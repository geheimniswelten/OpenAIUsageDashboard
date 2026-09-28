program OpenAITests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.OpenAI in '..\Dashboard.OpenAI.pas';

type
  TCostFixture = (cfReported, cfMissing, cfEmpty, cfNull, cfZero);
  TUsageFixture = (ufReported, ufZero, ufNull, ufMissingTokens, ufEmpty, ufMissing, ufNegative, ufOverflow, ufLarge);

  TFixtureClient = class(TOpenAIUsageClient)
  public
    UtcNow: TDateTime;
    CostFixture: TCostFixture;
    UsageFixture: TUsageFixture;
    CostQuery, CompletionQuery, ServiceQuery: string;
    CostResponse, CompletionResponse, SpendingLimitResponse: string;
    VectorStoresResponse: string;
  protected
    function CurrentUtcTime: TDateTime; override;
    function RequestJson(const APath, AQuery: string): string; override;
  end;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function TFixtureClient.CurrentUtcTime: TDateTime;
begin
  Result := UtcNow;
end;

function TFixtureClient.RequestJson(const APath, AQuery: string): string;
var
  TodayStart, YesterdayStart, FirstStart, WeekStart: string;
  TodayResults: string;
begin
  if (APath = '/organization/costs') and (CostResponse <> '') then
    Exit(CostResponse);
  if (APath = '/organization/usage/completions') and (CompletionResponse <> '') then
    Exit(CompletionResponse);
  if (APath = '/organization/spend_limit') and (SpendingLimitResponse <> '') then
    Exit(SpendingLimitResponse);
  if (APath = '/organization/usage/vector_stores') and (VectorStoresResponse <> '') then
    Exit(VectorStoresResponse);
  TodayStart := IntToStr(DateTimeToUnix(DateOf(UtcNow), True));
  YesterdayStart := IntToStr(DateTimeToUnix(DateOf(UtcNow) - 1, True));
  FirstStart := IntToStr(DateTimeToUnix(DateOf(UtcNow) - 13, True));
  WeekStart := IntToStr(DateTimeToUnix(DateOf(UtcNow) - 6, True));
  if APath = '/organization/costs' then
  begin
    CostQuery := AQuery;
    Result := '{"data":[{"start_time":' + YesterdayStart +
      ',"results":[{"amount":{"value":2.45,"currency":"usd"}}]}';
    case CostFixture of
      cfReported: TodayResults := '[{"amount":{"value":0.97,"currency":"usd"}}]';
      cfEmpty: TodayResults := '[]';
      cfNull: TodayResults := '[{"amount":{"value":null,"currency":"usd"}}]';
      cfZero: TodayResults := '[{"amount":{"value":0,"currency":"usd"}}]';
    end;
    if CostFixture <> cfMissing then
      Result := Result + ',{"start_time":' + TodayStart +
        ',"results":' + TodayResults + '}';
    Result := Result + '],"has_more":false}';
  end
  else if APath = '/organization/usage/completions' then
  begin
    if Pos('&page=second', AQuery) > 0 then
      Exit('{"data":[{"start_time":' + TodayStart +
        ',"results":[{"model":"test-model","num_model_requests":4,' +
        '"input_tokens":6,"output_tokens":4}]}],"has_more":false}');
    CompletionQuery := AQuery;
    Result := '{"data":[{"start_time":' + FirstStart +
      ',"results":[{"model":"older-model","num_model_requests":2000,' +
      '"input_tokens":900000,"output_tokens":100000}]},{"start_time":' + WeekStart +
      ',"results":[{"model":"test-model","num_model_requests":3,' +
      '"input_tokens":90,"output_tokens":10}]}';
    case UsageFixture of
      ufReported: TodayResults := '[{"model":"test-model","num_model_requests":20,' +
        '"input_tokens":123,"output_tokens":45},{"model":"other-model",' +
        '"num_model_requests":30,"input_tokens":90,"output_tokens":10}]';
      ufZero: TodayResults := '[{"num_model_requests":0,"input_tokens":0,"output_tokens":0}]';
      ufNull: TodayResults := '[{"num_model_requests":null,"input_tokens":null,"output_tokens":null}]';
      ufMissingTokens: TodayResults := '[{"num_model_requests":0,"input_tokens":0}]';
      ufEmpty: TodayResults := '[]';
      ufNegative: TodayResults := '[{"num_model_requests":-1,"input_tokens":-1,"output_tokens":0}]';
      ufOverflow: TodayResults := '[{"num_model_requests":null,"input_tokens":9223372036854775807,"output_tokens":1}]';
      ufLarge: TodayResults := '[{"num_model_requests":9007199254740993,"input_tokens":9007199254740993,"output_tokens":7}]';
    end;
    if UsageFixture <> ufMissing then
      Result := Result + ',{"start_time":' + TodayStart + ',"results":' + TodayResults + '}';
    if UsageFixture = ufReported then
      Result := Result + '],"has_more":true,"next_page":"second"}'
    else
      Result := Result + '],"has_more":false}';
  end
  else
  begin
    if APath = '/organization/usage/images' then
      ServiceQuery := AQuery;
    Result := '{"data":[],"has_more":false}';
  end;
