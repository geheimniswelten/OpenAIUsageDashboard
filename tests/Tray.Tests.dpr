program TrayTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FMX.Forms,
  Winapi.Windows,
  Winapi.ShellAPI,
  Vcl.ExtCtrls,
  Dashboard.Tray in '..\Dashboard.Tray.pas';

type
  TTrayProbe = class(TTrayIcon)
  public
    procedure Diagnose;
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

procedure Run;
var
  Tray: TDashboardTray;
  Error: string;
begin
  FMX.Forms.Application.Initialize;
  if FindCmdLineSwitch('diagnose') then
    DiagnoseEnvironment;
  Tray := TDashboardTray.Create(nil);
  try
    Check(not Tray.Visible, 'Tray must start hidden');
    if FindCmdLineSwitch('expect-unavailable') then
    begin
      Check(not Tray.Show(Error), 'Expected unavailable Shell, but Show succeeded');
      Check(not Tray.Visible, 'Failed registration must remain invisible');
      Check(Error <> '', 'Failed registration must explain the problem');
      Tray.Hide;
      Writeln('TRAY_UNAVAILABLE_FALLBACK_OK');
      Exit;
    end;
    if not Tray.Show(Error) then
      raise Exception.Create('Show failed: ' + Error);
    Check(Tray.Visible, 'Tray registration did not become visible');
    Tray.UpdateStatus('Tray-Test');
    Tray.SetCollectorMode(True);
    FMX.Forms.Application.ProcessMessages;
    Tray.SetCollectorMode(False);
    Tray.Hide;
    Check(not Tray.Visible, 'Hide did not clear Visible');
    if not Tray.Show(Error) then
      raise Exception.Create('Second Show failed: ' + Error);
    Check(Tray.Visible, 'Second registration did not become visible');
    FMX.Forms.Application.ProcessMessages;
  finally
    // Free also deletes the second icon; no settings, API or secrets touched.
    Tray.Free;
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
