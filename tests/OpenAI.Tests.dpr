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

  TFixtureClient = class(TOpenAIUsageClient)
  public
    UtcNow: TDateTime;
    CostFixture: TCostFixture;
    CostQuery, CompletionQuery: string;
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
  TodayStart, YesterdayStart: string;
  TodayResults: string;
begin
  TodayStart := IntToStr(DateTimeToUnix(DateOf(UtcNow), True));
  YesterdayStart := IntToStr(DateTimeToUnix(DateOf(UtcNow) - 1, True));
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
    CompletionQuery := AQuery;
    Result := '{"data":[{"start_time":' + TodayStart +
      ',"results":[{"model":"test-model","num_model_requests":7,' +
      '"input_tokens":123,"output_tokens":45}]}],"has_more":false}';
  end
  else
    Result := '{"data":[],"has_more":false}';
end;

procedure RunTests;
var
  Client: TFixtureClient;
  Snapshot, RoundTrip: TUsageSnapshot;
  ErrorText: string;
  Fixture: TCostFixture;
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
      Check(Pos('start_time=' + IntToStr(DateTimeToUnix(EncodeDate(2026, 8, 25), True)),
        Client.CompletionQuery) = 1, 'Usage query start must be UTC midnight.');
      Check(Pos('&end_time=' + IntToStr(DateTimeToUnix(Client.UtcNow, True)),
        Client.CostQuery) > 0, 'Query end must be the captured UTC instant.');
      Check(Snapshot.CostTodayAvailable = (Fixture in [cfReported, cfZero]),
        'Missing/empty/null cost data must differ from a reported zero.');
      Check((Snapshot.RequestsToday = 7) and (Snapshot.TokensToday = 168),
        'Today completion totals were shifted to another day.');
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
      RoundTrip.Recalculate;
      Check(SameValue(RoundTrip.CostToday, Snapshot.CostToday, 0.000001),
        'Viewer recalculation must use the collector snapshot day.');
    end;
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