end;

procedure RunJsonShapeTests;
var
  Client: TFixtureClient;
  Snapshot: TUsageSnapshot;
  ErrorText, TodayStart, YesterdayStart, ResultsJson, ResponseJson: string;
  CostItem, UsageItem, YesterdayCost, YesterdayUsage: string;
  ChartDays: TArray<TDailyChartDay>;
  I: Integer;
  FoundVectorStores: Boolean;

  function BucketJson(const AStart, AResults: string): string;
  begin
    Result := '{"start_time":' + AStart;
    if AResults <> '' then
      Result := Result + ',"results":' + AResults;
    Result := Result + '}';
  end;

  function PageJson(const ABuckets: string): string;
  begin
    Result := '{"data":[' + ABuckets + '],"has_more":false}';
  end;

  procedure FetchSuccessfully(const ACase: string);
  begin
    if not Client.Fetch(Snapshot, ErrorText) then
      Check(False, ACase + ': ' + ErrorText);
    Check(ErrorText = '', ACase + ': successful fetch retained an error.');
    ChartDays := Snapshot.GetDailyChartDays;
    Check(Length(ChartDays) = 14, ACase + ': expected fourteen chart days.');
  end;

  procedure CheckNoTodayCost(const ACase: string);
  begin
    Check(not Snapshot.CostTodayAvailable and not ChartDays[13].HasCostData,
      ACase + ': absent cost data must not become a reported zero.');
    Check(SameValue(Snapshot.CostToday, 0, 0.000001),
      ACase + ': absent cost data must not contribute to the total.');
  end;

  procedure CheckNoTodayUsage(const ACase: string);
  begin
    Check(not ChartDays[13].HasRequestData and not ChartDays[13].HasTokenData,
      ACase + ': absent usage must not become reported requests or tokens.');
    Check((Snapshot.RequestsToday = 0) and (Snapshot.TokensToday = 0),
      ACase + ': absent usage must not contribute to the totals.');
  end;

  procedure CheckInvalidShape(const ACase, AJson, AFieldPath: string;
    const AForCosts: Boolean);
  begin
    Client.CostResponse := '';
    Client.CompletionResponse := '';
    if AForCosts then
      Client.CostResponse := AJson
    else
      Client.CompletionResponse := AJson;
    Check(not Client.Fetch(Snapshot, ErrorText),
      ACase + ': a wrong JSON type must fail the fetch.');
    Check(Pos(AFieldPath, LowerCase(ErrorText)) > 0,
      ACase + ': error must identify JSON field ' + AFieldPath + ': ' + ErrorText);
    Check((Pos('type cast', LowerCase(ErrorText)) = 0) and
      (Pos('typumwandlung', LowerCase(ErrorText)) = 0) and
      (Pos('einvalidcast', LowerCase(ErrorText)) = 0),
      ACase + ': error must explain the JSON shape instead of exposing a cast exception.');
  end;

