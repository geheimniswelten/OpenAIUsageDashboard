program TrayTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FMX.Forms,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.ShellAPI,
  Vcl.ExtCtrls,
  Dashboard.Tray in '..\Dashboard.Tray.pas';

type
  TTrayProbe = class(TTrayIcon)
  public
    procedure Diagnose;
  end;

  TActionProbe = class
  public
    Count: Integer;
    LastAction: TTrayAction;
    procedure Action(Sender: TObject; AAction: TTrayAction);
  end;

procedure TActionProbe.Action(Sender: TObject; AAction: TTrayAction);
begin
  Inc(Count);
  LastAction := AAction;
end;

procedure TTrayProbe.Diagnose;
var
  IconData: TNotifyIconData;
  Accepted: Boolean;
  ErrorCode: DWORD;
  SharedIcon: HICON;
begin
  SharedIcon := LoadIcon(0, IDI_APPLICATION);
  if SharedIcon <> 0 then
    Icon.Handle := CopyIcon(SharedIcon);
  Visible := True;
  IconData := Data;
  Writeln('VCL_DATA cbSize=', IconData.cbSize, ' expected=', TNotifyIconData.SizeOf,
    ' hwnd=', UIntToStr(IconData.Wnd), ' isWindow=', IsWindow(IconData.Wnd),
    ' icon=', UIntToStr(IconData.hIcon), ' flags=', IconData.uFlags);
  SetLastError(ERROR_SUCCESS);
  Accepted := Refresh(NIM_MODIFY);
  ErrorCode := GetLastError;
  Writeln('VCL_MODIFY accepted=', Accepted, ' error=', ErrorCode,
    ' hex=', IntToHex(ErrorCode, 8));
  try
    Visible := False;
  except
    on E: Exception do
      Writeln('VCL_HIDE: ', E.Message);
  end;
end;

procedure DiagnoseEnvironment;
var
  Buffer: array[0..511] of Char;
  Needed, Session: DWORD;
  Probe: TTrayProbe;
begin
  ProcessIdToSessionId(GetCurrentProcessId, Session);
  Writeln('SESSION=', Session, ' SHELL_TRAY_HWND=',
    UIntToStr(FindWindow('Shell_TrayWnd', nil)));
  if GetUserObjectInformation(GetProcessWindowStation, UOI_NAME, @Buffer[0],
    SizeOf(Buffer), Needed) then
    Writeln('WINDOW_STATION=', PChar(@Buffer[0]));
  if GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId), UOI_NAME,
    @Buffer[0], SizeOf(Buffer), Needed) then
    Writeln('DESKTOP=', PChar(@Buffer[0]));
  Probe := TTrayProbe.Create(nil);
  try
    Probe.Diagnose;
  finally
    Probe.Free;
  end;
end;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function FindOwnRegisteredIcon(AWindow: HWND; AContext: LPARAM): BOOL; stdcall;
var
  IconData: PNotifyIconData;
begin
  // VCL identifies each icon by its private window handle. Enumerate only this
  // test thread, so the simulated Shell loss cannot affect another process.
  IconData := PNotifyIconData(AContext);
  FillChar(IconData^, SizeOf(IconData^), 0);
  IconData^.cbSize := TNotifyIconData.SizeOf;
  IconData^.Wnd := AWindow;
  IconData^.uID := UINT(AWindow);
  Result := not Shell_NotifyIcon(NIM_MODIFY, IconData);
  if Result then
    IconData^.Wnd := 0;
end;

function OwnRegisteredIcon: TNotifyIconData;
begin
  FillChar(Result, SizeOf(Result), 0);
  EnumThreadWindows(GetCurrentThreadId, @FindOwnRegisteredIcon, LPARAM(@Result));
  Check(Result.Wnd <> 0, 'Could not find this test process''s registered tray icon');
end;

procedure CheckLostIconRecovery(const ATray: TDashboardTray);
var
  IconData: TNotifyIconData;
  Error: string;
  RecoveryCount: Cardinal;
begin
  RecoveryCount := ATray.RecoveryCount;
  IconData := OwnRegisteredIcon;
  Check(Shell_NotifyIcon(NIM_DELETE, @IconData), 'Could not simulate lost tray icon');
  Check(not Shell_NotifyIcon(NIM_MODIFY, @IconData), 'Deleted icon still registered');
  Check(ATray.Visible, 'Shell loss must leave the old cached state for this regression');
  Check(ATray.EnsureVisible(Error), 'EnsureVisible failed to recover lost icon: ' + Error);
  Check(ATray.Visible, 'Recovered icon must be marked visible');
  Check(ATray.RecoveryCount = RecoveryCount + 1, 'Lost icon repair must be counted');
  Check(Shell_NotifyIcon(NIM_MODIFY, @IconData), 'Recovered icon missing from Shell');
  Check(ATray.EnsureVisible(Error), 'Healthy icon verification failed: ' + Error);
  Check(ATray.RecoveryCount = RecoveryCount + 1, 'Healthy icon must not count as a repair');

  Check(Shell_NotifyIcon(NIM_DELETE, @IconData), 'Could not simulate second icon loss');
  Check(ATray.Show(Error), 'Repeated Show failed to recover lost icon: ' + Error);
  Check(ATray.RecoveryCount = RecoveryCount + 2, 'Repeated Show repair must be counted');
  Check(Shell_NotifyIcon(NIM_MODIFY, @IconData), 'Repeated Show did not re-add icon');

  // Exercise VCL's broadcast recovery without restarting Explorer or sending a
  // broadcast to unrelated applications.
  Check(Shell_NotifyIcon(NIM_DELETE, @IconData), 'Could not simulate Explorer icon loss');
  SendMessage(IconData.Wnd, RegisterWindowMessage('TaskbarCreated'), 0, 0);
  Check(ATray.EnsureVisible(Error), 'TaskbarCreated recovery verification failed: ' + Error);
  Check(Shell_NotifyIcon(NIM_MODIFY, @IconData), 'TaskbarCreated did not restore icon');
