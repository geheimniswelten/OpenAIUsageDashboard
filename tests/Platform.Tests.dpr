program PlatformTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  System.DateUtils,
  Winapi.Windows,
  Winapi.Messages,
  FMX.Forms,
  Dashboard.DisplayPolicy in '..\Dashboard.DisplayPolicy.pas',
  Dashboard.Platform in '..\Dashboard.Platform.pas';

type
  TSuppressedForm = class(TForm)
  public
    function CanShow: Boolean; override;
  end;

  { Exercise coordinator transitions without affecting the test machine's
    display power, execution requests or diagnostic files. }
  TTestCoordinator = class(TPlatformCoordinator)
  public
    AppliedFlags: EXECUTION_STATE;
    ApplyCount: Integer;
    WakeCount: Integer;
    FailNextRequest: Boolean;
    function ApplyWindowsExecutionState(const AFlags: EXECUTION_STATE): Boolean; override;
    procedure WakeWindowsDisplays; override;
    procedure LogWindowsEvent(const AText: string); override;
    procedure SetDisplayAwake(const AEnabled: Boolean);
    procedure Resume;
  end;

var
  LastAppliedFlags: EXECUTION_STATE;

function TTestCoordinator.ApplyWindowsExecutionState(
  const AFlags: EXECUTION_STATE): Boolean;
begin
  Inc(ApplyCount);
  Result := not FailNextRequest;
  FailNextRequest := False;
  if Result then
  begin
    AppliedFlags := AFlags;
    LastAppliedFlags := AFlags;
  end;
end;

procedure TTestCoordinator.WakeWindowsDisplays;
begin
  Inc(WakeCount);
end;

procedure TTestCoordinator.LogWindowsEvent(const AText: string);
begin
end;

procedure TTestCoordinator.SetDisplayAwake(const AEnabled: Boolean);
begin
  SetKeepAwake(AEnabled);
end;

procedure TTestCoordinator.Resume;
var
  Message: TMessage;
begin
  FillChar(Message, SizeOf(Message), 0);
  Message.Msg := WM_POWERBROADCAST;
  Message.WParam := PBT_APMRESUMEAUTOMATIC;
  WindowsMessage(Message);
end;

function TSuppressedForm.CanShow: Boolean;
begin
  Result := False;
end;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure CheckSchedule;
var
  Monday: TDateTime;
  I: Integer;
begin
  Monday := EncodeDate(2026, 9, 7);
  for I := 0 to 6 do
  begin
    Check(not InKeepAwakeWindow(Monday + I + EncodeTime(9, 59, 59, 999), 10, 18),
      'Display must be released before 10:00');
    Check(InKeepAwakeWindow(Monday + I + EncodeTime(10, 0, 0, 0), 10, 18) = (I < 5),
      '10:00 must activate on weekdays only');
    Check(InKeepAwakeWindow(Monday + I + EncodeTime(17, 59, 59, 999), 10, 18) = (I < 5),
      'Display must stay awake until 18:00 on weekdays');
    Check(not InKeepAwakeWindow(Monday + I + EncodeTime(18, 0, 0, 0), 10, 18),
      '18:00 must release the display');
  end;
  Check(InKeepAwakeWindow(Monday, 0, 24), 'Full-day window starts at midnight');
end;

procedure CheckMonitorRecovery;
var
  Preference: TDashboardDisplayPreference;
begin
  Preference := TDashboardDisplayPreference.Create(1);
  Check(Preference.Resolve(['internal', 'wall'], 0) = 1, 'Select configured display');
  Check(Preference.Resolve(['internal'], 0) = 0, 'Fall back while wall display is absent');
  Check(Preference.Resolve(['internal', 'wall'], 0) = 1, 'Restore original display');
  Check(Preference.Resolve(['wall', 'internal'], 1) = 0, 'Follow identity after index reorder');
  Check(Preference.Resolve(['internal', 'different'], 0) = 1, 'Allow temporary external fallback');
  Check(Preference.Resolve(['wall', 'different', 'internal'], 2) = 0,
    'Same-count replacement must not overwrite preferred identity');
  Check(Preference.Resolve([], 0) = -1, 'Handle complete display removal');
  Check(Preference.Resolve(['internal', 'WALL'], 0) = 1, 'Restore after all displays were removed');

  Preference := TDashboardDisplayPreference.Create(-1);
  Check(Preference.Resolve(['internal'], 0) = 0, 'Auto mode starts on internal display');
  Check(Preference.Resolve(['internal', 'wall'], 0) = 1, 'Auto mode adopts arriving external display');
  Check(Preference.Resolve(['internal'], 0) = 0, 'Auto mode falls back');
  Check(Preference.Resolve(['other', 'internal', 'wall'], 1) = 2,
    'Auto mode restores its original external display');

  Preference := TDashboardDisplayPreference.Create(2);
  Check(Preference.Resolve(['internal'], 0) = 0, 'Handle unavailable configured index at startup');
  Check(Preference.Resolve(['internal', 'other', 'wall'], 0) = 2,
    'Remember configured index until it first becomes available');
  Preference := TDashboardDisplayPreference.Create(0);
  Check(Preference.Resolve(['wall', 'internal'], 1) = 0, 'Explicit monitor selection');
  Check(Preference.Resolve(['internal', 'wall'], 0) = 1, 'Explicit choice survives primary change');
