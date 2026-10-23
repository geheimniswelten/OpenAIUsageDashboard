program LimitAlertsTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Types, System.Math, System.DateUtils,
  Winapi.Windows, Winapi.MultiMon,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.LimitAlerts in '..\Dashboard.LimitAlerts.pas',
  Dashboard.LimitNotifications in '..\Dashboard.LimitNotifications.pas';

type
  TMockNotifications = class(TLimitNotifications)
  public
    Clock: UInt64;
    Active, Succeeds: Boolean;
    Shows, Sounds: Integer;
    LastThreshold: Integer;
    function CurrentTick: UInt64; override;
    function UserActive(ADisplayState: Integer): Boolean; override;
    function ShowWarning(const AWarning: TLimitWarning): Boolean; override;
    procedure PlaySound; override;
  end;
  TNativeProbe = class(TLimitNotifications)
  public
    function ShowTest: Boolean;
    function ActiveOn(AState: Integer): Boolean;
    function Handle: HWND;
  end;

var Checks: Integer;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
  Inc(Checks);
end;

function MakeLimit(ARemaining: Double; const AId: string = 'codex:primary'): TRateLimitWindow;
begin
  Result := Default(TRateLimitWindow);
  Result.Id := AId;
  Result.Name := 'codex';
  Result.WindowName := '7 Tage';
  Result.UsedPercent := 100 - ARemaining;
  Result.WindowMinutes := 10080;
  Result.ResetsAt := Now + 3;
  Result.Available := True;
end;

function TMockNotifications.CurrentTick: UInt64;
begin Result := Clock; end;
function TMockNotifications.UserActive(ADisplayState: Integer): Boolean;
begin Result := Active; end;
function TMockNotifications.ShowWarning(const AWarning: TLimitWarning): Boolean;
begin
  Inc(Shows);
  LastThreshold := AWarning.Threshold;
  Result := Succeeds;
end;
procedure TMockNotifications.PlaySound;
begin Inc(Sounds); end;
function TNativeProbe.ShowTest: Boolean;
var W: TLimitWarning;
begin
  W := Default(TLimitWarning);
  W.Limit := MakeLimit(8);
  W.Remaining := 8;
  W.Threshold := 8;
  Result := ShowWarning(W);
end;
function TNativeProbe.ActiveOn(AState: Integer): Boolean;
begin Result := UserActive(AState); end;
function TNativeProbe.Handle: HWND;
begin Result := TooltipHandle; end;

procedure PolicyTests;
var
  P: TLimitAlertTracker;
  L, L2: TRateLimitWindow;
  W: TArray<TLimitWarning>;
  I: Integer;
begin
  P := TLimitAlertTracker.Create;
  try
    L := MakeLimit(21);
    P.Observe([L], True, 100);
    Check(Length(P.Pending(100, 600000, Now)) = 0, '21% must be silent');
    L.UsedPercent := 80;
    P.Observe([L], True, 200);
    W := P.Pending(200, 600000, Now);
    Check((Length(W) = 1) and (W[0].Threshold = 20), '20% warning');
    Check(Length(P.Pending(300, 600000, Now)) = 1, 'undelivered warning retained');
    P.Delivered(W[0]);
    P.Observe([L], True, 400);
    Check(Length(P.Pending(400, 600000, Now)) = 0, 'repeated refresh must not repeat');
    L.UsedPercent := 79.9;
    P.Observe([L], True, 500);
    L.UsedPercent := 80;
    P.Observe([L], True, 600);
    Check(Length(P.Pending(600, 600000, Now)) = 0, 'rounding jitter must not rearm');
    L.UsedPercent := 89.99;
    P.Observe([L], True, 700);
    Check(Length(P.Pending(700, 600000, Now)) = 0, '10.01% not yet 10%');
    for I := 10 downto 0 do
    begin
      L.UsedPercent := 100 - I;
      P.Observe([L], True, 800);
      W := P.Pending(800, 600000, Now);
      Check((Length(W) = 1) and (W[0].Threshold = I), 'single-digit threshold ' + IntToStr(I));
      P.Delivered(W[0]);
      Check(Length(P.Pending(800, 600000, Now)) = 0, 'single digit duplicate');
    end;
    L.ResetsAt := L.ResetsAt + 7;
    L.UsedPercent := 92;
    P.Observe([L], True, 900);
    W := P.Pending(900, 600000, Now);
    Check((Length(W) = 1) and (W[0].Threshold = 8), 'new period/jump gives only current 8%');
    P.Delivered(W[0]);
    L.UsedPercent := 0;
    P.Observe([L], True, 1000);
    L.UsedPercent := 80;
    P.Observe([L], True, 1100);
    W := P.Pending(1100, 600000, Now);
    Check(Length(W) = 1, 'manual reset without deadline change rearms');
    P.Delivered(W[0]);
    L2 := MakeLimit(9, 'codex:secondary');
    L2.WindowMinutes := 300;
    P.Observe([L, L2], True, 1200);
    W := P.Pending(1200, 600000, Now);
    Check((Length(W) = 1) and (W[0].Limit.Id = L2.Id), 'windows tracked independently');
    Check(Length(P.Pending(601201, 600000, Now)) = 0, 'stale snapshot silent');
    P.Observe([L2], False, 1300);
    Check(Length(P.Pending(1300, 600000, Now)) = 0, 'missing data silent');
    L2.Available := False;
    P.Observe([L2], True, 1400);
    Check(Length(P.Pending(1400, 600000, Now)) = 0, 'null window silent');
    L2.Available := True;
    L2.UsedPercent := NaN;
    P.Observe([L2], True, 1500);
    Check(Length(P.Pending(1500, 600000, Now)) = 0, 'NaN silent');
    L2.UsedPercent := 101;
    P.Observe([L2], True, 1600);
    Check(Length(P.Pending(1600, 600000, Now)) = 0, 'invalid percent silent');
    L2.UsedPercent := 99;
    L2.ResetsAt := Now - 1;
    P.Observe([L2], True, 1700);
    Check(Length(P.Pending(1700, 600000, Now)) = 0, 'expired period silent');
  finally P.Free; end;
