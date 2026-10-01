program InstanceTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,
  Dashboard.Instance in '..\Dashboard.Instance.pas';

const
  TimeoutMs = 10000;
  ConcurrentStarts = 6;
  PrimaryContenderExit = 20;

type
  TChildProcess = record
    Process: THandle;
    Ready: THandle;
    Primary: THandle;
  end;

  { Every guard uses a unique GUID namespace. Tests neither acquire the real
    dashboard's mutex nor start its form, tray, API or display-power code. }
  TChildGroup = class
  private
    FControlPrefix: string;
    FMode: string;
    FStart: THandle;
    FRelease: THandle;
    FChildren: TArray<TChildProcess>;
  public
    constructor Create(const AInstancePrefix, AMode: string; ACount: Integer);
    destructor Destroy; override;
    procedure Start;
    procedure WaitReady;
    procedure Release;
    procedure VerifyExits;
    function PrimaryCount: Integer;
  end;

function ConvertSidToStringSidForTest(ASid: PSID; var AText: PChar): BOOL;
  stdcall; external 'advapi32.dll' name 'ConvertSidToStringSidW';

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function NewPrefix: string;
var
  Id: TGUID;
begin
  CreateGUID(Id);
  Result := 'OpenAIUsageDashboard.Instance.Tests.' + GUIDToString(Id);
end;

function ControlName(const APrefix, AKind: string; AIndex: Integer = -1): string;
begin
  Result := 'Local\' + APrefix + '.' + AKind;
  if AIndex >= 0 then
    Result := Result + '.' + IntToStr(AIndex);
end;

function MakeControlEvent(const AName: string): THandle;
begin
  Result := CreateEvent(nil, True, False, PChar(AName));
  Check(Result <> 0, 'CreateEvent failed for ' + AName);
end;

function OpenControlEvent(const AName: string): THandle;
begin
  Result := OpenEvent(SYNCHRONIZE or EVENT_MODIFY_STATE, False, PChar(AName));
  Check(Result <> 0, 'OpenEvent failed for ' + AName);
end;

procedure WaitForControl(AHandle: THandle; const ADescription: string);
begin
  Check(WaitForSingleObject(AHandle, TimeoutMs) = WAIT_OBJECT_0,
    'Timed out waiting for ' + ADescription);
end;

constructor TChildGroup.Create(const AInstancePrefix, AMode: string;
  ACount: Integer);
var
  Index: Integer;
  Command: string;
  Startup: TStartupInfo;
  ChildInfo: TProcessInformation;
begin
  inherited Create;
  Check((ACount > 0) and (ACount <= MAXIMUM_WAIT_OBJECTS), 'Invalid child count');
  FControlPrefix := NewPrefix;
  FMode := AMode;
  FStart := MakeControlEvent(ControlName(FControlPrefix, 'Start'));
  FRelease := MakeControlEvent(ControlName(FControlPrefix, 'Release'));
  SetLength(FChildren, ACount);
  for Index := 0 to High(FChildren) do
  begin
    FChildren[Index].Ready := MakeControlEvent(
      ControlName(FControlPrefix, 'Ready', Index));
    FChildren[Index].Primary := MakeControlEvent(
      ControlName(FControlPrefix, 'Primary', Index));
    FillChar(Startup, SizeOf(Startup), 0);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    FillChar(ChildInfo, SizeOf(ChildInfo), 0);
    Command := '"' + ParamStr(0) + '" --child "' + AInstancePrefix + '" "' +
      FControlPrefix + '" "' + AMode + '" ' + IntToStr(Index);
    UniqueString(Command);
    Check(CreateProcess(nil, PChar(Command), nil, nil, False, CREATE_NO_WINDOW,
      nil, nil, Startup, ChildInfo), 'Could not start child process');
    FChildren[Index].Process := ChildInfo.hProcess;
    CloseHandle(ChildInfo.hThread);
  end;
end;

destructor TChildGroup.Destroy;
var
  Child: TChildProcess;
begin
  if FRelease <> 0 then
    SetEvent(FRelease);
  for Child in FChildren do
  begin
    if Child.Process <> 0 then
    begin
      if WaitForSingleObject(Child.Process, 1000) = WAIT_TIMEOUT then
      begin
        // Termination is confined to a process created by this test fixture.
        TerminateProcess(Child.Process, 99);
        WaitForSingleObject(Child.Process, 1000);
      end;
      CloseHandle(Child.Process);
    end;
    if Child.Primary <> 0 then
      CloseHandle(Child.Primary);
    if Child.Ready <> 0 then
      CloseHandle(Child.Ready);
  end;
  if FRelease <> 0 then
    CloseHandle(FRelease);
  if FStart <> 0 then
    CloseHandle(FStart);
  inherited;
end;

procedure TChildGroup.Start;
begin
  Check(SetEvent(FStart), 'Could not release child start barrier');
end;

procedure TChildGroup.WaitReady;
var
  Handles: TArray<THandle>;
  Index: Integer;
begin
  SetLength(Handles, Length(FChildren));
  for Index := 0 to High(FChildren) do
    Handles[Index] := FChildren[Index].Ready;
  Check(WaitForMultipleObjects(Length(Handles), @Handles[0], True, TimeoutMs) =
    WAIT_OBJECT_0, 'Children did not complete instance arbitration (' + FMode + ')');
end;

procedure TChildGroup.Release;
begin
  Check(SetEvent(FRelease), 'Could not release primary child');
end;

procedure TChildGroup.VerifyExits;
var
  Handles: TArray<THandle>;
  Index: Integer;
  Actual, Expected: DWORD;
begin
  SetLength(Handles, Length(FChildren));
  for Index := 0 to High(FChildren) do
    Handles[Index] := FChildren[Index].Process;
  Check(WaitForMultipleObjects(Length(Handles), @Handles[0], True, TimeoutMs) =
    WAIT_OBJECT_0, 'Child process did not finish (' + FMode + ')');
  for Index := 0 to High(FChildren) do
  begin
    Expected := 0;
    if (FMode = 'contend') and
      (WaitForSingleObject(FChildren[Index].Primary, 0) = WAIT_OBJECT_0) then
      Expected := PrimaryContenderExit;
    Check(GetExitCodeProcess(FChildren[Index].Process, Actual),
      'Could not read child exit code');
    Check(Actual = Expected, Format('Child %d (%s) exited with %d; expected %d',
      [Index, FMode, Actual, Expected]));
  end;
end;

function TChildGroup.PrimaryCount: Integer;
var
  Child: TChildProcess;
begin
  Result := 0;
  for Child in FChildren do
    if WaitForSingleObject(Child.Primary, 0) = WAIT_OBJECT_0 then
      Inc(Result);
end;

procedure RunChild;
var
  Instance: TDashboardInstance;
  StartEvent, ReleaseEvent, ReadyEvent, PrimaryEvent: THandle;
  Prefix, Mode: string;
  Index: Integer;
begin
  Check(ParamCount = 5, 'Invalid child arguments');
  Prefix := ParamStr(3);
  Mode := ParamStr(4);
  Index := StrToInt(ParamStr(5));
  StartEvent := OpenControlEvent(ControlName(Prefix, 'Start'));
  try
    ReleaseEvent := OpenControlEvent(ControlName(Prefix, 'Release'));
    try
      ReadyEvent := OpenControlEvent(ControlName(Prefix, 'Ready', Index));
      try
        PrimaryEvent := OpenControlEvent(ControlName(Prefix, 'Primary', Index));
        try
          WaitForControl(StartEvent, 'child start barrier');
          Instance := TDashboardInstance.Create(ParamStr(2));
          try
            if (Mode = 'primary') or (Mode = 'crash') then
              Check(Instance.IsPrimary, 'Expected this child to become primary')
            else if Mode <> 'contend' then
              Check(not Instance.IsPrimary, 'Duplicate child became primary');
            if Instance.IsPrimary then
              Check(SetEvent(PrimaryEvent), 'Could not report primary ownership')
            else if Mode <> 'duplicate-quiet' then
            begin
              Instance.RequestActivation;
              Check(not Instance.ConsumeActivationRequest,
                'Secondary must not consume the primary activation request');
            end;
            Check(SetEvent(ReadyEvent), 'Could not report child readiness');
            if Instance.IsPrimary then
            begin
              WaitForControl(ReleaseEvent, 'primary child release');
              if Mode = 'crash' then
                // Deliberately omit Free/ReleaseMutex: the OS abandons ownership.
                ExitProcess(0);
              if Mode = 'contend' then
              begin
                Check(Instance.ConsumeActivationRequest,
                  'Concurrent duplicate startup lost its activation request');
                Check(not Instance.ConsumeActivationRequest,
                  'Concurrent startup request was not reset after consumption');
                ExitCode := PrimaryContenderExit;
              end;
            end;
          finally
            Instance.Free;
          end;
        finally
          CloseHandle(PrimaryEvent);
        end;
      finally
        CloseHandle(ReadyEvent);
      end;
    finally
      CloseHandle(ReleaseEvent);
    end;
  finally
    CloseHandle(StartEvent);
  end;
end;

procedure TestExistingPrimaryAndActivation;
var
  Prefix: string;
  Primary: TDashboardInstance;
  Children: TChildGroup;
begin
  Prefix := NewPrefix;
  Primary := TDashboardInstance.Create(Prefix);
  try
    Check(Primary.IsPrimary, 'First process must become primary');
    Check(not Primary.ConsumeActivationRequest, 'Fresh instance has a stale request');
    // This models a duplicate collector launch: the startup caller intentionally
    // does not request a visible dashboard. Actual --collector routing is in DPR.
    Children := TChildGroup.Create(Prefix, 'duplicate-quiet', 1);
    try
      Children.Start;
      Children.WaitReady;
      Children.VerifyExits;
      Check(Children.PrimaryCount = 0, 'Quiet duplicate became primary');
      Check(not Primary.ConsumeActivationRequest, 'Quiet duplicate requested activation');
    finally
      Children.Free;
    end;
    Children := TChildGroup.Create(Prefix, 'duplicate-request', 1);
    try
      Children.Start;
      Children.WaitReady;
      Children.VerifyExits;
      // There is deliberately no form or event pump yet. The request must survive
      // until startup is complete and the primary can show its dashboard.
      Check(Primary.ConsumeActivationRequest, 'Request during startup was lost');
      Check(not Primary.ConsumeActivationRequest, 'Consumed request remained pending');
    finally
      Children.Free;
    end;
    Children := TChildGroup.Create(Prefix, 'duplicate-request', ConcurrentStarts);
    try
      Children.Start;
      Children.WaitReady;
      Children.VerifyExits;
      Check(Children.PrimaryCount = 0, 'Parallel duplicate became primary');
      Check(Primary.ConsumeActivationRequest, 'Parallel requests did not reach primary');
      Check(not Primary.ConsumeActivationRequest, 'Parallel requests did not coalesce');
    finally
      Children.Free;
    end;
  finally
    Primary.Free;
  end;
  Writeln('INSTANCE_EXISTING_PRIMARY_ACTIVATION_OK');
end;

procedure TestConcurrentFirstStarts;
var
  Children: TChildGroup;
begin
  // Start all processes from one barrier with no pre-existing primary. The
  // winner retains ownership until every competitor has made its decision.
  Children := TChildGroup.Create(NewPrefix, 'contend', ConcurrentStarts);
  try
    Children.Start;
    Children.WaitReady;
    Check(Children.PrimaryCount = 1, 'Concurrent first starts must have exactly one primary');
    Children.Release;
    Children.VerifyExits;
  finally
    Children.Free;
  end;
  Writeln('INSTANCE_CONCURRENT_FIRST_STARTS_OK');
end;

procedure TestReleaseAndRestart;
var
  Prefix: string;
  Instance: TDashboardInstance;
  Children: TChildGroup;
begin
  Prefix := NewPrefix;
  Instance := TDashboardInstance.Create(Prefix);
  try
    Check(Instance.IsPrimary, 'Initial release fixture must become primary');
  finally
    Instance.Free;
  end;
  Children := TChildGroup.Create(Prefix, 'primary', 1);
  try
    Children.Start;
    Children.WaitReady;
    Check(Children.PrimaryCount = 1, 'Released instance prevented a process restart');
    Instance := TDashboardInstance.Create(Prefix);
    try
      Check(not Instance.IsPrimary, 'Restarted process did not retain mutex ownership');
    finally
      Instance.Free;
    end;
    Children.Release;
    Children.VerifyExits;
  finally
    Children.Free;
  end;
  Instance := TDashboardInstance.Create(Prefix);
  try
    Check(Instance.IsPrimary, 'Normal child exit prevented subsequent restart');
    Check(not Instance.ConsumeActivationRequest, 'Restart retained a stale activation request');
  finally
    Instance.Free;
  end;
  Writeln('INSTANCE_RELEASE_RESTART_OK');
end;

function CurrentUserSid: string;
var
  Token: THandle;
  Needed: DWORD;
  Buffer: TBytes;
  SidText: PChar;
begin
  Check(OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token), 'OpenProcessToken failed');
  try
    Needed := 0;
    GetTokenInformation(Token, TokenUser, nil, 0, Needed);
    Check(Needed > 0, 'Token user size was not returned');
    SetLength(Buffer, Needed);
    Check(GetTokenInformation(Token, TokenUser, @Buffer[0], Needed, Needed),
      'Could not read token user');
    SidText := nil;
    Check(ConvertSidToStringSidForTest(PTokenUser(@Buffer[0])^.User.Sid, SidText),
      'Could not format user SID');
    try
      Result := string(SidText);
    finally
      LocalFree(HLOCAL(SidText));
    end;
  finally
    CloseHandle(Token);
  end;
