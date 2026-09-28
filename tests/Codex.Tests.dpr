program CodexTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.DateUtils,
  System.IOUtils,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.Codex in '..\Dashboard.Codex.pas';

type
  TTestClient = class(TCodexClient)
  public
    procedure Usage(ASnapshot: TUsageSnapshot; const AJson: string);
    procedure Limits(ASnapshot: TUsageSnapshot; const AJson: string);
    function ChildEnvironment(const AEntries: TArray<string>;
      const AProfile: string): string;
    function DashboardHome(const ALocalAppData: string): string;
  end;

procedure TTestClient.Usage(ASnapshot: TUsageSnapshot; const AJson: string);
begin
  ApplyUsage(ASnapshot, AJson);
end;

procedure TTestClient.Limits(ASnapshot: TUsageSnapshot; const AJson: string);
begin
  ApplyRateLimits(ASnapshot, AJson);
end;

function TTestClient.ChildEnvironment(const AEntries: TArray<string>;
  const AProfile: string): string;
begin
  Result := BuildChildEnvironment(AEntries, AProfile);
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function TTestClient.DashboardHome(const ALocalAppData: string): string;
begin
  Result := ResolveDashboardHome(ALocalAppData);
end;

procedure TestDashboardHome;
var
  Client: TTestClient;
  TestRoot, NormalProfile, CachedProfile: string;
begin
  TestRoot := TPath.Combine(TPath.GetTempPath,
    'Dashboard-Profile-' + TGUID.NewGuid.ToString);
  NormalProfile := TPath.Combine(TestRoot, 'OpenAIUsageDashboard\Codex');
  CachedProfile := TPath.Combine(TestRoot,
    'Packages\OpenAI.Codex_test\LocalCache\Local\OpenAIUsageDashboard\Codex');
  Client := TTestClient.Create;
  try
    Check(Client.DashboardHome('') = '', 'Missing LocalAppData must stay empty.');
    Check(Client.DashboardHome(TestRoot) = NormalProfile,
      'New logins must use the regular dashboard profile.');
    ForceDirectories(CachedProfile);
    Check(Client.DashboardHome(TestRoot) = NormalProfile,
      'An unfinished package login must not select the package profile.');
    TFile.WriteAllText(TPath.Combine(CachedProfile, 'auth.json'), '{}');
    Check(Client.DashboardHome(TestRoot) = CachedProfile,
      'Explorer startup must discover the dashboard login in the MSIX cache.');
    ForceDirectories(NormalProfile);
    TFile.WriteAllText(TPath.Combine(NormalProfile, 'auth.json'), '{}');
    Check(Client.DashboardHome(TestRoot) = NormalProfile,
      'An existing normal dashboard login must take precedence.');
  finally
    if TDirectory.Exists(TestRoot) then
      TDirectory.Delete(TestRoot, True);
    Client.Free;
  end;
end;

