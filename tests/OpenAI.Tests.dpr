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
  except
    on E: Exception do
    begin
      Writeln('OPENAI_FIXTURES_FAILED: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
