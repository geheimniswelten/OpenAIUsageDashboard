unit Dashboard.LimitNotifications;

interface

uses
  System.Classes, System.Types, Winapi.Windows, Winapi.Messages,
  Winapi.CommCtrl, Winapi.MultiMon, Dashboard.Model, Dashboard.LimitAlerts;

type
  TLimitNotifications = class
  private
    FTracker: TLimitAlertTracker;
    FOwner, FTooltip: HWND;
    FTool: TToolInfo;
    FText: string;
    FVisibleUntil: UInt64;
    FNextAttempt: UInt64;
    procedure WindowProc(var AMessage: TMessage);
    function EnsureTooltip: Boolean;
  protected
    function CurrentTick: UInt64; virtual;
    function UserActive(ADisplayState: Integer): Boolean; virtual;
    function ShowWarning(const AWarning: TLimitWarning): Boolean; virtual;
    procedure PlaySound; virtual;
    property TooltipHandle: HWND read FTooltip;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Observe(const ASnapshot: TUsageSnapshot; ASuccess: Boolean);
    procedure Invalidate;
    procedure Hide;
    procedure Tick(ABackground: Boolean; ADisplayState, ARefreshSeconds: Integer);
    class function ClampOrigin(const AWork: TRect; const ASize: TSize;
      const ADesired: TPoint): TPoint; static;
  end;

implementation

uses System.SysUtils, System.Math;

{ Keep the Win32 declarations local; no dependency on a particular SDK's
  WTS Pascal unit. WTSConnectState = 8, WTSActive = 0. }
function QuerySession(hServer: THandle; SessionId: DWORD; InfoClass: Integer;
  var Buffer: Pointer; var BytesReturned: DWORD): BOOL; stdcall;
  external 'wtsapi32.dll' name 'WTSQuerySessionInformationW';
procedure FreeSessionMemory(Buffer: Pointer); stdcall;
  external 'wtsapi32.dll' name 'WTSFreeMemory';

constructor TLimitNotifications.Create;
begin
  inherited;
  FTracker := TLimitAlertTracker.Create;
  FOwner := AllocateHWnd(WindowProc);
end;

destructor TLimitNotifications.Destroy;
begin
  Hide;
  if FTooltip <> 0 then DestroyWindow(FTooltip);
  if FOwner <> 0 then DeallocateHWnd(FOwner);
  FTracker.Free;
  inherited;
end;

procedure TLimitNotifications.WindowProc(var AMessage: TMessage);
begin
  AMessage.Result := DefWindowProc(FOwner, AMessage.Msg, AMessage.WParam, AMessage.LParam);
end;

function TLimitNotifications.CurrentTick: UInt64;
begin
  Result := GetTickCount64;
end;

function TLimitNotifications.UserActive(ADisplayState: Integer): Boolean;
var
  Input: TLastInputInfo;
  Desktop: HDESK;
  InputName, ThreadName: array[0..255] of Char;
  Needed, Bytes: DWORD;
  Buffer: Pointer;
begin
  Result := False;
  if ADisplayState in [0, 2] then Exit;
  Input.cbSize := SizeOf(Input);
  if not GetLastInputInfo(Input) then Exit;
  if ((UInt64(GetTickCount) + UInt64($100000000) - UInt64(Input.dwTime)) and UInt64($FFFFFFFF)) > 120000 then Exit;
  Buffer := nil;
  if not QuerySession(0, DWORD(-1), 8, Buffer, Bytes) then Exit;
  try
    if (Buffer = nil) or (Bytes < SizeOf(Integer)) then Exit;
    if PInteger(Buffer)^ <> 0 then Exit;
  finally
    FreeSessionMemory(Buffer);
  end;
  Desktop := OpenInputDesktop(0, False, DESKTOP_READOBJECTS);
  if Desktop = 0 then Exit;
  try
    if not GetUserObjectInformation(Desktop, UOI_NAME, @InputName,
      SizeOf(InputName), Needed) then Exit;
    if not GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId),
      UOI_NAME, @ThreadName, SizeOf(ThreadName), Needed) then Exit;
    Result := SameText(InputName, ThreadName);
  finally
    CloseDesktop(Desktop);
  end;
end;

function TLimitNotifications.EnsureTooltip: Boolean;
begin
  if FTooltip = 0 then
  begin
    InitCommonControls;
    FTooltip := CreateWindowEx(WS_EX_TOPMOST or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW,
      TOOLTIPS_CLASS, nil, WS_POPUP or TTS_NOPREFIX or TTS_ALWAYSTIP or
      TTS_BALLOON or TTS_NOANIMATE or TTS_NOFADE,
      CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
      FOwner, 0, HInstance, nil);
    if FTooltip = 0 then Exit(False);
    FTool := Default(TToolInfo);
    { V2 layout also works without a Common Controls v6 manifest. }
    FTool.cbSize := NativeUInt(@FTool.lpReserved) - NativeUInt(@FTool);
    FTool.uFlags := TTF_TRACK or TTF_ABSOLUTE;
    FTool.hwnd := FOwner;
    FTool.uId := 1;
    FTool.lpszText := PChar(' ');
    if SendMessage(FTooltip, TTM_ADDTOOL, 0, LPARAM(@FTool)) = 0 then
    begin
      DestroyWindow(FTooltip);
      FTooltip := 0;
    end;
  end;
  Result := FTooltip <> 0;
