program PlatformTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.DateUtils,
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Winapi.Messages,
  FMX.Forms,
  FMX.Types,
  FMX.Platform.Win,
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
    UseFakeTick: Boolean;
    FakeTick: UInt64;
    ReportOnDuringWake: Boolean;
    RestoreCallbackCount: Integer;
    function WindowsTick: UInt64; override;
    function ApplyWindowsExecutionState(const AFlags: EXECUTION_STATE): Boolean; override;
    procedure WakeWindowsDisplays; override;
    procedure LogWindowsEvent(const AText: string); override;
    procedure SetDisplayAwake(const AEnabled: Boolean);
    procedure Resume;
    procedure ReportDisplayStatus(const AStatus: DWORD;
      const ADataLength: DWORD = SizeOf(DWORD));
    procedure ReportOtherPowerSetting(const AStatus: DWORD);
    procedure ReportNilPowerSetting;
    procedure DashboardRestored(ASender: TObject);
  end;

  TDisplayPowerSetting = packed record
    PowerSetting: TGUID;
    DataLength: DWORD;
    Data: DWORD;
  end;

var
  LastAppliedFlags: EXECUTION_STATE;

function TTestCoordinator.WindowsTick: UInt64;
begin
  if UseFakeTick then
    Result := FakeTick
  else
    Result := inherited WindowsTick;
end;

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
  if ReportOnDuringWake then
    ReportDisplayStatus(1);
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

procedure TTestCoordinator.ReportDisplayStatus(const AStatus: DWORD;
  const ADataLength: DWORD);
const
  SessionDisplayStatus: TGUID = '{2B84C20E-AD23-4DDF-93DB-05FFBD7EFCA5}';
var
  Setting: TDisplayPowerSetting;
  Message: TMessage;
begin
  FillChar(Setting, SizeOf(Setting), 0);
  Setting.PowerSetting := SessionDisplayStatus;
  Setting.DataLength := ADataLength;
  Setting.Data := AStatus;
  FillChar(Message, SizeOf(Message), 0);
  Message.Msg := WM_POWERBROADCAST;
  Message.WParam := $8013; { PBT_POWERSETTINGCHANGE }
  Message.LParam := LPARAM(@Setting);
  WindowsMessage(Message);
end;

procedure TTestCoordinator.ReportOtherPowerSetting(const AStatus: DWORD);
const
  ConsoleDisplayState: TGUID = '{6FE69556-704A-47A0-8F24-C28D936FDA47}';
var
  Setting: TDisplayPowerSetting;
  Message: TMessage;
begin
  FillChar(Setting, SizeOf(Setting), 0);
  Setting.PowerSetting := ConsoleDisplayState;
  Setting.DataLength := SizeOf(DWORD);
  Setting.Data := AStatus;
  FillChar(Message, SizeOf(Message), 0);
  Message.Msg := WM_POWERBROADCAST;
  Message.WParam := $8013;
  Message.LParam := LPARAM(@Setting);
  WindowsMessage(Message);
end;

procedure TTestCoordinator.ReportNilPowerSetting;
var
  Message: TMessage;
begin
  FillChar(Message, SizeOf(Message), 0);
  Message.Msg := WM_POWERBROADCAST;
  Message.WParam := $8013;
  WindowsMessage(Message);
end;

procedure TTestCoordinator.DashboardRestored(ASender: TObject);
begin
  Inc(RestoreCallbackCount);
  RestoreWindowsDashboard;
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

function CreateClockedCoordinator(const AForm: TForm): TTestCoordinator;
begin
  Result := TTestCoordinator.Create(AForm);
  Result.UseFakeTick := True;
  Result.FakeTick := 1000;
end;

procedure CheckDisplayWakeRetries(const AForm: TForm);
var
  Coordinator: TTestCoordinator;
  Status, I, Count: Integer;
