unit Dashboard.Model;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON;

type
  TDailyCost = record
    Day: TDateTime;
    Amount: Double;
    HasCostData: Boolean;
  end;

  TModelUsage = record
    Model: string;
    Requests: Int64;
    Tokens: Int64;
  end;

  TServiceUsage = record
    Name: string;
    Value: Double;
    UnitText: string;
    Requests: Int64;
    Available: Boolean;
  end;

  TRateLimitWindow = record
    Id: string;
    Name: string;
    WindowName: string;
    UsedPercent: Double;
    WindowMinutes: Integer;
    ResetsAt: TDateTime;
    Available: Boolean;
  end;

  TForecastPoint = record
    Day: TDateTime;
    Cumulative: Double;
    StartsNewPeriod: Boolean;
  end;

  TUsageSnapshot = class
  public
    LastUpdated: TDateTime;
    OrganizationId: string;
    Currency: string;
    Cost30Days: Double;
    CostToday: Double;
    CostTodayAvailable: Boolean;
    Requests7Days: Int64;
    RequestsToday: Int64;
    Tokens7Days: Int64;
    TokensToday: Int64;
    SpendingLimit: Double;
    PeriodStart: TDateTime;
    PeriodEnd: TDateTime;
    PeriodCost: Double;
    ForecastDailyRate: Double;
    StatusText: string;
    SourceText: string;
    DailyCosts: TArray<TDailyCost>;
    Models: TArray<TModelUsage>;
    Services: TArray<TServiceUsage>;
    RateLimits: TArray<TRateLimitWindow>;
    Forecast: TArray<TForecastPoint>;
    CodexLifetimeTokens: Int64;
    CodexTodayTokens: Int64;
    CodexSevenDayTokens: Int64;
    CodexMonthTokens: Int64;
    CodexResetCredits: Integer;
    CodexUsageAvailable: Boolean;
    CodexLifetimeAvailable: Boolean;
    CodexDailyUsageAvailable: Boolean;
    CodexTodayUsageAvailable: Boolean;
    CodexRateLimitsAvailable: Boolean;
    CodexError: string;
    constructor Create;
    procedure Clear;
    procedure Assign(const ASource: TUsageSnapshot);
    procedure Recalculate(const AAsOfUtc: TDateTime = 0);
    procedure MakeDemo;
    function ToJson: string;
    procedure FromJson(const AJson: string);
  end;

function JsonString(const AObject: TJSONObject; const AName, ADefault: string): string;
function JsonFloat(const AObject: TJSONObject; const AName: string; const ADefault: Double = 0): Double;
function JsonInt64(const AObject: TJSONObject; const AName: string; const ADefault: Int64 = 0): Int64;
function JsonBool(const AObject: TJSONObject; const AName: string; const ADefault: Boolean = False): Boolean;

implementation

uses
  System.Math,
  System.Generics.Collections;

function JsonString(const AObject: TJSONObject; const AName, ADefault: string): string;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  V := AObject.GetValue(AName);
  if (V <> nil) and not (V is TJSONNull) then
    Result := V.Value;
end;

function JsonFloat(const AObject: TJSONObject; const AName: string; const ADefault: Double): Double;
var
  V: TJSONValue;
  FS: TFormatSettings;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  V := AObject.GetValue(AName);
  if V is TJSONNumber then
    Exit(TJSONNumber(V).AsDouble);
  if V <> nil then
  begin
    FS := TFormatSettings.Invariant;
    TryStrToFloat(V.Value, Result, FS);
  end;
end;

function JsonInt64(const AObject: TJSONObject; const AName: string; const ADefault: Int64): Int64;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  V := AObject.GetValue(AName);
  if V is TJSONNumber then
    Result := Trunc(TJSONNumber(V).AsDouble)
  else if V <> nil then
    TryStrToInt64(V.Value, Result);
end;

