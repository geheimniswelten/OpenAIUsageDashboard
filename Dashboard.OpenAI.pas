unit Dashboard.OpenAI;

interface

uses
  System.Net.HttpClient,
  Dashboard.Model;

type
  TOpenAIUsageClient = class
  private
    FAdminKey: string;
    FBaseUrl: string;
    FSpendingLimit: Double;
    FBillingDay: Integer;
    FHttpClient: THTTPClient;
    FCurrentRequest: IHTTPRequest;
    FCancelled: Integer;
    function RequestJson(const APath, AQuery: string): string;
    function RequestPages(const APath, AQuery: string): TObject;
    procedure ReadCosts(const ABuckets: TObject; const ASnapshot: TUsageSnapshot);
    procedure ReadCompletions(const ABuckets: TObject; const ASnapshot: TUsageSnapshot);
    procedure ReadService(const APath, AName, AValueField, AUnitText,
      ARequestField, AQuery: string; const ALatestOnly: Boolean;
      const ASnapshot: TUsageSnapshot);
    procedure TryReadSpendingLimit(const ASnapshot: TUsageSnapshot);
  public
    constructor Create(const AAdminKey: string; const ASpendingLimit: Double;
      const ABillingDay: Integer);
    destructor Destroy; override;
    procedure Cancel;
    function Fetch(const ASnapshot: TUsageSnapshot; out AError: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.Math,
  System.JSON,
  System.NetEncoding,
  System.Net.URLClient,
  System.SyncObjs,
  System.Generics.Collections;

type
  TModelAccumulator = class
  public
    Requests: Int64;
    Tokens: Int64;
  end;

function UrlEncode(const S: string): string;
begin
  Result := TNetEncoding.URL.Encode(S);
end;

function AppendQuery(const AQuery, AName, AValue: string): string;
begin
  Result := AQuery;
  if Result <> '' then
    Result := Result + '&';
  Result := Result + UrlEncode(AName) + '=' + UrlEncode(AValue);
end;

function HttpErrorText(const AStatus: Integer; const ABody: string): string;
var
  V: TJSONValue;
  O, E: TJSONObject;
  Detail: string;
begin
  Detail := '';
  V := TJSONObject.ParseJSONValue(ABody);
  try
    if V is TJSONObject then
    begin
      O := TJSONObject(V);
      E := O.GetValue('error') as TJSONObject;
      Detail := JsonString(E, 'message', '');
    end;
  finally
    V.Free;
  end;
  case AStatus of
    401: Result := 'OpenAI hat den Admin-Key abgelehnt (HTTP 401).';
    403: Result := 'Dem Key fehlt die Berechtigung für Organisations-Nutzungsdaten (HTTP 403).';
    429: Result := 'Das OpenAI-Abfragelimit ist vorübergehend erreicht (HTTP 429).';
  else
    Result := Format('OpenAI antwortet mit HTTP %d.', [AStatus]);
  end;
  if Detail <> '' then
    Result := Result + ' ' + Detail;
end;

function CurrentBillingStart(const ABillingDay: Integer): TDateTime;
var
  Y, M, D: Word;
begin
  DecodeDate(Date, Y, M, D);
  if D >= ABillingDay then
    Result := EncodeDate(Y, M, ABillingDay)
  else
    Result := IncMonth(EncodeDate(Y, M, 1), -1) + ABillingDay - 1;
end;

{ TOpenAIUsageClient }

constructor TOpenAIUsageClient.Create(const AAdminKey: string;
  const ASpendingLimit: Double; const ABillingDay: Integer);
begin
  inherited Create;
  FAdminKey := Trim(AAdminKey);
  FBaseUrl := 'https://api.openai.com/v1';
  FSpendingLimit := Max(0, ASpendingLimit);
  FBillingDay := EnsureRange(ABillingDay, 1, 28);
  FHttpClient := THTTPClient.Create;
  FHttpClient.ConnectionTimeout := 15000;
  FHttpClient.ResponseTimeout := 45000;
  FCancelled := 0;
end;

destructor TOpenAIUsageClient.Destroy;
begin
  Cancel;
  FHttpClient.Free;
  inherited;
end;

procedure TOpenAIUsageClient.Cancel;
var
  Request: IHTTPRequest;
begin
  TInterlocked.Exchange(FCancelled, 1);
  TMonitor.Enter(Self);
  try
    Request := FCurrentRequest;
  finally
    TMonitor.Exit(Self);
  end;
  if Request <> nil then
    Request.Cancel;
end;

function TOpenAIUsageClient.RequestJson(const APath, AQuery: string): string;
var
  Headers: TNetHeaders;
  Request: IHTTPRequest;
  Response: IHTTPResponse;
  Url: string;
begin
  if TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0 then
    raise EAbort.Create('OpenAI-Abfrage wurde beendet.');
  Url := FBaseUrl + APath;
  if AQuery <> '' then
    Url := Url + '?' + AQuery;
  SetLength(Headers, 3);
  Headers[0] := TNetHeader.Create('Authorization', 'Bearer ' + FAdminKey);
  Headers[1] := TNetHeader.Create('Accept', 'application/json');
  Headers[2] := TNetHeader.Create('User-Agent', 'OpenAIUsageDashboard/1.0');
  Request := FHttpClient.GetRequest('GET', Url);
  TMonitor.Enter(Self);
  try
    if TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0 then
      raise EAbort.Create('OpenAI-Abfrage wurde beendet.');
    FCurrentRequest := Request;
  finally
    TMonitor.Exit(Self);
  end;
  try
    Response := FHttpClient.Execute(Request, nil, Headers);
    Result := Response.ContentAsString(TEncoding.UTF8);
    if (Response.StatusCode < 200) or (Response.StatusCode > 299) then
      raise Exception.Create(HttpErrorText(Response.StatusCode, Result));
  finally
    TMonitor.Enter(Self);
    try
      if FCurrentRequest = Request then
        FCurrentRequest := nil;
    finally
      TMonitor.Exit(Self);
    end;
  end;
end;

function TOpenAIUsageClient.RequestPages(const APath, AQuery: string): TObject;
var
  Combined, Data: TJSONArray;
  Root: TJSONObject;
  Value, CopyValue: TJSONValue;
  Query, NextPage: string;
  I, Guard: Integer;
begin
  Combined := TJSONArray.Create;
  try
    Query := AQuery;
    Guard := 0;
    repeat
      Inc(Guard);
      if Guard > 100 then
        raise EInvalidOpException.Create('Zu viele OpenAI-Seiten in einer Antwort.');
      Value := TJSONObject.ParseJSONValue(RequestJson(APath, Query));
      try
        if not (Value is TJSONObject) then
          raise EConvertError.Create('OpenAI lieferte kein JSON-Objekt.');
        Root := TJSONObject(Value);
        Data := Root.GetValue('data') as TJSONArray;
        if Data <> nil then
          for I := 0 to Data.Count - 1 do
          begin
            CopyValue := TJSONObject.ParseJSONValue(Data.Items[I].ToJSON);
            Combined.AddElement(CopyValue);
          end;
        if JsonBool(Root, 'has_more') then
          NextPage := JsonString(Root, 'next_page', '')
        else
          NextPage := '';
      finally
        Value.Free;
      end;
      if NextPage <> '' then
        Query := AppendQuery(AQuery, 'page', NextPage);
    until NextPage = '';
    Result := Combined;
    Combined := nil;
  finally
    Combined.Free;
  end;
end;

procedure TOpenAIUsageClient.ReadCosts(const ABuckets: TObject;
  const ASnapshot: TUsageSnapshot);
var
  Buckets, Results: TJSONArray;
  Bucket, Item, Amount: TJSONObject;
  List: TList<TDailyCost>;
  Daily: TDailyCost;
  I, J: Integer;
  BucketStart: Int64;
begin
  Buckets := TJSONArray(ABuckets);
  List := TList<TDailyCost>.Create;
  try
    for I := 0 to Buckets.Count - 1 do
    begin
      Bucket := Buckets.Items[I] as TJSONObject;
      BucketStart := JsonInt64(Bucket, 'start_time');
      Daily.Day := DateOf(UnixToDateTime(BucketStart, False));
      Daily.Amount := 0;
      Results := Bucket.GetValue('results') as TJSONArray;
      if Results <> nil then
        for J := 0 to Results.Count - 1 do
        begin
          Item := Results.Items[J] as TJSONObject;
          Amount := Item.GetValue('amount') as TJSONObject;
          Daily.Amount := Daily.Amount + JsonFloat(Amount, 'value');
          if ASnapshot.OrganizationId = '' then
            ASnapshot.OrganizationId := JsonString(Item, 'organization_id', '');
          if ASnapshot.Currency = 'USD' then
            ASnapshot.Currency := UpperCase(JsonString(Amount, 'currency', 'USD'));
        end;
      List.Add(Daily);
    end;
    ASnapshot.DailyCosts := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TOpenAIUsageClient.ReadCompletions(const ABuckets: TObject;
  const ASnapshot: TUsageSnapshot);
var
  Buckets, Results: TJSONArray;
  Bucket, Item: TJSONObject;
  Models: TObjectDictionary<string, TModelAccumulator>;
  Acc: TModelAccumulator;
  Pair: TPair<string, TModelAccumulator>;
  I, J, K: Integer;
  DayValue, UtcToday: TDateTime;
  ModelName: string;
  Requests, Tokens: Int64;
  Temp: TModelUsage;
begin
  Buckets := TJSONArray(ABuckets);
  Models := TObjectDictionary<string, TModelAccumulator>.Create([doOwnsValues]);
  try
    UtcToday := DateOf(TTimeZone.Local.ToUniversalTime(Now));
    for I := 0 to Buckets.Count - 1 do
    begin
      Bucket := Buckets.Items[I] as TJSONObject;
      DayValue := DateOf(UnixToDateTime(JsonInt64(Bucket, 'start_time'), False));
      Results := Bucket.GetValue('results') as TJSONArray;
      if Results = nil then
        Continue;
      for J := 0 to Results.Count - 1 do
      begin
        Item := Results.Items[J] as TJSONObject;
        Requests := JsonInt64(Item, 'num_model_requests');
        Tokens := JsonInt64(Item, 'input_tokens') + JsonInt64(Item, 'output_tokens');
        ASnapshot.Requests7Days := ASnapshot.Requests7Days + Requests;
        ASnapshot.Tokens7Days := ASnapshot.Tokens7Days + Tokens;
        if SameDate(DayValue, UtcToday) then
        begin
          ASnapshot.RequestsToday := ASnapshot.RequestsToday + Requests;
          ASnapshot.TokensToday := ASnapshot.TokensToday + Tokens;
        end;
        ModelName := JsonString(Item, 'model', '(ohne Modellname)');
        if not Models.TryGetValue(ModelName, Acc) then
        begin
          Acc := TModelAccumulator.Create;
          Models.Add(ModelName, Acc);
        end;
        Inc(Acc.Requests, Requests);
        Inc(Acc.Tokens, Tokens);
      end;
    end;
    SetLength(ASnapshot.Models, Models.Count);
    I := 0;
    for Pair in Models do
    begin
      ASnapshot.Models[I].Model := Pair.Key;
      ASnapshot.Models[I].Requests := Pair.Value.Requests;
      ASnapshot.Models[I].Tokens := Pair.Value.Tokens;
      Inc(I);
    end;
    for I := 0 to High(ASnapshot.Models) - 1 do
      for K := I + 1 to High(ASnapshot.Models) do
        if ASnapshot.Models[K].Tokens > ASnapshot.Models[I].Tokens then
        begin
          Temp := ASnapshot.Models[I];
          ASnapshot.Models[I] := ASnapshot.Models[K];
          ASnapshot.Models[K] := Temp;
        end;
  finally
    Models.Free;
  end;
end;

procedure TOpenAIUsageClient.ReadService(const APath, AName, AValueField,
  AUnitText, ARequestField, AQuery: string; const ALatestOnly: Boolean;
  const ASnapshot: TUsageSnapshot);
var
  Buckets, Results: TJSONArray;
  Bucket, Item: TJSONObject;
  Service: TServiceUsage;
  I, J, Index: Integer;
  PageObject: TObject;
begin
  Service.Name := AName;
  Service.Value := 0;
  Service.UnitText := AUnitText;
  Service.Requests := 0;
  Service.Available := False;
  try
    PageObject := RequestPages(APath, AQuery);
    try
      Buckets := TJSONArray(PageObject);
      for I := 0 to Buckets.Count - 1 do
      begin
        Bucket := Buckets.Items[I] as TJSONObject;
        Results := Bucket.GetValue('results') as TJSONArray;
        if Results = nil then
          Continue;
        if ALatestOnly and (I < Buckets.Count - 1) then
          Continue;
        if ALatestOnly then
          Service.Value := 0;
        for J := 0 to Results.Count - 1 do
        begin
          Item := Results.Items[J] as TJSONObject;
          Service.Value := Service.Value + JsonFloat(Item, AValueField);
          if ARequestField <> '' then
            Service.Requests := Service.Requests + JsonInt64(Item, ARequestField);
        end;
      end;
      Service.Available := True;
    finally
      PageObject.Free;
    end;
  except
    { Additional services are independent.  One unavailable endpoint does not
      discard the main costs/completions snapshot. }
  end;
  Index := Length(ASnapshot.Services);
  SetLength(ASnapshot.Services, Index + 1);
  ASnapshot.Services[Index] := Service;
end;

procedure TOpenAIUsageClient.TryReadSpendingLimit(const ASnapshot: TUsageSnapshot);
var
  V: TJSONValue;
  O, Data: TJSONObject;
  S: string;
begin
  if FSpendingLimit > 0 then
  begin
    ASnapshot.SpendingLimit := FSpendingLimit;
    Exit;
  end;
  try
    S := RequestJson('/organization/spend_limit', '');
    V := TJSONObject.ParseJSONValue(S);
    try
      if V is TJSONObject then
      begin
        O := TJSONObject(V);
        ASnapshot.SpendingLimit := JsonFloat(O, 'limit', 0);
        if ASnapshot.SpendingLimit <= 0 then
          ASnapshot.SpendingLimit := JsonFloat(O, 'spend_limit', 0);
        if ASnapshot.SpendingLimit <= 0 then
          ASnapshot.SpendingLimit := JsonFloat(O, 'monthly_limit', 0);
        Data := O.GetValue('data') as TJSONObject;
        if (ASnapshot.SpendingLimit <= 0) and (Data <> nil) then
          ASnapshot.SpendingLimit := JsonFloat(Data, 'limit', 0);
      end;
    finally
      V.Free;
    end;
  except
    ASnapshot.SpendingLimit := 0;
  end;
end;

function TOpenAIUsageClient.Fetch(const ASnapshot: TUsageSnapshot;
  out AError: string): Boolean;
var
  Costs, Completions: TObject;
  UtcNow, StartDate, PeriodStart: TDateTime;
  CostQuery, UsageQuery: string;
  StartUnix: Int64;
begin
  TInterlocked.Exchange(FCancelled, 0);
  Result := False;
  AError := '';
  if ASnapshot = nil then
  begin
    AError := 'Interner Fehler: kein Datenziel.';
    Exit;
  end;
  if FAdminKey = '' then
  begin
    AError := 'Noch kein OpenAI-Admin-Key gespeichert.';
    Exit;
  end;
  try
    ASnapshot.Clear;
    UtcNow := TTimeZone.Local.ToUniversalTime(Now);
    PeriodStart := CurrentBillingStart(FBillingDay);
    ASnapshot.PeriodStart := PeriodStart;
    ASnapshot.PeriodEnd := IncMonth(PeriodStart, 1);
    StartDate := Min(DateOf(UtcNow) - 29, TTimeZone.Local.ToUniversalTime(PeriodStart));
    StartUnix := DateTimeToUnix(StartDate, False);
    CostQuery := 'start_time=' + IntToStr(StartUnix) + '&bucket_width=1d&limit=31';
    Costs := RequestPages('/organization/costs', CostQuery);
    try
      ReadCosts(Costs, ASnapshot);
    finally
      Costs.Free;
    end;

    StartUnix := DateTimeToUnix(DateOf(UtcNow) - 6, False);
    UsageQuery := 'start_time=' + IntToStr(StartUnix) +
      '&bucket_width=1d&limit=7&group_by=model';
    Completions := RequestPages('/organization/usage/completions', UsageQuery);
    try
      ReadCompletions(Completions, ASnapshot);
    finally
      Completions.Free;
    end;

    UsageQuery := 'start_time=' + IntToStr(StartUnix) + '&bucket_width=1d&limit=7';
    ReadService('/organization/usage/images', 'Bilder', 'images', '',
      'num_model_requests', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/embeddings', 'Embeddings', 'input_tokens', 'Tokens',
      'num_model_requests', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/web_search_calls', 'Websuche', 'num_requests', '',
      'num_model_requests', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/file_search_calls', 'Dateisuche', 'num_requests', '',
      '', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/audio_transcriptions', 'Transkription', 'seconds', 'Sek.',
      'num_model_requests', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/audio_speeches', 'Sprachausgabe', 'characters', 'Zeichen',
      'num_model_requests', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/code_interpreter_sessions', 'Code Interpreter',
      'num_sessions', 'Sitzungen', '', UsageQuery, False, ASnapshot);
    ReadService('/organization/usage/vector_stores', 'Vector Stores', 'usage_bytes', 'B',
      '', UsageQuery, True, ASnapshot);
    ReadService('/organization/usage/moderations', 'Moderation', 'input_tokens', 'Tokens',
      'num_model_requests', UsageQuery, False, ASnapshot);
    TryReadSpendingLimit(ASnapshot);
    ASnapshot.LastUpdated := Now;
    ASnapshot.StatusText := 'Aktuell';
    ASnapshot.SourceText := 'OpenAI API Platform';
    ASnapshot.Recalculate;
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      ASnapshot.StatusText := AError;
    end;
  end;
end;

end.