begin
  Coordinator := CreateClockedCoordinator(AForm);
  try
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 1, 'Morning must request display power immediately');
    Coordinator.FakeTick := 5999;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 1, 'Wake retry must wait five seconds');
    for I := 1 to 3 do
    begin
      Coordinator.FakeTick := 1000 + UInt64(I) * 5000;
      Coordinator.SetDisplayAwake(True);
      Check(Coordinator.WakeCount = I + 1,
        'Unknown display state must retry at 5, 10 and 15 seconds');
    end;
    Coordinator.FakeTick := 180000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 4,
      'Unknown display state must stop after three retries');
    Coordinator.ReportDisplayStatus(0);
    Coordinator.FakeTick := 184999;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 4, 'New off report must not immediately repeat wake');
    Coordinator.FakeTick := 185000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 5,
      'An off report must restart wake attempts after unknown-state retries ended');
  finally
    Coordinator.Free;
  end;

  for Status in [0, 2] do
  begin
    Coordinator := CreateClockedCoordinator(AForm);
    try
      Coordinator.ReportDisplayStatus(Status);
      Coordinator.SetDisplayAwake(True);
      for I := 1 to 3 do
      begin
        Coordinator.FakeTick := 1000 + UInt64(I) * 5000;
        Coordinator.SetDisplayAwake(True);
        Check(Coordinator.WakeCount = I + 1,
          'Reported off/dim state must receive three fast retries');
      end;
      Coordinator.FakeTick := 75999;
      Coordinator.SetDisplayAwake(True);
      Check(Coordinator.WakeCount = 4,
        'Persistent off/dim state must wait sixty seconds after fast retries');
      Coordinator.FakeTick := 76000;
      Coordinator.SetDisplayAwake(True);
      Check(Coordinator.WakeCount = 5, 'Persistent off/dim state must keep retrying');
      Check(Coordinator.AppliedFlags =
        (ES_CONTINUOUS or ES_SYSTEM_REQUIRED or ES_DISPLAY_REQUIRED),
        'Wake retries must retain the system and display execution request');
      Coordinator.ReportDisplayStatus(1);
      Count := Coordinator.WakeCount;
      Coordinator.FakeTick := 136000;
      Coordinator.SetDisplayAwake(True);
      Check(Coordinator.WakeCount = Count, 'Display-on confirmation must cancel retries');
      Coordinator.ReportDisplayStatus(Status);
      Coordinator.FakeTick := 140999;
      Coordinator.SetDisplayAwake(True);
      Check(Coordinator.WakeCount = Count, 'Off/dim after on must wait five seconds');
      Coordinator.FakeTick := 141000;
      Coordinator.SetDisplayAwake(True);
      Check(Coordinator.WakeCount = Count + 1,
        'Off/dim after on must restart retries within five seconds');
    finally
      Coordinator.Free;
    end;
  end;

  Coordinator := CreateClockedCoordinator(AForm);
  try
    Coordinator.SetDisplayAwake(True);
    Coordinator.ReportOtherPowerSetting(1);
    Coordinator.ReportDisplayStatus(1, 1);
    Coordinator.ReportDisplayStatus(1, 8);
    Coordinator.ReportDisplayStatus(High(DWORD));
    Coordinator.ReportNilPowerSetting;
    Coordinator.FakeTick := 6000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 2,
      'Other GUIDs, invalid data lengths, invalid states and nil payloads must not confirm display-on');
  finally
    Coordinator.Free;
  end;

  Coordinator := CreateClockedCoordinator(AForm);
  try
    Coordinator.ReportOnDuringWake := True;
    Coordinator.SetDisplayAwake(True);
    Coordinator.FakeTick := 6000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 1,
      'Synchronous display-on confirmation during initial wake must cancel retries');
    Coordinator.ReportOnDuringWake := False;
    Coordinator.ReportDisplayStatus(0);
    Coordinator.ReportOnDuringWake := True;
    Coordinator.FakeTick := 11000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 2, 'Off notification must wake again after five seconds');
    Coordinator.FakeTick := 16000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 2,
      'Synchronous display-on confirmation during a retry must cancel further retries');
  finally
    Coordinator.Free;
  end;
end;

procedure CheckDisplayWakeCancellation(const AForm: TForm);
var
  Coordinator: TTestCoordinator;
begin
  Coordinator := CreateClockedCoordinator(AForm);
  try
    Coordinator.ReportDisplayStatus(0);
    Coordinator.SetDisplayAwake(True);
    Coordinator.FakeTick := 2000;
    Coordinator.SetDisplayAwake(False);
    Coordinator.ReportDisplayStatus(0);
    Coordinator.FakeTick := 120000;
    Coordinator.SetDisplayAwake(False);
    Check(Coordinator.WakeCount = 1, 'Nighttime must cancel all pending display wake retries');
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 2, 'The next morning must start a new wake attempt');
    Coordinator.SetCollectorOnly(True);
    Coordinator.ReportDisplayStatus(2);
    Coordinator.FakeTick := 240000;
    Coordinator.SetDisplayAwake(True);
    Check(Coordinator.WakeCount = 2, 'Collector mode must cancel retries and ignore dim notifications');
    Coordinator.SetCollectorOnly(False);
    Check(Coordinator.WakeCount = 3, 'Returning to dashboard during daytime must wake immediately');
  finally
    Coordinator.Free;
  end;
end;

procedure CheckNativeDashboardBounds(const AForm: TForm;
  const ACoordinator: TTestCoordinator);
var
  I, J, BlackFormCount: Integer;
  NativeBounds, ExpectedBounds: TRect;
  OtherForm: TCommonCustomForm;
  MatchedDisplay: Boolean;
  Display: TDisplay;