end;

procedure TestAbandonedOwnerRecovery;
var
  Prefix, MutexName: string;
  RetainedMutex: THandle;
  Children: TChildGroup;
  Instance: TDashboardInstance;
begin
  Prefix := NewPrefix;
  Children := TChildGroup.Create(Prefix, 'crash', 1);
  try
    Children.Start;
    Children.WaitReady;
    Check(Children.PrimaryCount = 1, 'Crash fixture did not become primary');
    // Retain a handle without taking ownership, so the kernel object survives
    // owner termination. Without this handle the test would only check creation
    // of a fresh mutex, never Windows' WAIT_ABANDONED recovery path.
    MutexName := 'Local\' + Prefix + '.' + CurrentUserSid + '.Mutex';
    RetainedMutex := OpenMutex(SYNCHRONIZE or MUTEX_MODIFY_STATE, False, PChar(MutexName));
    Check(RetainedMutex <> 0, 'Could not retain crash fixture mutex');
    try
      Children.Release;
      Children.VerifyExits;
      Instance := TDashboardInstance.Create(Prefix);
      try
        Check(Instance.IsPrimary, 'Abandoned mutex did not admit a replacement primary');
        Check(not Instance.ConsumeActivationRequest, 'Crash recovery invented an activation request');
      finally
        Instance.Free;
      end;
    finally
      CloseHandle(RetainedMutex);
    end;
  finally
    Children.Free;
  end;
  Writeln('INSTANCE_ABANDONED_OWNER_RECOVERY_OK');