procedure TestChildEnvironment;
var
  Client: TTestClient;
  ProfilePath, AuthPath, EnvironmentBlock: string;
  ParentEntries: TArray<string>;

  function ContainsEntry(const AEntry: string): Boolean;
  begin
    Result := Pos(#0 + AEntry + #0, #0 + EnvironmentBlock) > 0;
  end;

begin
  ProfilePath := TPath.Combine(TPath.GetTempPath,
    'Dashboard-Codex-' + TGUID.NewGuid.ToString);
  AuthPath := TPath.Combine(ProfilePath, 'auth.json');
  Client := TTestClient.Create;
  try
    ParentEntries := TArray<string>.Create('USERPROFILE=C:\TestUser', 'PATH=C:\Tools',
      'OTHER_SETTING=preserved');
    EnvironmentBlock := Client.ChildEnvironment(ParentEntries, ProfilePath);
    Check(ContainsEntry('HOME=C:\TestUser') and
      ContainsEntry('CODEX_HOME=C:\TestUser\.codex'),
      'Without a dashboard login the existing home fallback must remain.');
    Check(ContainsEntry('PATH=C:\Tools') and ContainsEntry('OTHER_SETTING=preserved'),
      'Unrelated child environment entries must remain.');

    ForceDirectories(ProfilePath);
    ParentEntries := TArray<string>.Create('USERPROFILE=C:\TestUser',
      'HOME=C:\ExistingHome', 'codex_home=C:\ExistingCodex', 'PATH=C:\Tools');
    EnvironmentBlock := Client.ChildEnvironment(ParentEntries, ProfilePath);
    Check(ContainsEntry('codex_home=C:\ExistingCodex') and
      ContainsEntry('HOME=C:\ExistingHome'),
      'An unfinished dashboard login must preserve the inherited profile.');

    TFile.WriteAllText(AuthPath, '{}', TEncoding.UTF8);
    EnvironmentBlock := Client.ChildEnvironment(ParentEntries, ProfilePath);
    Check(ContainsEntry('CODEX_HOME=' + ProfilePath) and
      not ContainsEntry('codex_home=C:\ExistingCodex'),
      'The dashboard login must replace the inherited Codex profile in the child.');
    Check(ContainsEntry('HOME=C:\ExistingHome') and ContainsEntry('PATH=C:\Tools'),
      'Selecting the dashboard login must preserve the remaining environment.');
    Check(ParentEntries[2] = 'codex_home=C:\ExistingCodex',
      'The parent environment must not be modified.');
    Check(Copy(EnvironmentBlock, Length(EnvironmentBlock) - 1, 2) = #0#0,
      'CreateProcess requires a double-null-terminated environment block.');

    TFile.Delete(AuthPath);
    EnvironmentBlock := Client.ChildEnvironment(ParentEntries, ProfilePath);
    Check(ContainsEntry('codex_home=C:\ExistingCodex'),
      'Removing a dashboard login must restore the inherited profile.');
  finally
    if TFile.Exists(AuthPath) then
      TFile.Delete(AuthPath);
    if TDirectory.Exists(ProfilePath) then
      TDirectory.Delete(ProfilePath, False);
    Client.Free;
  end;
end;

procedure CheckWindowNames(const AClient: TTestClient; const ASnapshot: TUsageSnapshot;
  const APrimaryMinutes, ASecondaryMinutes: Integer;
  const APrimaryName, ASecondaryName: string);
begin
  AClient.Limits(ASnapshot, '{"rateLimits":{"limitId":"codex",' +
    '"primary":{"usedPercent":25,"windowDurationMins":' + IntToStr(APrimaryMinutes) +
    ',"resetsAt":2000000000},"secondary":{"usedPercent":66,"windowDurationMins":' +
    IntToStr(ASecondaryMinutes) + ',"resetsAt":2000000300}}}');
  Check(Length(ASnapshot.RateLimits) = 2, 'Both available windows must remain');
  Check((ASnapshot.RateLimits[0].Id = 'codex:codex:primary') and
    (ASnapshot.RateLimits[1].Id = 'codex:codex:secondary'),
    'Duration labels must not change window order or identity');
  Check((ASnapshot.RateLimits[0].WindowName = APrimaryName) and
    (ASnapshot.RateLimits[1].WindowName = ASecondaryName),
    'Window labels must describe the reported durations');
  Check((ASnapshot.RateLimits[0].WindowMinutes = APrimaryMinutes) and
    (ASnapshot.RateLimits[1].WindowMinutes = ASecondaryMinutes),
    'Original window durations must be preserved');
  Check((ASnapshot.RateLimits[0].UsedPercent = 25) and
    (ASnapshot.RateLimits[1].UsedPercent = 66), 'Duration labels changed percentages');
  Check((DateTimeToUnix(ASnapshot.RateLimits[0].ResetsAt, False) = 2000000000) and
    (DateTimeToUnix(ASnapshot.RateLimits[1].ResetsAt, False) = 2000000300),
    'Duration labels changed reset times');
end;

procedure RunTests;
var
  Client: TTestClient;
  Snapshot, RoundTrip: TUsageSnapshot;
  Rejected: Boolean;
  TodayText, YesterdayText, OldText: string;
begin
  Client := TTestClient.Create;
  Snapshot := TUsageSnapshot.Create;
  RoundTrip := TUsageSnapshot.Create;
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

    CheckWindowNames(Client, Snapshot, 10080, 300, '7 Tage', '5 Stunden');
    CheckWindowNames(Client, Snapshot, 300, 10080, '5 Stunden', '7 Tage');
    RoundTrip.FromJson(Snapshot.ToJson);
    Check((Length(RoundTrip.RateLimits) = 2) and
      (RoundTrip.RateLimits[0].WindowName = '5 Stunden') and
      (RoundTrip.RateLimits[1].WindowName = '7 Tage') and
      (RoundTrip.RateLimits[0].WindowMinutes = 300) and
      (RoundTrip.RateLimits[1].WindowMinutes = 10080),
      'Duration labels and minutes must survive viewer snapshot transfer');
    CheckWindowNames(Client, Snapshot, 1440, 60, '1 Tag', '1 Stunde');
    CheckWindowNames(Client, Snapshot, 1, 90, '1 Minute', '90 Minuten');
    CheckWindowNames(Client, Snapshot, 0, -1, 'Primär', 'Sekundär');
    Client.Limits(Snapshot, '{"rateLimits":{"limitId":"codex",' +
      '"primary":{"usedPercent":25},"secondary":{"usedPercent":66,"windowDurationMins":null}}}');
    Check((Snapshot.RateLimits[0].WindowName = 'Primär') and
      (Snapshot.RateLimits[1].WindowName = 'Sekundär'),
      'Missing or null durations must retain neutral role labels');

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
    RoundTrip.Free;
    Snapshot.Free;
    Client.Free;
  end;
end;

begin
  try
    TestDashboardHome;
    TestChildEnvironment;
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