begin
  Check((ACoordinator.TargetDisplay >= 0) and
    (ACoordinator.TargetDisplay < Screen.DisplayCount), 'Dashboard must select a real monitor');
  Display := Screen.Displays[ACoordinator.TargetDisplay];
  ExpectedBounds := Display.PhysicalBounds;
  if ExpectedBounds.Height > 1 then
    Dec(ExpectedBounds.Bottom);
  Check(GetWindowRect(FormToHWND(AForm), NativeBounds), 'Dashboard must have native window bounds');
  Check(EqualRect(NativeBounds, ExpectedBounds),
    'Dashboard must leave exactly one physical pixel uncovered at the bottom');
  Check(Abs(AForm.Height - (Display.Bounds.Height - 1 / Display.Scale)) < 0.01,
    'Dashboard logical height must account for its monitor DPI scale');
  Check(not AForm.FullScreen, 'Windows dashboard must avoid FMX fullscreen mode');
  BlackFormCount := 0;
  for I := 0 to Screen.FormCount - 1 do
  begin
    OtherForm := Screen.Forms[I];
    if OtherForm.Caption <> 'OpenAI Dashboard · abgedunkelter Bildschirm' then
      Continue;
    Inc(BlackFormCount);
    Check(GetWindowRect(FormToHWND(OtherForm), NativeBounds),
      'Blackout form must have native window bounds');
    MatchedDisplay := False;
    for J := 0 to Screen.DisplayCount - 1 do
      if J <> ACoordinator.TargetDisplay then
      begin
        Display := Screen.Displays[J];
        ExpectedBounds := Display.PhysicalBounds;
        if ExpectedBounds.Height > 1 then
          Dec(ExpectedBounds.Bottom);
        if EqualRect(NativeBounds, ExpectedBounds) then
        begin
          Check(Abs(OtherForm.Height - (Display.Bounds.Height - 1 / Display.Scale)) < 0.01,
            'Blackout logical height must account for its monitor DPI scale');
          MatchedDisplay := True;
          Break;
        end;
      end;
    Check(MatchedDisplay, 'Blackout form must leave one physical pixel on another monitor');
  end;
  Check(BlackFormCount = Screen.DisplayCount - 1,
    Format('Coordinator must create one blackout form for each other monitor (actual=%d expected=%d)',
      [BlackFormCount, Screen.DisplayCount - 1]));
end;

procedure CheckTaskbarStyle(const AWindow: HWND; const AVisible: Boolean);
var
  Style: NativeInt;
begin
  Style := GetWindowLongPtr(AWindow, GWL_EXSTYLE);
  if AVisible then
    Check(Style and WS_EX_TOOLWINDOW = 0, 'Tray failure must restore taskbar eligibility')
  else
    Check((Style and WS_EX_TOOLWINDOW <> 0) and (Style and WS_EX_APPWINDOW = 0),
      'A working tray must suppress native taskbar buttons');
end;

procedure CheckNativeDashboardRecovery;
var
  Form: TForm;
  PreviousMainForm: TCommonCustomForm;
  Coordinator: TTestCoordinator;
  WindowHandle, AppHandle, ForegroundHandle: HWND;