end;

procedure RunAppSecondaries(const AExecutable, AArguments: string;
  ACount: Integer);
var
  Processes: TArray<THandle>;
  Startup: TStartupInfo;
  ChildInfo: TProcessInformation;
  Command: string;
  Index: Integer;
  Code: DWORD;
begin
  Check((ACount > 0) and (ACount <= MAXIMUM_WAIT_OBJECTS), 'Invalid app child count');
  SetLength(Processes, ACount);
  try
    for Index := 0 to High(Processes) do
    begin
      FillChar(Startup, SizeOf(Startup), 0);
      Startup.cb := SizeOf(Startup);
      Startup.dwFlags := STARTF_USESHOWWINDOW;
      Startup.wShowWindow := SW_HIDE;
      FillChar(ChildInfo, SizeOf(ChildInfo), 0);
      Command := '"' + AExecutable + '"';
      if AArguments <> '' then
        Command := Command + ' ' + AArguments;
      UniqueString(Command);
      Check(CreateProcess(PChar(AExecutable), PChar(Command), nil, nil,
        False, CREATE_NO_WINDOW, nil, nil, Startup, ChildInfo),
        'Could not start actual application as secondary');
      Processes[Index] := ChildInfo.hProcess;
      CloseHandle(ChildInfo.hThread);
    end;
    Check(WaitForMultipleObjects(Length(Processes), @Processes[0], True,
      TimeoutMs) = WAIT_OBJECT_0, 'Actual secondary app did not exit promptly');
    for Index := 0 to High(Processes) do
    begin
      Check(GetExitCodeProcess(Processes[Index], Code), 'Could not read app exit code');
      Check(Code = 0, Format('Actual secondary app %d (%s) exited with %d',
        [Index, AArguments, Code]));
    end;
  finally
    for Index := 0 to High(Processes) do
      if Processes[Index] <> 0 then
      begin
        if WaitForSingleObject(Processes[Index], 0) = WAIT_TIMEOUT then
        begin
          // Only our explicitly created secondary test processes are terminated.
          TerminateProcess(Processes[Index], 99);
          WaitForSingleObject(Processes[Index], 1000);
        end;
        CloseHandle(Processes[Index]);
      end;
  end;