end;

class function TLimitNotifications.ClampOrigin(const AWork: TRect;
  const ASize: TSize; const ADesired: TPoint): TPoint;
begin
  Result.X := EnsureRange(ADesired.X, AWork.Left, Max(AWork.Left, AWork.Right - ASize.cx));
  Result.Y := EnsureRange(ADesired.Y, AWork.Top, Max(AWork.Top, AWork.Bottom - ASize.cy));
end;

function TLimitNotifications.ShowWarning(const AWarning: TLimitWarning): Boolean;
var
  Cursor, Origin: TPoint;
  Monitor: TMonitorInfo;
  Bounds: TRect;
  WindowLabel: string;
begin
  Result := False;
  if not GetCursorPos(Cursor) then Exit;
  Monitor.cbSize := SizeOf(Monitor);
  if not GetMonitorInfo(MonitorFromPoint(Cursor, MONITOR_DEFAULTTONEAREST), @Monitor) then Exit;
  if not EnsureTooltip then Exit;
  WindowLabel := AWarning.Limit.WindowName;
  if WindowLabel = '' then WindowLabel := IntToStr(AWarning.Limit.WindowMinutes) + ' Minuten';
  FText := AWarning.Limit.Name + ' · ' + WindowLabel + sLineBreak +
    'Noch ' + FormatFloat('0.##', AWarning.Remaining) + ' % verfügbar';
  if AWarning.Limit.ResetsAt > 0 then
    FText := FText + sLineBreak + 'Zurücksetzung: ' +
      FormatDateTime('dd.mm. hh:nn', AWarning.Limit.ResetsAt);
  FTool.lpszText := PChar(FText);
  SendMessage(FTooltip, TTM_UPDATETIPTEXT, 0, LPARAM(@FTool));
  SendMessage(FTooltip, TTM_SETTITLE, TTI_WARNING, LPARAM(PChar('Codex-Limit')));
  SendMessage(FTooltip, TTM_SETMAXTIPWIDTH, 0, Min(420, Monitor.rcWork.Width - 32));
  Origin := ClampOrigin(Monitor.rcWork, TSize.Create(1, 1), Point(Cursor.X + 16, Cursor.Y + 24));
  SendMessage(FTooltip, TTM_TRACKPOSITION, 0,
    LPARAM((Cardinal(Origin.X) and $FFFF) or ((Cardinal(Origin.Y) and $FFFF) shl 16)));
  SendMessage(FTooltip, TTM_TRACKACTIVATE, 1, LPARAM(@FTool));
  if GetWindowRect(FTooltip, Bounds) then
  begin
    Origin := ClampOrigin(Monitor.rcWork, TSize.Create(Bounds.Width, Bounds.Height), Origin);
    SetWindowPos(FTooltip, HWND_TOPMOST, Origin.X, Origin.Y, 0, 0,
      SWP_NOSIZE or SWP_NOACTIVATE or SWP_SHOWWINDOW);
  end;
  Result := IsWindowVisible(FTooltip);
end;

procedure TLimitNotifications.PlaySound;
begin
  MessageBeep(MB_ICONEXCLAMATION);
end;

procedure TLimitNotifications.Hide;
begin
  if FTooltip <> 0 then
    SendMessage(FTooltip, TTM_TRACKACTIVATE, 0, LPARAM(@FTool));
  FVisibleUntil := 0;
end;

procedure TLimitNotifications.Invalidate;
begin
  FTracker.Invalidate;
  Hide;
end;

procedure TLimitNotifications.Observe(const ASnapshot: TUsageSnapshot; ASuccess: Boolean);
begin
  if not ASuccess or not ASnapshot.CodexRateLimitsAvailable then
    Invalidate
  else
    FTracker.Observe(ASnapshot.RateLimits, True, CurrentTick);
end;

procedure TLimitNotifications.Tick(ABackground: Boolean;
  ADisplayState, ARefreshSeconds: Integer);
var
  Warnings: TArray<TLimitWarning>;
  TickNow: UInt64;
begin
  TickNow := CurrentTick;
  if (FVisibleUntil <> 0) and (TickNow >= FVisibleUntil) then Hide;
  if not ABackground then
  begin
    Hide;
    Exit;
  end;
  Warnings := FTracker.Pending(TickNow, UInt64(Max(120, ARefreshSeconds * 2)) * 1000, Now);
  if (Length(Warnings) = 0) and (FVisibleUntil = 0) then Exit;
  if not UserActive(ADisplayState) then
  begin
    Hide;
    Exit;
  end;
  if (FVisibleUntil <> 0) or (TickNow < FNextAttempt) or (Length(Warnings) = 0) then Exit;
  FNextAttempt := TickNow + 10000;
  { One window per balloon, others remain pending. Refetch current values
    when the next balloon is due instead of queueing obsolete messages. }
  if ShowWarning(Warnings[0]) then
  begin
    FTracker.Delivered(Warnings[0]);
    FVisibleUntil := TickNow + 7000;
    PlaySound;
  end;
end;

end.