function JsonBool(const AObject: TJSONObject; const AName: string; const ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  V := AObject.GetValue(AName);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else if V <> nil then
    Result := SameText(V.Value, 'true') or (V.Value = '1');
end;

procedure AddDatePair(const AObject: TJSONObject; const AName: string; const AValue: TDateTime);
begin
  if AValue > 0 then
    AObject.AddPair(AName, DateToISO8601(AValue, False))
  else
    AObject.AddPair(AName, '');
end;

function ReadDate(const AObject: TJSONObject; const AName: string): TDateTime;
var
  S: string;
begin
  Result := 0;
  S := JsonString(AObject, AName, '');
  if S <> '' then
    TryISO8601ToDate(S, Result, False);
end;

procedure AddCalendarDay(const AObject: TJSONObject; const AName: string;
  const AValue: TDateTime);
begin
  AObject.AddPair(AName, FormatDateTime('yyyy-mm-dd', AValue));
end;

function ReadCalendarDay(const AObject: TJSONObject; const AName: string): TDateTime;
var
  S: string;
  Y, M, D: Integer;
begin
  Result := 0;
  S := JsonString(AObject, AName, '');
  { Calendar labels are not instants. Also accept the date prefix in older
    snapshots, without moving its day into the viewer's time zone. }
  if (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') and
     TryStrToInt(Copy(S, 1, 4), Y) and TryStrToInt(Copy(S, 6, 2), M) and
     TryStrToInt(Copy(S, 9, 2), D) then
    TryEncodeDate(Y, M, D, Result);
end;

{ TUsageSnapshot }

constructor TUsageSnapshot.Create;
begin
  inherited Create;
  Clear;
end;

procedure TUsageSnapshot.Clear;
begin
  LastUpdated := 0;
  OrganizationId := '';
  Currency := 'USD';
  Cost30Days := 0;
  CostToday := 0;
  CostTodayAvailable := False;
  Requests7Days := 0;
  RequestsToday := 0;
  Tokens7Days := 0;
  TokensToday := 0;
  SpendingLimit := 0;
  PeriodStart := StartOfTheMonth(Date);
  PeriodEnd := IncMonth(PeriodStart, 1);
  PeriodCost := 0;
  ForecastDailyRate := 0;
  StatusText := 'Noch keine Daten';
  SourceText := '';
  DailyCosts := nil;
  Models := nil;
  Services := nil;
  RateLimits := nil;
  Forecast := nil;
  CodexLifetimeTokens := 0;
  CodexTodayTokens := 0;
  CodexSevenDayTokens := 0;
  CodexMonthTokens := 0;
  CodexResetCredits := 0;
  CodexUsageAvailable := False;
  CodexLifetimeAvailable := False;
  CodexDailyUsageAvailable := False;
  CodexTodayUsageAvailable := False;
  CodexRateLimitsAvailable := False;
  CodexError := '';
end;

procedure TUsageSnapshot.Assign(const ASource: TUsageSnapshot);
begin
  if ASource = nil then
    Exit;
  LastUpdated := ASource.LastUpdated;
  OrganizationId := ASource.OrganizationId;
  Currency := ASource.Currency;
  Cost30Days := ASource.Cost30Days;
  CostToday := ASource.CostToday;
  CostTodayAvailable := ASource.CostTodayAvailable;
  Requests7Days := ASource.Requests7Days;
  RequestsToday := ASource.RequestsToday;
  Tokens7Days := ASource.Tokens7Days;
  TokensToday := ASource.TokensToday;
  SpendingLimit := ASource.SpendingLimit;
  PeriodStart := ASource.PeriodStart;
  PeriodEnd := ASource.PeriodEnd;
  PeriodCost := ASource.PeriodCost;
  ForecastDailyRate := ASource.ForecastDailyRate;
  StatusText := ASource.StatusText;
  SourceText := ASource.SourceText;
  DailyCosts := Copy(ASource.DailyCosts);
  Models := Copy(ASource.Models);
  Services := Copy(ASource.Services);
  RateLimits := Copy(ASource.RateLimits);
  Forecast := Copy(ASource.Forecast);
  CodexLifetimeTokens := ASource.CodexLifetimeTokens;
  CodexTodayTokens := ASource.CodexTodayTokens;
  CodexSevenDayTokens := ASource.CodexSevenDayTokens;
  CodexMonthTokens := ASource.CodexMonthTokens;
  CodexResetCredits := ASource.CodexResetCredits;
  CodexUsageAvailable := ASource.CodexUsageAvailable;
  CodexLifetimeAvailable := ASource.CodexLifetimeAvailable;
  CodexDailyUsageAvailable := ASource.CodexDailyUsageAvailable;
  CodexTodayUsageAvailable := ASource.CodexTodayUsageAvailable;
  CodexRateLimitsAvailable := ASource.CodexRateLimitsAvailable;
  CodexError := ASource.CodexError;
end;

procedure TUsageSnapshot.Recalculate(const AAsOfUtc: TDateTime);
var
  I, N, J: Integer;
  TodayValue, DayValue, Running, SumX, SumY, SumXY, SumXX, Slope,
    DailyAmount, XValue: Double;
  RegressionDay, TargetDay, ForecastPeriodStart, ForecastPeriodEnd: TDateTime;
begin
  if AAsOfUtc > 0 then
    TodayValue := DateOf(AAsOfUtc)
  else if LastUpdated > 0 then
    TodayValue := DateOf(TTimeZone.Local.ToUniversalTime(LastUpdated))
  else
    TodayValue := DateOf(TTimeZone.Local.ToUniversalTime(Now));
  Cost30Days := 0;
  CostToday := 0;
  CostTodayAvailable := False;
  PeriodCost := 0;
  for I := 0 to High(DailyCosts) do
  begin
    DayValue := Trunc(DailyCosts[I].Day);
    if (DayValue >= TodayValue - 29) and (DayValue <= TodayValue) then
      Cost30Days := Cost30Days + DailyCosts[I].Amount;
    if SameDate(DayValue, TodayValue) then
    begin
      CostToday := CostToday + DailyCosts[I].Amount;
      CostTodayAvailable := CostTodayAvailable or DailyCosts[I].HasCostData or
        (DailyCosts[I].Amount <> 0);
    end;
    if (DayValue >= Trunc(PeriodStart)) and (DayValue < Trunc(PeriodEnd)) then
      PeriodCost := PeriodCost + DailyCosts[I].Amount;
  end;

  { Least-squares slope of cumulative spend.  Today's incomplete bucket is
    intentionally excluded from the forecast, as requested. }
  N := 0;
  Running := 0;
  SumX := 0;
  SumY := 0;
  SumXY := 0;
  SumXX := 0;
  RegressionDay := Trunc(PeriodStart);
  while RegressionDay < TodayValue do
  begin
    DailyAmount := 0;
    for I := 0 to High(DailyCosts) do
      if SameDate(DailyCosts[I].Day, RegressionDay) then
        DailyAmount := DailyAmount + Max(0, DailyCosts[I].Amount);
    Running := Running + DailyAmount;
    XValue := DaysBetween(RegressionDay, Trunc(PeriodStart));
    SumX := SumX + XValue;
    SumY := SumY + Running;
    SumXY := SumXY + XValue * Running;
    SumXX := SumXX + XValue * XValue;
    Inc(N);
    RegressionDay := IncDay(RegressionDay, 1);
  end;
  if (N >= 2) and ((N * SumXX - Sqr(SumX)) <> 0) then
    Slope := (N * SumXY - SumX * SumY) / (N * SumXX - Sqr(SumX))
  else if N > 0 then
    Slope := Running / N
  else
    Slope := 0;
  ForecastDailyRate := Max(0, Slope);

  SetLength(Forecast, 4);
  ForecastPeriodStart := PeriodStart;
  ForecastPeriodEnd := PeriodEnd;
  for I := 0 to 3 do
  begin
    TargetDay := IncDay(TodayValue, (I + 1) * 7);
    while TargetDay >= ForecastPeriodEnd do
    begin
      ForecastPeriodStart := ForecastPeriodEnd;
      ForecastPeriodEnd := IncMonth(ForecastPeriodEnd, 1);
    end;
    Forecast[I].Day := TargetDay;
    Forecast[I].StartsNewPeriod := ForecastPeriodStart >= PeriodEnd;
    if Forecast[I].StartsNewPeriod then
      Forecast[I].Cumulative := ForecastDailyRate * Max(0, DaysBetween(TargetDay, ForecastPeriodStart))
    else
    begin
      J := DaysBetween(TargetDay, TodayValue);
      Forecast[I].Cumulative := PeriodCost - CostToday + ForecastDailyRate * J;
    end;
  end;
end;

procedure TUsageSnapshot.MakeDemo;
const
  DemoModels: array[0..4] of string =
    ('gpt-5.6-terra', 'gpt-5.4-mini', 'gpt-4o-mini-2024-07-18',
     'gpt-5.3-codex-spark', 'gpt-4.1-mini');
var
  I: Integer;
  UtcToday: TDateTime;
begin
  Clear;
  LastUpdated := Now;
  UtcToday := DateOf(TTimeZone.Local.ToUniversalTime(LastUpdated));
  OrganizationId := 'org-demo';
  SpendingLimit := 30;
  PeriodStart := StartOfTheMonth(UtcToday);
  PeriodEnd := IncMonth(PeriodStart, 1);
  SetLength(DailyCosts, 30);
  for I := 0 to High(DailyCosts) do
  begin
    DailyCosts[I].Day := IncDay(UtcToday, I - High(DailyCosts));
    DailyCosts[I].HasCostData := True;
    if DayOfTheWeek(DailyCosts[I].Day) >= 6 then
      DailyCosts[I].Amount := 0.05 + 0.03 * (I mod 3)
    else
      DailyCosts[I].Amount := 0.18 + 0.55 * Abs(Sin(I * 1.37));
  end;
  SetLength(Models, Length(DemoModels));
  for I := 0 to High(Models) do
  begin
    Models[I].Model := DemoModels[I];
    Models[I].Requests := 170 - I * 31;
    Models[I].Tokens := 2900000 div (I + 1);
  end;
  Requests7Days := 198;
  RequestsToday := 82;
  Tokens7Days := 2900000;
  TokensToday := 1500000;
  SetLength(Services, 6);
  Services[0].Name := 'Bilder';
  Services[0].UnitText := '';
  Services[0].Available := True;
  Services[1].Name := 'Embeddings';
  Services[1].Value := 426;
  Services[1].UnitText := 'Tokens';
  Services[1].Requests := 40;
  Services[1].Available := True;
  Services[2].Name := 'Websuche';
  Services[2].Available := True;
  Services[3].Name := 'Dateisuche';
  Services[3].Available := True;
  Services[4].Name := 'Transkription';
  Services[4].UnitText := 'Sek.';
  Services[4].Available := True;
  Services[5].Name := 'Code Interpreter';
  Services[5].UnitText := 'Sitzungen';
  Services[5].Available := True;
  SetLength(RateLimits, 2);
  RateLimits[0].Id := 'codex';
  RateLimits[0].Name := 'Codex';
  RateLimits[0].WindowName := '7 Tage';
  RateLimits[0].UsedPercent := 66;
  RateLimits[0].WindowMinutes := 10080;
  RateLimits[0].ResetsAt := IncDay(Now, 2);
  RateLimits[0].Available := True;
  RateLimits[1].Id := 'codex-secondary';
  RateLimits[1].Name := 'Codex · sekundär';
  RateLimits[1].WindowName := '5 Stunden';
  RateLimits[1].UsedPercent := 18;
  RateLimits[1].WindowMinutes := 300;
  RateLimits[1].ResetsAt := IncHour(Now, 3);
  RateLimits[1].Available := True;
  CodexLifetimeTokens := 40300000000;
  CodexTodayTokens := 141600000;
  CodexSevenDayTokens := 4100000000;
  CodexMonthTokens := 1300000000;
  CodexUsageAvailable := True;
  CodexLifetimeAvailable := True;
  CodexDailyUsageAvailable := True;
  CodexTodayUsageAvailable := True;
  CodexRateLimitsAvailable := True;
  StatusText := 'Demo-Daten';
  SourceText := 'Integrierte Vorschau';
  Recalculate;
end;

function TUsageSnapshot.ToJson: string;
var
  Root, Item: TJSONObject;
  A: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    AddDatePair(Root, 'lastUpdated', LastUpdated);
    Root.AddPair('organizationId', OrganizationId);
    Root.AddPair('currency', Currency);
    Root.AddPair('cost30Days', TJSONNumber.Create(Cost30Days));
    Root.AddPair('costToday', TJSONNumber.Create(CostToday));
    Root.AddPair('costTodayAvailable', TJSONBool.Create(CostTodayAvailable));
    Root.AddPair('requests7Days', TJSONNumber.Create(Requests7Days));
    Root.AddPair('requestsToday', TJSONNumber.Create(RequestsToday));
    Root.AddPair('tokens7Days', TJSONNumber.Create(Tokens7Days));
    Root.AddPair('tokensToday', TJSONNumber.Create(TokensToday));
    Root.AddPair('spendingLimit', TJSONNumber.Create(SpendingLimit));
    AddCalendarDay(Root, 'periodStart', PeriodStart);
    AddCalendarDay(Root, 'periodEnd', PeriodEnd);
    Root.AddPair('periodCost', TJSONNumber.Create(PeriodCost));
    Root.AddPair('forecastDailyRate', TJSONNumber.Create(ForecastDailyRate));
    Root.AddPair('statusText', StatusText);
    Root.AddPair('sourceText', SourceText);
    Root.AddPair('codexLifetimeTokens', TJSONNumber.Create(CodexLifetimeTokens));
    Root.AddPair('codexTodayTokens', TJSONNumber.Create(CodexTodayTokens));
    Root.AddPair('codexSevenDayTokens', TJSONNumber.Create(CodexSevenDayTokens));
    Root.AddPair('codexMonthTokens', TJSONNumber.Create(CodexMonthTokens));
    Root.AddPair('codexResetCredits', TJSONNumber.Create(CodexResetCredits));
    Root.AddPair('codexUsageAvailable', TJSONBool.Create(CodexUsageAvailable));
    Root.AddPair('codexLifetimeAvailable', TJSONBool.Create(CodexLifetimeAvailable));
    Root.AddPair('codexDailyUsageAvailable', TJSONBool.Create(CodexDailyUsageAvailable));
    Root.AddPair('codexTodayUsageAvailable', TJSONBool.Create(CodexTodayUsageAvailable));
    Root.AddPair('codexRateLimitsAvailable', TJSONBool.Create(CodexRateLimitsAvailable));
    Root.AddPair('codexError', CodexError);

    A := TJSONArray.Create;
    Root.AddPair('dailyCosts', A);
    for I := 0 to High(DailyCosts) do
    begin
      Item := TJSONObject.Create;
      AddCalendarDay(Item, 'day', DailyCosts[I].Day);
      Item.AddPair('amount', TJSONNumber.Create(DailyCosts[I].Amount));
      Item.AddPair('hasCostData', TJSONBool.Create(DailyCosts[I].HasCostData));
      A.AddElement(Item);
    end;
    A := TJSONArray.Create;
    Root.AddPair('models', A);
    for I := 0 to High(Models) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('model', Models[I].Model);
      Item.AddPair('requests', TJSONNumber.Create(Models[I].Requests));
      Item.AddPair('tokens', TJSONNumber.Create(Models[I].Tokens));
      A.AddElement(Item);
    end;
    A := TJSONArray.Create;
    Root.AddPair('services', A);
    for I := 0 to High(Services) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Services[I].Name);
      Item.AddPair('value', TJSONNumber.Create(Services[I].Value));
      Item.AddPair('unit', Services[I].UnitText);
      Item.AddPair('requests', TJSONNumber.Create(Services[I].Requests));
      Item.AddPair('available', TJSONBool.Create(Services[I].Available));
      A.AddElement(Item);
    end;
    A := TJSONArray.Create;
    Root.AddPair('rateLimits', A);
    for I := 0 to High(RateLimits) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('id', RateLimits[I].Id);
      Item.AddPair('name', RateLimits[I].Name);
      Item.AddPair('windowName', RateLimits[I].WindowName);
      Item.AddPair('usedPercent', TJSONNumber.Create(RateLimits[I].UsedPercent));
      Item.AddPair('windowMinutes', TJSONNumber.Create(RateLimits[I].WindowMinutes));
      AddDatePair(Item, 'resetsAt', RateLimits[I].ResetsAt);
      Item.AddPair('available', TJSONBool.Create(RateLimits[I].Available));
      A.AddElement(Item);
    end;
    A := TJSONArray.Create;
    Root.AddPair('forecast', A);
    for I := 0 to High(Forecast) do
    begin
      Item := TJSONObject.Create;
      AddCalendarDay(Item, 'day', Forecast[I].Day);
      Item.AddPair('cumulative', TJSONNumber.Create(Forecast[I].Cumulative));
      Item.AddPair('startsNewPeriod', TJSONBool.Create(Forecast[I].StartsNewPeriod));
      A.AddElement(Item);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure TUsageSnapshot.FromJson(const AJson: string);
var
  Root, Item: TJSONObject;
  Value: TJSONValue;
  A: TJSONArray;
  I: Integer;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      raise EConvertError.Create('Ungültige Dashboard-Antwort');
    Root := TJSONObject(Value);
    Clear;
    LastUpdated := ReadDate(Root, 'lastUpdated');
    OrganizationId := JsonString(Root, 'organizationId', '');
    Currency := JsonString(Root, 'currency', 'USD');
    Cost30Days := JsonFloat(Root, 'cost30Days');
    CostToday := JsonFloat(Root, 'costToday');
    CostTodayAvailable := JsonBool(Root, 'costTodayAvailable', CostToday <> 0);
    Requests7Days := JsonInt64(Root, 'requests7Days');
    RequestsToday := JsonInt64(Root, 'requestsToday');
    Tokens7Days := JsonInt64(Root, 'tokens7Days');
    TokensToday := JsonInt64(Root, 'tokensToday');
    SpendingLimit := JsonFloat(Root, 'spendingLimit');
    PeriodStart := ReadCalendarDay(Root, 'periodStart');
    PeriodEnd := ReadCalendarDay(Root, 'periodEnd');
    PeriodCost := JsonFloat(Root, 'periodCost');
    ForecastDailyRate := JsonFloat(Root, 'forecastDailyRate');
    StatusText := JsonString(Root, 'statusText', '');
    SourceText := JsonString(Root, 'sourceText', '');
    CodexLifetimeTokens := JsonInt64(Root, 'codexLifetimeTokens');
    CodexTodayTokens := JsonInt64(Root, 'codexTodayTokens');
    CodexSevenDayTokens := JsonInt64(Root, 'codexSevenDayTokens');
    CodexMonthTokens := JsonInt64(Root, 'codexMonthTokens');
    CodexResetCredits := JsonInt64(Root, 'codexResetCredits');
    CodexUsageAvailable := JsonBool(Root, 'codexUsageAvailable', CodexLifetimeTokens > 0);
    CodexLifetimeAvailable := JsonBool(Root, 'codexLifetimeAvailable', CodexUsageAvailable);
    CodexDailyUsageAvailable := JsonBool(Root, 'codexDailyUsageAvailable', CodexUsageAvailable);
    CodexTodayUsageAvailable := JsonBool(Root, 'codexTodayUsageAvailable', CodexDailyUsageAvailable);
    CodexRateLimitsAvailable := JsonBool(Root, 'codexRateLimitsAvailable');
    CodexError := JsonString(Root, 'codexError', '');

    A := Root.GetValue('dailyCosts') as TJSONArray;
    if A <> nil then
    begin
      SetLength(DailyCosts, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        Item := A.Items[I] as TJSONObject;
        DailyCosts[I].Day := ReadCalendarDay(Item, 'day');
        DailyCosts[I].Amount := JsonFloat(Item, 'amount');
        DailyCosts[I].HasCostData := JsonBool(Item, 'hasCostData', DailyCosts[I].Amount <> 0);
      end;
    end;
    A := Root.GetValue('models') as TJSONArray;
    if A <> nil then
    begin
      SetLength(Models, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        Item := A.Items[I] as TJSONObject;
        Models[I].Model := JsonString(Item, 'model', '');
        Models[I].Requests := JsonInt64(Item, 'requests');
        Models[I].Tokens := JsonInt64(Item, 'tokens');
      end;
    end;
    A := Root.GetValue('services') as TJSONArray;
    if A <> nil then
    begin
      SetLength(Services, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        Item := A.Items[I] as TJSONObject;
        Services[I].Name := JsonString(Item, 'name', '');
        Services[I].Value := JsonFloat(Item, 'value');
        Services[I].UnitText := JsonString(Item, 'unit', '');
        Services[I].Requests := JsonInt64(Item, 'requests');
        Services[I].Available := JsonBool(Item, 'available');
      end;
    end;
    A := Root.GetValue('rateLimits') as TJSONArray;
    if A <> nil then
    begin
      SetLength(RateLimits, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        Item := A.Items[I] as TJSONObject;
        RateLimits[I].Id := JsonString(Item, 'id', '');
        RateLimits[I].Name := JsonString(Item, 'name', '');
        RateLimits[I].WindowName := JsonString(Item, 'windowName', '');
        RateLimits[I].UsedPercent := JsonFloat(Item, 'usedPercent');
        RateLimits[I].WindowMinutes := JsonInt64(Item, 'windowMinutes');
        RateLimits[I].ResetsAt := ReadDate(Item, 'resetsAt');
        RateLimits[I].Available := JsonBool(Item, 'available');
      end;
    end;
    A := Root.GetValue('forecast') as TJSONArray;
    if A <> nil then
    begin
      SetLength(Forecast, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        Item := A.Items[I] as TJSONObject;
        Forecast[I].Day := ReadCalendarDay(Item, 'day');
        Forecast[I].Cumulative := JsonFloat(Item, 'cumulative');
        Forecast[I].StartsNewPeriod := JsonBool(Item, 'startsNewPeriod');
      end;
    end;
  finally
    Value.Free;
  end;
end;

end.