begin
  Client := TFixtureClient.Create('offline-fixture', 0, 1);
  Snapshot := TUsageSnapshot.Create;
  try
    Client.UtcNow := EncodeDateTime(2026, 8, 31, 23, 30, 0, 0);
    TodayStart := IntToStr(DateTimeToUnix(DateOf(Client.UtcNow), True));
    YesterdayStart := IntToStr(DateTimeToUnix(DateOf(Client.UtcNow) - 1, True));
    CostItem := '{"amount":{"value":1.25,"currency":"usd"}}';
    UsageItem := '{"model":"shape-model","num_model_requests":3,' +
      '"input_tokens":5,"output_tokens":7}';
    YesterdayCost := BucketJson(YesterdayStart, '[' + CostItem + ']');
    YesterdayUsage := BucketJson(YesterdayStart, '[' + UsageItem + ']');

    for I := 0 to 1 do
    begin
      if I = 0 then
        ResponseJson := '{"has_more":false}'
      else
        ResponseJson := '{"data":null,"has_more":false}';
      Client.CostResponse := ResponseJson;
      Client.CompletionResponse := '';
      FetchSuccessfully('Missing/null costs data');
      CheckNoTodayCost('Missing/null costs data');
      Check(SameValue(Snapshot.Cost30Days, 0, 0.000001),
        'Missing/null costs data must leave the cost aggregate empty.');
      Check((Snapshot.RequestsToday = 54) and (Snapshot.TokensToday = 278),
        'Missing/null costs data must preserve the independent completion response.');

      Client.CostResponse := '';
      Client.CompletionResponse := ResponseJson;
      FetchSuccessfully('Missing/null completions data');
      CheckNoTodayUsage('Missing/null completions data');
      Check((Snapshot.Requests7Days = 0) and (Snapshot.Tokens7Days = 0),
        'Missing/null completions data must leave usage aggregates empty.');
      Check(Snapshot.CostTodayAvailable and SameValue(Snapshot.CostToday, 0.97, 0.000001),
        'Missing/null completions data must preserve the independent cost response.');

      if I = 0 then
        ResultsJson := ''
      else
        ResultsJson := 'null';
      Client.CostResponse := PageJson(YesterdayCost + ',' + BucketJson(TodayStart, ResultsJson));
      Client.CompletionResponse := PageJson(YesterdayUsage + ',' + BucketJson(TodayStart, ResultsJson));
      FetchSuccessfully('Missing/null results');
      CheckNoTodayCost('Missing/null cost results');
      CheckNoTodayUsage('Missing/null completion results');
      Check(ChartDays[12].HasCostData and SameValue(ChartDays[12].Amount, 1.25, 0.000001),
        'Missing/null results must preserve a valid neighboring cost bucket.');
      Check(ChartDays[12].HasRequestData and ChartDays[12].HasTokenData and
        (Snapshot.Requests7Days = 3) and (Snapshot.Tokens7Days = 12),
        'Missing/null results must preserve a valid neighboring usage bucket.');

      if I = 0 then
        ResultsJson := '[{}]'
      else
        ResultsJson := '[{"amount":null}]';
      Client.CostResponse := PageJson(YesterdayCost + ',' + BucketJson(TodayStart, ResultsJson));
      FetchSuccessfully('Missing/null amount');
      CheckNoTodayCost('Missing/null amount');
      Check(SameValue(Snapshot.Cost30Days, 1.25, 0.000001),
        'Missing/null amount must retain the neighboring reported cost.');
    end;

    Client.CostResponse := PageJson('null,' + BucketJson(TodayStart,
      '[null,{"amount":null},' + CostItem + ',null]') + ',null');
    Client.CompletionResponse := PageJson('null,' + BucketJson(TodayStart,
      '[null,' + UsageItem + ',null]') + ',null');
    FetchSuccessfully('Null entries surrounding valid buckets and results');
    Check(Snapshot.CostTodayAvailable and ChartDays[13].HasCostData and
      SameValue(Snapshot.CostToday, 1.25, 0.000001),
      'Null entries must not discard or duplicate their neighboring cost result.');
    Check(ChartDays[13].HasRequestData and ChartDays[13].HasTokenData and
      (Snapshot.RequestsToday = 3) and (Snapshot.TokensToday = 12) and
      (Length(Snapshot.Models) = 1) and (Snapshot.Models[0].Model = 'shape-model'),
      'Null entries must not discard, duplicate or manufacture usage/model results.');

    Client.CostResponse := PageJson('null,' + BucketJson(TodayStart, '[null]') + ',null');
    Client.CompletionResponse := Client.CostResponse;
    FetchSuccessfully('Only null bucket and result entries');
    CheckNoTodayCost('Only null result entries');
    CheckNoTodayUsage('Only null result entries');

    for I := 0 to 1 do
    begin
      CheckInvalidShape('Object instead of data array', '{"data":{}}', 'data', I = 0);
      CheckInvalidShape('Number instead of data bucket', '{"data":[42]}', 'data', I = 0);
      CheckInvalidShape('Object instead of results array',
        PageJson(BucketJson(TodayStart, '{}')), 'results', I = 0);
      CheckInvalidShape('Number instead of result object',
        PageJson(BucketJson(TodayStart, '[42]')), 'results', I = 0);
    end;
    CheckInvalidShape('Number instead of amount object',
      PageJson(BucketJson(TodayStart, '[{"amount":7}]')), 'amount', True);

    Client.CostResponse := '';
    Client.CompletionResponse := '';
    Client.SpendingLimitResponse := '{"limit":42,"data":null}';
    FetchSuccessfully('Direct spending limit with null data');
    Check(SameValue(Snapshot.SpendingLimit, 42, 0.000001),
      'A null optional spending-limit data object must not erase a direct limit.');

    Client.VectorStoresResponse := PageJson(
      BucketJson(YesterdayStart, '[{"usage_bytes":456}]') + ',' +
      BucketJson(TodayStart, '[null,{"usage_bytes":123},null]') + ',null');
    FetchSuccessfully('Latest vector-store bucket followed by null');
    FoundVectorStores := False;
    for I := 0 to High(Snapshot.Services) do
      if Snapshot.Services[I].Name = 'Vector Stores' then
      begin
        FoundVectorStores := True;
        Check(Snapshot.Services[I].Available and
          SameValue(Snapshot.Services[I].Value, 123, 0.000001),
          'A trailing null bucket must preserve the latest vector-store value without summing older buckets.');
      end;
    Check(FoundVectorStores, 'The vector-store service must remain in the snapshot.');
    Check(Snapshot.CostTodayAvailable and SameValue(Snapshot.CostToday, 0.97, 0.000001) and
      (Snapshot.RequestsToday = 54) and (Snapshot.TokensToday = 278),
      'Null vector-store entries must preserve the independent cost and completion totals.');
    Writeln('OPENAI_JSON_SHAPES_OK');
  finally
    Snapshot.Free;
    Client.Free;
  end;