end;

procedure DeliveryTests;
var N: TMockNotifications; S: TUsageSnapshot;
begin
  S := TUsageSnapshot.Create;
  N := TMockNotifications.Create;
  try
    N.Clock := 1000;
    S.CodexRateLimitsAvailable := True;
    S.RateLimits := [MakeLimit(8)];
    N.Observe(S, True);
    N.Tick(True, 1, 300);
    Check(N.Shows = 0, 'inactive user silent');
    N.Active := True;
    N.Tick(False, 1, 300);
    Check(N.Shows = 0, 'visible dashboard silent');
    N.Tick(True, 1, 300);
    Check((N.Shows = 1) and (N.Sounds = 0), 'failed balloon has no beep');
    N.Clock := 12000;
    N.Succeeds := True;
    N.Tick(True, 1, 300);
    Check((N.Shows = 2) and (N.Sounds = 1) and (N.LastThreshold = 8), 'failed delivery retried');
    N.Clock := 25000;
    N.Tick(True, 1, 300);
    Check(N.Sounds = 1, 'no repeated beep after timeout');
    S.RateLimits[0].UsedPercent := 93;
    N.Observe(S, True);
    N.Tick(True, 1, 300);
    Check((N.Sounds = 2) and (N.LastThreshold = 7), 'next threshold delivered');
    N.Clock := 40000;
    S.RateLimits[0].UsedPercent := 94;
    N.Observe(S, False);
    N.Tick(True, 1, 300);
    Check(N.Sounds = 2, 'failed refresh silent');
    N.Observe(S, True);
    N.Invalidate;
    N.Tick(True, 1, 300);
    Check(N.Sounds = 2, 'demo mode silent');
    N.Observe(S, True);
    N.Clock := N.Clock + 600001;
    N.Tick(True, 1, 300);
    Check(N.Sounds = 2, 'old pending warning silent');
  finally N.Free; S.Free; end;
end;

procedure NativeTests;
var
  N: TNativeProbe;
  Before: HWND;
  R: TRect;
  M: TMonitorInfo;
  P: TPoint;
begin
  P := TLimitNotifications.ClampOrigin(Rect(-1920, -1080, 0, 0),
    TSize.Create(400, 120), Point(-20, -20));
  Check((P.X = -400) and (P.Y = -120), 'negative monitor/right-bottom edge');
  P := TLimitNotifications.ClampOrigin(Rect(1920, 0, 3840, 1040),
    TSize.Create(400, 120), Point(1900, -20));
  Check((P.X = 1920) and (P.Y = 0), 'second monitor/left-top edge');
  N := TNativeProbe.Create;
  try
    Check(not N.ActiveOn(0), 'screen off silent');
    Check(not N.ActiveOn(2), 'screen dimmed silent');
    Before := GetForegroundWindow;
    GetCursorPos(P);
    M.cbSize := SizeOf(M);
    Check(GetMonitorInfo(MonitorFromPoint(P, MONITOR_DEFAULTTONEAREST), @M), 'mouse monitor exists');
    Check(N.ShowTest, 'native balloon visible');
    Check(GetForegroundWindow = Before, 'balloon must not steal focus');
    Check(GetWindowRect(N.Handle, R), 'native balloon rectangle');
    Check((R.Left >= M.rcWork.Left) and (R.Top >= M.rcWork.Top) and
      (R.Right <= M.rcWork.Right) and (R.Bottom <= M.rcWork.Bottom), 'balloon inside mouse monitor work area');
    N.Hide;
    Check(not IsWindowVisible(N.Handle), 'native balloon hides');
  finally N.Free; end;
end;

begin
  try
    PolicyTests;
    DeliveryTests;
    NativeTests;
    Writeln('PASS: ', Checks, ' limit notification checks (no sound, no API requests).');
  except
    on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end;
  end;
end.
