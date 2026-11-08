unit Dashboard.WindowsShutdown;

interface

// Call once immediately after Application.Initialize, before creating forms.
// Only existing hidden RTL utility windows on this GUI thread are covered.
procedure InstallWindowsShutdownGuard;
procedure RemoveWindowsShutdownGuard;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.CommCtrl,
  // Keep this unit's finalization ahead of FMX's helper-window destruction.
  FMX.Forms,
  FMX.Platform.Win;

var
  GuardedWindows: TList<HWND>;
  InstallError: DWORD;
  ExitCleanupRegistered: Boolean;

function ShutdownHelperProc(AWindow: HWND; AMessage: UINT;
  AWParam: WPARAM; ALParam: LPARAM; ASubclassId: UINT_PTR;
  ARefData: DWORD_PTR): LRESULT; stdcall;
begin
  // Delphi 13's TWinSystemAppearanceService dispatches this message to
  // TObject.DefaultHandler, returning zero instead of DefWindowProc's TRUE.
  // These background helpers own no editable data and must not veto shutdown.
  if AMessage = WM_QUERYENDSESSION then
    Exit(1);
  if AMessage = WM_NCDESTROY then
  begin
    RemoveWindowSubclass(AWindow, ShutdownHelperProc, ASubclassId);
    if GuardedWindows <> nil then
      GuardedWindows.Remove(AWindow);
  end;
  // Includes WM_SETTINGCHANGE and a cancelled WM_ENDSESSION (wParam = 0).
  Result := DefSubclassProc(AWindow, AMessage, AWParam, ALParam);
end;

function GuardUtilityWindow(AWindow: HWND; AContext: LPARAM): BOOL; stdcall;
var
  ClassName: array[0..63] of Char;
  ProcessId: DWORD;
begin
  Result := True;
  if (GetWindowThreadProcessId(AWindow, @ProcessId) <> GetCurrentThreadId) or
     (ProcessId <> GetCurrentProcessId) or IsWindowVisible(AWindow) then
    Exit;
  if (GetClassName(AWindow, ClassName, Length(ClassName)) = 0) or
     (string(ClassName) <> 'TPUtilWindow') then
    Exit;
  if SetWindowSubclass(AWindow, ShutdownHelperProc,
    UINT_PTR(@ShutdownHelperProc), 0) then
    GuardedWindows.Add(AWindow)
  else
  begin
    InstallError := GetLastError;
    if InstallError = ERROR_SUCCESS then
      InstallError := ERROR_INVALID_FUNCTION;
    Result := False;
  end;
end;

procedure InstallWindowsShutdownGuard;
var
  Controls: TInitCommonControlsEx;
begin
  if GuardedWindows <> nil then
    Exit;
  // Halt runs exit procedures before unit finalization. FMX can destroy its
  // utility windows during that finalization, so restore their original WndProcs
  // here rather than relying on the relative order of FMX's cyclic units.
  if not ExitCleanupRegistered then
  begin
    AddExitProc(RemoveWindowsShutdownGuard);
    ExitCleanupRegistered := True;
  end;
  // Force the delayed COMCTL32 import before the RTL resolves subclass APIs.
  InitCommonControls;
  Controls.dwSize := SizeOf(Controls);
  Controls.dwICC := ICC_WIN95_CLASSES;
  if not InitCommonControlsEx(Controls) then
    raise EOSError.CreateFmt('InitCommonControlsEx failed (%d)', [GetLastError]);
  GuardedWindows := TList<HWND>.Create;
  try
    InstallError := ERROR_SUCCESS;
    EnumThreadWindows(GetCurrentThreadId, @GuardUtilityWindow, 0);
    if InstallError <> ERROR_SUCCESS then
      raise EOSError.CreateFmt('Shutdown helper subclass failed (%d)', [InstallError]);
  except
    RemoveWindowsShutdownGuard;
    raise;
  end;
end;

procedure RemoveWindowsShutdownGuard;
var
  Window: HWND;
begin
  if GuardedWindows = nil then
    Exit;
  for Window in GuardedWindows do
    RemoveWindowSubclass(Window, ShutdownHelperProc, UINT_PTR(@ShutdownHelperProc));
  FreeAndNil(GuardedWindows);
end;

initialization

finalization
  // AllocateHWnd/DeallocateHWnd must see their original window procedures.
  // Also runs when FMX ends the session with Halt instead of normal form cleanup.
  RemoveWindowsShutdownGuard;

end.