end;

procedure TestActualAppSecondaries(const AExecutable: string);
var
  Guard: TDashboardInstance;
begin
  Check(FileExists(AExecutable), 'Actual application executable does not exist');
  // This opt-in integration fixture is the only test using the production
  // namespace. It owns the default guard before starting any actual app, so all
  // app launches must leave through DPR's secondary path before creating FMX,
  // collectors or publishers. Never send a request to a user's live dashboard.
  Guard := TDashboardInstance.Create;
  try
    if not Guard.IsPrimary then
    begin
      Writeln('INSTANCE_ACTUAL_APP_SECONDARIES_SKIPPED: existing dashboard');
      Exit;
    end;
    Check(not Guard.ConsumeActivationRequest, 'Actual-app fixture has a stale request');
    RunAppSecondaries(AExecutable, '', 1);
    Check(Guard.ConsumeActivationRequest,
      'Normal actual app secondary did not request dashboard activation');
    Check(not Guard.ConsumeActivationRequest,
      'Actual app activation did not reset after consumption');
    RunAppSecondaries(AExecutable, '--collector', 1);
    Check(not Guard.ConsumeActivationRequest,
      'Actual --collector secondary incorrectly requested dashboard activation');
    RunAppSecondaries(AExecutable, '', ConcurrentStarts);
    Check(Guard.ConsumeActivationRequest,
      'Parallel actual app secondaries did not request dashboard activation');
    Check(not Guard.ConsumeActivationRequest,
      'Parallel actual app activations did not coalesce');
  finally
    Guard.Free;
  end;
  Writeln('INSTANCE_ACTUAL_APP_SECONDARIES_OK');
end;

begin
  try
    if (ParamCount > 0) and SameText(ParamStr(1), '--child') then
      RunChild
    else
    begin
      TestExistingPrimaryAndActivation;
      TestConcurrentFirstStarts;
      TestReleaseAndRestart;
      TestAbandonedOwnerRecovery;
      if ParamCount > 0 then
      begin
        Check((ParamCount = 2) and SameText(ParamStr(1), '--app'),
          'Usage: Instance.Tests.exe [--app absolute-executable-path]');
        TestActualAppSecondaries(ExpandFileName(ParamStr(2)));
      end;
      Writeln('INSTANCE_TEST_OK');
    end;
  except
    on E: Exception do
    begin
      Writeln('INSTANCE_TEST_FAILED: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