end;

procedure CheckPowerTransitions(const AForm: TForm);
const
  SystemOnly = ES_CONTINUOUS or ES_SYSTEM_REQUIRED;
  SystemAndDisplay = SystemOnly or ES_DISPLAY_REQUIRED;
var
  Coordinator: TTestCoordinator;
  Count: Integer;
begin
  Coordinator := TTestCoordinator.Create(AForm);
  try
    Coordinator.SetDisplayAwake(False);
    Check(Coordinator.AppliedFlags = SystemOnly, 'Nighttime startup must keep the timer running');
    Check(Coordinator.WakeCount = 0, 'Nighttime startup must not wake the display');
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.KeepAwake, 'Successful morning transition');
    Check(Coordinator.AppliedFlags = SystemAndDisplay, 'Morning must require system and display');
    Check(Coordinator.WakeCount = 1, 'Morning must explicitly wake the display');
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 1, 'Ordinary timer ticks must not repeatedly wake the display');
    Count := Coordinator.ApplyCount;
    Coordinator.Resume;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.ApplyCount = Count + 1, 'Resume must immediately reapply the power request');
    Check(Coordinator.WakeCount = 2, 'Resume during daytime must restore display power');
    Coordinator.SetDisplayAwake(False);
    Check(Coordinator.AppliedFlags = SystemOnly, '18:00 releases display but retains system request');
    Coordinator.Resume;
    Coordinator.SetDisplayAwake(False);
    Check(Coordinator.WakeCount = 2, 'Resume at night must not wake the display');
    Coordinator.FailNextRequest := True;
    Coordinator.SetDisplayAwake(True);
    Check(not Coordinator.KeepAwake, 'A failed API call must not mark the display awake');
    Check(Coordinator.WakeCount = 2, 'Failed power request must not issue a wake command');
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.KeepAwake and (Coordinator.WakeCount = 3),
      'Retry must apply and wake after a transient API failure');
    Coordinator.SetCollectorOnly(True);
    Check(Coordinator.AppliedFlags = SystemOnly, 'Daytime collector must release display request');
    Coordinator.SetDisplayAwake(False);
    Check(Coordinator.AppliedFlags = ES_CONTINUOUS, 'Nighttime collector retains original power policy');
    Check(Coordinator.WakeCount = 3, 'Collector must not wake displays');
    Coordinator.SetCollectorOnly(False);
    Check(Coordinator.AppliedFlags = SystemOnly, 'Returning to dashboard at night must keep PC awake');
  finally
    Coordinator.Free;
  end;
  Check(LastAppliedFlags = ES_CONTINUOUS, 'Destruction must release all execution requests');
end;

procedure Run;
var
  Form: TSuppressedForm;
  Coordinator: TTestCoordinator;
  FormCount: Integer;
  Bounds: TRectF;
begin
  Application.Initialize;
  CheckSchedule;
  CheckMonitorRecovery;
  Form := TSuppressedForm.CreateNew(nil);
  try
    CheckPowerTransitions(Form);
    Form.SetBounds(17, 23, 320, 200);
    Form.Show;
    Check(not Form.Visible, 'CanShow must suppress the initial FMX window');
    FormCount := Screen.FormCount;
    Bounds := TRectF.Create(Form.Left, Form.Top, Form.Left + Form.Width,
      Form.Top + Form.Height);
    Coordinator := TTestCoordinator.Create(Form);
    try
      Coordinator.SetCollectorOnly(True);
      Coordinator.Tick(10, 18, 10);
      Coordinator.PlaceDashboard(-1);
      Coordinator.NotifyInteraction(10);
      Check(not Form.Visible, 'Collector operations must not reveal the main window');
      Check(Screen.FormCount = FormCount, 'Collector must not create blackout forms');
      Check((Form.Left = Bounds.Left) and (Form.Top = Bounds.Top) and
        (Form.Width = Bounds.Width) and (Form.Height = Bounds.Height),
        'Collector must not move or resize the main window');
      Coordinator.SetCollectorOnly(False);
      Check(Screen.FormCount = FormCount, 'Mode switch alone must not create blackout forms');
    finally
      Coordinator.Free;
    end;
  finally
    Form.Free;
  end;
end;

begin
  try
    Run;
    Writeln('PLATFORM_TESTS_OK: schedule, wake/release/resume, API retry, monitor recovery, collector isolation');
  except
    on E: Exception do
    begin
      Writeln('COLLECTOR_PLATFORM_TESTS_FAILED: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