begin
  Form := TForm.CreateNew(nil);
  PreviousMainForm := Application.MainForm;
  try
    Application.MainForm := Form;
    Form.Caption := 'Platform native recovery test';
    Form.SetBounds(17, 23, 320, 200);
    Form.Show;
    Coordinator := CreateClockedCoordinator(Form);
    try
      { Keep the auxiliary forms hidden while checking their native geometry. }
      Coordinator.NotifyInteraction(10);
      Coordinator.SetTaskbarVisible(False);
      Coordinator.PlaceDashboard(-1);
      CheckNativeDashboardBounds(Form, Coordinator);
      WindowHandle := FormToHWND(Form);
      AppHandle := ApplicationHWND;
      CheckTaskbarStyle(AppHandle, False);
      CheckTaskbarStyle(WindowHandle, False);
      Winapi.Windows.ShowWindow(AppHandle, SW_MINIMIZE);
      Check(IsIconic(AppHandle), 'Test must minimize the FMX taskbar proxy');
      Coordinator.PlaceDashboard(-1);
      Check(IsIconic(AppHandle), 'Automatic placement must preserve taskbar minimization');
      Coordinator.Resume;
      Coordinator.FakeTick := 2000;
      Coordinator.Tick(0, 24, 10);
      Check(IsIconic(AppHandle), 'Refresh after resume must preserve taskbar minimization');
      Coordinator.RestoreWindowsDashboard;
      CheckTaskbarStyle(AppHandle, False);
      CheckTaskbarStyle(WindowHandle, False);
      Check(not IsIconic(AppHandle) and not IsIconic(WindowHandle) and
        IsWindowVisible(WindowHandle), 'Explicit restore must recover minimized taskbar and dashboard windows');
      CheckNativeDashboardBounds(Form, Coordinator);
      Winapi.Windows.ShowWindow(WindowHandle, SW_MINIMIZE);
      Check(IsIconic(WindowHandle), 'Test must minimize the native dashboard window');
      Coordinator.PlaceDashboard(-1);
      Coordinator.Tick(0, 24, 10);
      Check(IsIconic(WindowHandle), 'Placement and timer must preserve native dashboard minimization');
      Coordinator.RestoreWindowsDashboard;
      Check(not IsIconic(AppHandle) and not IsIconic(WindowHandle) and
        IsWindowVisible(WindowHandle),
        'Explicit restore must recover dashboard and taskbar after native dashboard minimization');
      Winapi.Windows.ShowWindow(WindowHandle, SW_HIDE);
      Check(Form.Visible and not IsWindowVisible(WindowHandle),
        'Test must leave a visible FMX form with a hidden native window');
      ForegroundHandle := GetForegroundWindow;
      Coordinator.FakeTick := 3000;
      Coordinator.Tick(0, 24, 10);
      Check(IsWindowVisible(WindowHandle),
        'Automatic refresh must recover a hidden native window when FMX caches Visible=True');
      Check(GetForegroundWindow = ForegroundHandle,
        'Automatic hidden-window recovery must preserve the foreground window');
      Winapi.Windows.ShowWindow(WindowHandle, SW_HIDE);
      Check(not IsWindowVisible(WindowHandle), 'Test must hide the native dashboard window');
      Check(Form.Visible, 'Native hide must preserve the cached FMX Visible=True state');
      Coordinator.RestoreWindowsDashboard;
      Check(IsWindowVisible(WindowHandle),
        'Explicit restore must show a native window even when FMX still caches Visible=True');
      CheckNativeDashboardBounds(Form, Coordinator);
      Coordinator.OnDashboardRestore := Coordinator.DashboardRestored;
      Winapi.Windows.ShowWindow(AppHandle, SW_MINIMIZE);
      Winapi.Windows.ShowWindow(WindowHandle, SW_HIDE);
      SendMessage(AppHandle, WM_SYSCOMMAND, SC_RESTORE, 0);
      SendMessage(AppHandle, WM_SYSCOMMAND, SC_RESTORE, 0);
      Application.ProcessMessages;
      Check(Coordinator.RestoreCallbackCount = 1,
        Format('Taskbar restore must queue one dashboard callback without recursive duplicates (actual=%d)',
          [Coordinator.RestoreCallbackCount]));
      Check(not IsIconic(AppHandle) and IsWindowVisible(WindowHandle),
        'Taskbar restore callback must recover the hidden dashboard');
      CheckNativeDashboardBounds(Form, Coordinator);
      { Settings change FMX's border/style and can recreate the native handle. }
      Coordinator.SetCollectorOnly(True);
      Form.FormStyle := TFormStyle.Normal;
      Form.BorderStyle := TFmxFormBorderStyle.Sizeable;
      Coordinator.SetTaskbarVisible(False);
      CheckTaskbarStyle(FormToHWND(Form), False);
      Coordinator.SetCollectorOnly(False);
      Coordinator.PlaceDashboard(-1);
      Coordinator.RestoreWindowsDashboard;
      WindowHandle := FormToHWND(Form);
      CheckTaskbarStyle(AppHandle, False);
      CheckTaskbarStyle(WindowHandle, False);
      CheckNativeDashboardBounds(Form, Coordinator);
      Coordinator.SetTaskbarVisible(True);
      CheckTaskbarStyle(AppHandle, True);
      CheckTaskbarStyle(WindowHandle, True);
      Check(GetWindowLongPtr(AppHandle, GWL_EXSTYLE) and WS_EX_APPWINDOW <> 0,
        'Tray failure must restore the FMX application taskbar button');
      Coordinator.SetTaskbarVisible(False);
      Coordinator.SetCollectorOnly(True);
      Winapi.Windows.ShowWindow(WindowHandle, SW_HIDE);
      Coordinator.RestoreWindowsDashboard;
      Check(not IsWindowVisible(WindowHandle),
        'Explicit restore in collector mode must not reveal the dashboard');
    finally
      Coordinator.Free;
    end;
  finally
    Application.MainForm := PreviousMainForm;
    Form.Free;
  end;
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
    CheckDisplayWakeRetries(Form);
    CheckDisplayWakeCancellation(Form);
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
  CheckNativeDashboardRecovery;
end;

begin
  try
    Run;
    Writeln('PLATFORM_TESTS_OK: schedule, wake/release/resume, timed wake retries, power notifications, native recovery, monitor bounds, collector isolation');
  except
    on E: Exception do
    begin
      Writeln('COLLECTOR_PLATFORM_TESTS_FAILED: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