end;

procedure RunTests;
var
  Client: TFixtureClient;
  Snapshot, RoundTrip: TUsageSnapshot;
  ErrorText: string;
  Fixture: TCostFixture;
  UsageFixture: TUsageFixture;
  ChartDays: TArray<TDailyChartDay>;
  Rate: Double;
begin
  Client := TFixtureClient.Create('offline-fixture', 30, 1);
  Snapshot := TUsageSnapshot.Create;
  RoundTrip := TUsageSnapshot.Create;
  try
    { In Berlin this is already September 1. API day and billing period must
      still be August 31 and August respectively. No network is used. }
    Client.UtcNow := EncodeDateTime(2026, 8, 31, 23, 30, 0, 0);
    for Fixture := Low(TCostFixture) to High(TCostFixture) do
    begin
      Client.CostFixture := Fixture;
      Check(Client.Fetch(Snapshot, ErrorText), 'Fetch fixture: ' + ErrorText);
      Check(SameDate(Snapshot.PeriodStart, EncodeDate(2026, 8, 1)),
        'Billing date was shifted into the local month.');
      Check(Pos('start_time=' + IntToStr(DateTimeToUnix(EncodeDate(2026, 8, 1), True)),
        Client.CostQuery) = 1, 'Cost query start must be UTC midnight.');
      Check(Pos('start_time=' + IntToStr(DateTimeToUnix(EncodeDate(2026, 8, 18), True)),
        Client.CompletionQuery) = 1, 'Usage query must cover fourteen UTC days.');
      Check(Pos('&bucket_width=1d&limit=14&group_by=model', Client.CompletionQuery) > 0,
        'Completions must request fourteen daily buckets grouped by model.');
      Check(Pos('start_time=' + IntToStr(DateTimeToUnix(EncodeDate(2026, 8, 25), True)),
        Client.ServiceQuery) = 1, 'Service query must retain seven UTC days.');
      Check(Pos('&bucket_width=1d&limit=7', Client.ServiceQuery) > 0,
        'Service bucket limit must remain seven.');
      Check(Pos('&end_time=' + IntToStr(DateTimeToUnix(Client.UtcNow, True)),
        Client.CostQuery) > 0, 'Query end must be the captured UTC instant.');
      Check(Snapshot.CostTodayAvailable = (Fixture in [cfReported, cfZero]),
        'Missing/empty/null cost data must differ from a reported zero.');
      Check((Snapshot.RequestsToday = 54) and (Snapshot.TokensToday = 278),
        'Today must aggregate all models and paginated buckets on its UTC day.');
      Check((Snapshot.Requests7Days = 57) and (Snapshot.Tokens7Days = 378),
        'Seven-day totals must exclude older chart-only usage.');
      Check((Length(Snapshot.Models) = 2) and (Snapshot.Models[0].Model = 'test-model') and
        (Snapshot.Models[0].Tokens = 278), 'Model ranking must retain its seven-day scope.');
      Check(Length(Snapshot.DailyModelUsage) = 3,
        'Repeated calendar days must merge into one daily usage record.');
      ChartDays := Snapshot.GetDailyChartDays;
      Check((Length(ChartDays) = 14) and SameDate(ChartDays[0].Day, EncodeDate(2026, 8, 18)) and
        SameDate(ChartDays[13].Day, EncodeDate(2026, 8, 31)),
        'Chart must span fourteen calendar days through the current UTC day.');
      Check((ChartDays[0].Requests = 2000) and ChartDays[0].HasRequestData,
        'The first chart week must retain its model requests.');
      Check((ChartDays[13].Requests = 54) and ChartDays[13].HasRequestData and
        (ChartDays[13].HasCostData = (Fixture in [cfReported, cfZero])),
        'Today requests must remain visible when the cost bucket is absent.');
      if Fixture = cfReported then
      begin
        Check(SameValue(Snapshot.CostToday, 0.97, 0.000001), 'Today cost mismatch.');
        Rate := Snapshot.ForecastDailyRate;
        Snapshot.DailyCosts[High(Snapshot.DailyCosts)].Amount := 9999;
        Snapshot.Recalculate(Client.UtcNow);
        Check(SameValue(Rate, Snapshot.ForecastDailyRate, 0.000001),
          'Today must not influence the forecast slope.');
      end;
      RoundTrip.FromJson(Snapshot.ToJson);
      Check(SameDate(RoundTrip.DailyCosts[0].Day, EncodeDate(2026, 8, 30)),
        'Calendar dates must survive snapshot transfer unchanged.');
      Check(RoundTrip.CostTodayAvailable = Snapshot.CostTodayAvailable,
        'Cost availability was lost during transfer.');
      Check((Length(RoundTrip.DailyModelUsage) = 3) and
        (RoundTrip.DailyModelUsage[2].Requests = 54) and
        RoundTrip.DailyModelUsage[2].HasRequestData and
        RoundTrip.DailyModelUsage[2].HasTokenData,
        'Daily usage and its availability must survive snapshot transfer.');
      RoundTrip.Recalculate;
      Check(SameValue(RoundTrip.CostToday, Snapshot.CostToday, 0.000001),
        'Viewer recalculation must use the collector snapshot day.');
    end;
    Client.CostFixture := cfMissing;
    for UsageFixture := ufZero to ufOverflow do
    begin
      Client.UsageFixture := UsageFixture;
      Check(Client.Fetch(Snapshot, ErrorText), 'Usage availability fixture: ' + ErrorText);
      ChartDays := Snapshot.GetDailyChartDays;
      Check(ChartDays[13].HasRequestData = (UsageFixture in [ufZero, ufMissingTokens]),
        'Zero request counts must differ from missing, null or empty results.');
      Check(ChartDays[13].HasTokenData = (UsageFixture = ufZero),
        'Token totals require both input and output fields, including explicit zero.');
      Check(not ChartDays[13].HasCostData,
        'Usage data must not manufacture a reported zero cost.');
    end;
    Client.UsageFixture := ufLarge;
    Check(Client.Fetch(Snapshot, ErrorText), ErrorText);
    Check((Snapshot.RequestsToday = 9007199254740993) and
      (Snapshot.TokensToday = 9007199254741000), 'Daily usage must retain exact Int64 counts.');
    RoundTrip.FromJson(Snapshot.ToJson);
    ChartDays := RoundTrip.GetDailyChartDays;
    Check((ChartDays[13].Requests = 9007199254740993) and
      (ChartDays[13].Tokens = 9007199254741000), 'Snapshot JSON must preserve large counts exactly.');
    Client.UtcNow := EncodeDateTime(2026, 9, 1, 0, 1, 0, 0);
    Check(Client.Fetch(Snapshot, ErrorText), ErrorText);
    Check(SameDate(Snapshot.PeriodStart, EncodeDate(2026, 9, 1)),
      'Billing period must reset at the UTC month boundary.');
    Writeln('OPENAI_FIXTURES_OK');
  finally
    RoundTrip.Free;
    Snapshot.Free;
    Client.Free;
  end;
end;

begin
  try
    RunTests;
    RunJsonShapeTests;
  except
    on E: Exception do
    begin
      Writeln('OPENAI_FIXTURES_FAILED: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
