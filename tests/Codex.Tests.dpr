program CodexTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.DateUtils,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.Codex in '..\Dashboard.Codex.pas';

type
  TTestClient = class(TCodexClient)
  public
    procedure Usage(ASnapshot: TUsageSnapshot; const AJson: string);
    procedure Limits(ASnapshot: TUsageSnapshot; const AJson: string);
  end;

procedure TTestClient.Usage(ASnapshot: TUsageSnapshot; const AJson: string);
begin
  ApplyUsage(ASnapshot, AJson);
end;

procedure TTestClient.Limits(ASnapshot: TUsageSnapshot; const AJson: string);
begin
  ApplyRateLimits(ASnapshot, AJson);
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure RunTests;
var
  Client: TTestClient;
  Snapshot: TUsageSnapshot;
  Rejected: Boolean;
  TodayText, YesterdayText, OldText: string;
begin
  Client := TTestClient.Create;
  Snapshot := TUsageSnapshot.Create;
  try
    TodayText := FormatDateTime('yyyy-mm-dd', Date);
    YesterdayText := FormatDateTime('yyyy-mm-dd', IncDay(Date, -1));
    OldText := FormatDateTime('yyyy-mm-dd', IncDay(Date, -8));
    Client.Usage(Snapshot, '{"summary":{"lifetimeTokens":40000000000},' +
      '"dailyUsageBuckets":[{"startDate":"' + TodayText + '","tokens":25},' +
      '{"startDate":"' + YesterdayText + '","tokens":100},' +
      '{"startDate":"' + OldText + '","tokens":1000}]}');
    Check(Snapshot.CodexLifetimeAvailable and Snapshot.CodexDailyUsageAvailable and Snapshot.CodexTodayUsageAvailable,
      'Complete usage response was marked unavailable');
    Check(Snapshot.CodexLifetimeTokens = 40000000000, 'Lifetime Int64 changed');
    Check(Snapshot.CodexTodayTokens = 25, 'Today aggregation is wrong');
    Check(Snapshot.CodexSevenDayTokens = 125, 'Seven-day boundary is wrong');

    Client.Usage(Snapshot,
      '{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":[]}');
    Check(Snapshot.CodexUsageAvailable and
      not Snapshot.CodexLifetimeAvailable and Snapshot.CodexDailyUsageAvailable,
      'Missing lifetime must not hide an available empty daily series');
    Check(not Snapshot.CodexTodayUsageAvailable,
      'An empty daily series must not invent a reported zero for today');

    Client.Usage(Snapshot,
      '{"summary":{"lifetimeTokens":0},"dailyUsageBuckets":null}');
    Check(Snapshot.CodexLifetimeAvailable and
      not Snapshot.CodexDailyUsageAvailable and not Snapshot.CodexTodayUsageAvailable and Snapshot.CodexUsageAvailable,
      'Zero lifetime is available; null daily data is unavailable');

    Rejected := False;
    try
      Client.Usage(Snapshot,
        '{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}');
    except
      on E: EConvertError do
        Rejected := True;
    end;
    Check(Rejected and not Snapshot.CodexUsageAvailable and
      not Snapshot.CodexLifetimeAvailable and not Snapshot.CodexDailyUsageAvailable,
      'Unavailable token data was silently accepted as zero');

    Rejected := False;
    try
      Client.Usage(Snapshot,
        '{"summary":{"lifetimeTokens":1},"dailyUsageBuckets":[' +
        '{"startDate":"' + TodayText + '","tokens":null}]}');
    except
      on E: EConvertError do
        Rejected := True;
    end;
    Check(Rejected and not Snapshot.CodexDailyUsageAvailable,
      'Invalid daily bucket was accepted as zero');

    Client.Limits(Snapshot, '{"rateLimitsByLimitId":{},"rateLimits":{' +
      '"limitId":"codex","primary":{"usedPercent":66,' +
      '"windowDurationMins":10080,"resetsAt":2000000000}}}');
    Check(Snapshot.CodexRateLimitsAvailable and (Length(Snapshot.RateLimits) = 1),
      'Empty multi-bucket map must fall back to the legacy limit');
    Check(Snapshot.RateLimits[0].UsedPercent = 66, 'Used percent changed');

    Client.Limits(Snapshot, '{"rateLimitsByLimitId":{' +
      '"spark":{"limitId":"spark","primary":{"usedPercent":0}},' +
      '"codex":{"limitId":"codex","primary":{"usedPercent":25},' +
      '"secondary":{"usedPercent":null}}}}');
    Check(Snapshot.CodexRateLimitsAvailable and (Length(Snapshot.RateLimits) = 2),
      'Null secondary limit should not create a false 0 percent window');
    Check(Snapshot.RateLimits[0].Id = 'codex:codex:primary',
      'Codex limit should be before Spark');

    Rejected := False;
    try
      Client.Limits(Snapshot,
        '{"rateLimits":{"primary":{"usedPercent":null}}}');
    except
      on E: EConvertError do
        Rejected := True;
    end;
    Check(Rejected and not Snapshot.CodexRateLimitsAvailable and
      (Length(Snapshot.RateLimits) = 0),
      'Null limit must not preserve stale windows or create false zero');
  finally
    Snapshot.Free;
    Client.Free;
  end;
end;

begin
  try
    RunTests;
    Writeln('CODEX_PARSER_TESTS_OK');
  except
    on E: Exception do
    begin
      Writeln('CODEX_PARSER_TESTS_FAILED ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