end;

procedure CheckDoubleClickToggle(const AProbe: TActionProbe);
var
  IconData: TNotifyIconData;
  I: Integer;
begin
  IconData := OwnRegisteredIcon;
  // Use the real VCL callback window and the Shell's mouse message sequence.
  SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_LBUTTONDOWN);
  SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_LBUTTONUP);
  FMX.Forms.Application.ProcessMessages;
  Check(AProbe.Count = 0, 'A single click must not consume the double-click toggle');
  for I := 1 to 2 do
  begin
    SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_LBUTTONDOWN);
    SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_LBUTTONUP);
    SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_LBUTTONDBLCLK);
    SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_LBUTTONUP);
    Check(AProbe.Count = I - 1, 'Toggle must be queued outside the VCL mouse callback');
    FMX.Forms.Application.ProcessMessages;
    Check(AProbe.Count = I, 'Each double-click must dispatch exactly one toggle');
    Check(AProbe.LastAction = taToggleDashboard, 'Double-click must request a dashboard toggle');
  end;
  SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_RBUTTONDBLCLK);
  SendMessage(IconData.Wnd, WM_SYSTEM_TRAY_MESSAGE, IconData.uID, WM_MBUTTONDBLCLK);
  FMX.Forms.Application.ProcessMessages;
  Check(AProbe.Count = 2, 'Other mouse buttons must not toggle the dashboard');
end;

procedure Run;
var
  Tray: TDashboardTray;
  Probe: TActionProbe;
  Error: string;
begin
  FMX.Forms.Application.Initialize;
  if FindCmdLineSwitch('diagnose') then
    DiagnoseEnvironment;
  Probe := TActionProbe.Create;
  Tray := TDashboardTray.Create(Probe.Action);
  try
    Check(not Tray.Visible, 'Tray must start hidden');
    Check(Tray.EnsureVisible(Error), 'Initial hidden state must need no registration');
    Check(not Tray.Visible, 'EnsureVisible must not show an intentionally hidden icon');
    if FindCmdLineSwitch('expect-unavailable') then
    begin
      Check(not Tray.Show(Error), 'Expected unavailable Shell, but Show succeeded');
      Check(not Tray.Visible, 'Failed registration must remain invisible');
      Check(Error <> '', 'Failed registration must explain the problem');
      Check(not Tray.EnsureVisible(Error), 'Unavailable Shell retry must fail safely');
      Check(not Tray.Visible, 'Failed retry must remain invisible');
      Check(Error <> '', 'Failed retry must explain the problem');
      Check(Tray.RecoveryCount = 0, 'Failed attempts must not count as successful repairs');
      Tray.Hide;
      Check(Tray.EnsureVisible(Error), 'Hide must cancel unavailable Shell retries');
      Check(Error = '', 'Intentionally hidden icon must not report a registration error');
      Writeln('TRAY_UNAVAILABLE_FALLBACK_OK');
      Exit;
    end;
    if not Tray.Show(Error) then
      raise Exception.Create('Show failed: ' + Error);
    Check(Tray.Visible, 'Tray registration did not become visible');
    Check(Tray.RecoveryCount = 0, 'Initial registration must not count as a repair');
    CheckLostIconRecovery(Tray);
    CheckDoubleClickToggle(Probe);
    Tray.UpdateStatus('Tray-Test');
    Tray.SetCollectorMode(True);
    FMX.Forms.Application.ProcessMessages;
    Tray.SetCollectorMode(False);
    Tray.Hide;
    Check(not Tray.Visible, 'Hide did not clear Visible');
    Check(Tray.EnsureVisible(Error), 'EnsureVisible must honor Hide');
    Check(not Tray.Visible, 'Recovery must not undo an intentional Hide');
    if not Tray.Show(Error) then
      raise Exception.Create('Second Show failed: ' + Error);
    Check(Tray.Visible, 'Second registration did not become visible');
    FMX.Forms.Application.ProcessMessages;
  finally
    // Free also deletes the second icon; no settings, API or secrets touched.
    Tray.Free;
    Probe.Free;
  end;
end;

begin
  try
    Run;
    if not FindCmdLineSwitch('expect-unavailable') then
      Writeln('TRAY_TEST_OK');
  except
    on E: Exception do
    begin
      Writeln('TRAY_TEST_FAILED: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
