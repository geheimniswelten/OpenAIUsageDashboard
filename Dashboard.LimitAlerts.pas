unit Dashboard.LimitAlerts;

interface

uses
  System.Generics.Collections, Dashboard.Model;

type
  TLimitWarning = record
    Limit: TRateLimitWindow;
    Threshold: Integer;
    Remaining: Double;
  end;

  { UI-thread policy. Delivery is acknowledged separately: inactivity or a
    failed popup must not consume a threshold. No account requests here. }
  TLimitAlertTracker = class
  private type
    TState = record
      ResetAt: TDateTime;
      Minutes: Integer;
      LowestDelivered: Integer;
      PreviousUsed: Double;
    end;
  private
    FStates: TDictionary<string, TState>;
    FLimits: TArray<TRateLimitWindow>;
    FObservedTick: UInt64;
    FAvailable: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Observe(const ALimits: TArray<TRateLimitWindow>;
      AAvailable: Boolean; ATick: UInt64);
    procedure Invalidate;
    function Pending(ATick, AMaxAgeMs: UInt64; ANow: TDateTime): TArray<TLimitWarning>;
    procedure Delivered(const AWarning: TLimitWarning);
  end;

implementation

uses System.SysUtils, System.Math;

function ValidLimit(const L: TRateLimitWindow): Boolean;
begin
  Result := L.Available and (L.Id <> '') and
    not IsNan(L.UsedPercent) and not IsInfinite(L.UsedPercent) and
    (L.UsedPercent >= 0) and (L.UsedPercent <= 100);
end;

function ThresholdFor(ARemaining: Double): Integer;
begin
  if ARemaining > 20 then Result := 101
  else if ARemaining > 10 then Result := 20
  else Result := Ceil(ARemaining); { Includes one final exhausted/0% warning. }
end;

constructor TLimitAlertTracker.Create;
begin
  inherited;
  FStates := TDictionary<string, TState>.Create;
end;

destructor TLimitAlertTracker.Destroy;
begin
  FStates.Free;
  inherited;
end;

procedure TLimitAlertTracker.Invalidate;
begin
  FAvailable := False;
  FLimits := nil;
end;

procedure TLimitAlertTracker.Observe(const ALimits: TArray<TRateLimitWindow>;
  AAvailable: Boolean; ATick: UInt64);
var
  L: TRateLimitWindow;
  S: TState;
begin
  Invalidate;
  if not AAvailable then Exit;
  FLimits := Copy(ALimits);
  FAvailable := True;
  FObservedTick := ATick;
  for L in FLimits do
    if ValidLimit(L) then
    begin
      if not FStates.TryGetValue(L.Id, S) then
      begin
        S := Default(TState);
        S.LowestDelivered := 101;
      end
      else if ((S.ResetAt > 0) and (L.ResetsAt > 0) and
          (Abs(S.ResetAt - L.ResetsAt) > 1 / 86400)) or
          (S.Minutes <> L.WindowMinutes) or
          (S.PreviousUsed - L.UsedPercent >= 20) then
        S.LowestDelivered := 101;
      S.ResetAt := L.ResetsAt;
      S.Minutes := L.WindowMinutes;
      S.PreviousUsed := L.UsedPercent;
      FStates.AddOrSetValue(L.Id, S);
    end;
end;

function TLimitAlertTracker.Pending(ATick, AMaxAgeMs: UInt64;
  ANow: TDateTime): TArray<TLimitWarning>;
var
  L: TRateLimitWindow;
  S: TState;
  W: TLimitWarning;
begin
  Result := nil;
  if not FAvailable or (ATick < FObservedTick) or
    (ATick - FObservedTick > AMaxAgeMs) then Exit;
  for L in FLimits do
    if ValidLimit(L) and ((L.ResetsAt = 0) or (L.ResetsAt > ANow)) and
      FStates.TryGetValue(L.Id, S) then
    begin
      W.Remaining := 100 - L.UsedPercent;
      W.Threshold := ThresholdFor(W.Remaining);
      if W.Threshold < S.LowestDelivered then
      begin
        W.Limit := L;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := W;
      end;
    end;
end;

procedure TLimitAlertTracker.Delivered(const AWarning: TLimitWarning);
var S: TState;
begin
  if FStates.TryGetValue(AWarning.Limit.Id, S) and
    (S.ResetAt = AWarning.Limit.ResetsAt) and
    (S.Minutes = AWarning.Limit.WindowMinutes) then
  begin
    S.LowestDelivered := Min(S.LowestDelivered, AWarning.Threshold);
    FStates.AddOrSetValue(AWarning.Limit.Id, S);
  end;
end;

end.
