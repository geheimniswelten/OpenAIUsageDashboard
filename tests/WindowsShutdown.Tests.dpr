program WindowsShutdownTests;

{$APPTYPE CONSOLE}
{$R '..\OpenAIUsageDashboard.res'}

uses
  System.SysUtils, System.Classes, Winapi.Windows, Winapi.Messages,
  FMX.Forms, Dashboard.WindowsShutdown in '..\Dashboard.WindowsShutdown.pas',
  Dashboard.Platform in '..\Dashboard.Platform.pas',
  Dashboard.Tray in '..\Dashboard.Tray.pas';

const
  ProbeMessage = WM_APP + $756;

type
  THelperProbe = class
  public
    Window: HWND;
    CancelCount: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure WindowProc(var Message: TMessage);
  end;

  TQueryResult = record
    Flags: LPARAM;
    Count, Rejected: Integer;
  end;
  PQueryResult = ^TQueryResult;

constructor THelperProbe.Create;
begin
  inherited;
  Window := AllocateHWnd(WindowProc);
end;

destructor THelperProbe.Destroy;
begin
  DeallocateHWnd(Window);
  inherited;
end;

procedure THelperProbe.WindowProc(var Message: TMessage);
begin
  case Message.Msg of
    WM_QUERYENDSESSION: Message.Result := 0;
    ProbeMessage: Message.Result := 12345;
    WM_ENDSESSION:
      begin
        if Message.WParam = 0 then Inc(CancelCount);
        Message.Result := 0;
      end;
  else
    Message.Result := DefWindowProc(Window, Message.Msg, Message.WParam, Message.LParam);
  end;
end;

procedure Check(Condition: Boolean; const Description: string);
begin
  if not Condition then raise Exception.Create(Description);
end;

function QueryWindow(Window: HWND; Context: LPARAM): BOOL; stdcall;
var
  Answer: DWORD_PTR;
  Data: PQueryResult;
begin
  Data := PQueryResult(Context);
  Inc(Data.Count);
  Answer := 0;
  // Address this test thread's windows only. Never broadcast or shut down Windows.
  if (SendMessageTimeout(Window, WM_QUERYENDSESSION, 0, Data.Flags,
    SMTO_ABORTIFHUNG or SMTO_BLOCK, 1000, @Answer) = 0) or (Answer = 0) then
    Inc(Data.Rejected);
  Result := True;
end;

function QueryOwnWindows(Flags: LPARAM): TQueryResult;
begin
  Result.Flags := Flags;
  Result.Count := 0;
  Result.Rejected := 0;
  EnumThreadWindows(GetCurrentThreadId, @QueryWindow, LPARAM(@Result));
end;

procedure Run;
const
  SessionFlags: array[0..4] of Cardinal =
    (0, ENDSESSION_LOGOFF, ENDSESSION_CLOSEAPP, ENDSESSION_CRITICAL,
     ENDSESSION_LOGOFF or ENDSESSION_CRITICAL);
var
  Probe: THelperProbe;
  Form: TForm;
  Coordinator: TPlatformCoordinator;
  Tray: TDashboardTray;
  Query: TQueryResult;
  Flags: Cardinal;
begin
  Application.Initialize;
  Query := QueryOwnWindows(0);
  Writeln('BASELINE: windows=', Query.Count, ' vetoes=', Query.Rejected);
  if SameText(ParamStr(1), '--without-guard') then
  begin
    Check(Query.Rejected = 0, 'Framework helper vetoes Windows shutdown');
    Exit;
  end;
  Probe := THelperProbe.Create;
  try
    InstallWindowsShutdownGuard;
    InstallWindowsShutdownGuard; // Duplicate installation must be harmless.
    Check(SendMessage(Probe.Window, ProbeMessage, 0, 0) = 12345,
      'Unrelated messages must reach the original procedure');
    Check(SendMessage(Probe.Window, WM_ENDSESSION, 0, 0) = 0,
      'Cancelled session must be handled normally');
    Check(Probe.CancelCount = 1, 'Cancelled session must reach the original handler once');
    Check(not Application.Terminated, 'A query or cancellation must not terminate the app');
    Form := TForm.CreateNew(nil);
    Coordinator := TPlatformCoordinator.Create(Form);
    Tray := TDashboardTray.Create(nil);
    try
      for Flags in SessionFlags do
      begin
        Query := QueryOwnWindows(LPARAM(Flags));
        Check(Query.Count > 3, 'Expected real framework and dashboard helper windows');
        Check(Query.Rejected = 0, 'A window still rejects a session-end query');
      end;
      Check(not Application.Terminated, 'Queries must leave the application running');
    finally
      Tray.Free;
      Coordinator.Free;
      Form.Free;
    end;
    if SameText(ParamStr(1), '--halt') then
    begin
      Writeln('SHUTDOWN_HALT_FINALIZATION');
      Halt(0); // Same finalization path used by FMX for confirmed WM_ENDSESSION.
    end;
    RemoveWindowsShutdownGuard;
    Check(SendMessage(Probe.Window, WM_QUERYENDSESSION, 0, 0) = 0,
      'Removing the guard must restore the original procedure');
    InstallWindowsShutdownGuard;
    Check(QueryOwnWindows(0).Rejected = 0, 'Reinstallation must work');
  finally
    RemoveWindowsShutdownGuard;
    Probe.Free;
  end;
end;

begin
  try
    Run;
    Writeln('WINDOWS_SHUTDOWN_OK');
  except
    on E: Exception do
    begin
      Writeln('WINDOWS_SHUTDOWN_FAILED: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
