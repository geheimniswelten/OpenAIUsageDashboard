unit Dashboard.DisplayPolicy;

interface

type
  { A transient fallback must never replace the requested monitor. Windows can
    reorder monitor indices and HMONITOR handles when a display reconnects. }
  TDashboardDisplayPreference = record
  private
    FRequestedIndex: Integer;
    FPreferredDevice: string;
  public
    constructor Create(const ARequestedIndex: Integer);
    function Resolve(const ADevices: TArray<string>;
      const APrimaryIndex: Integer): Integer;
  end;

function InKeepAwakeWindow(const ATime: TDateTime;
  const AStartHour, AEndHour: Integer): Boolean;

implementation

uses
  System.SysUtils,
  System.DateUtils;

function InKeepAwakeWindow(const ATime: TDateTime;
  const AStartHour, AEndHour: Integer): Boolean;
begin
  Result := (DayOfTheWeek(ATime) <= 5) and
    (HourOf(ATime) >= AStartHour) and (HourOf(ATime) < AEndHour);
end;

constructor TDashboardDisplayPreference.Create(const ARequestedIndex: Integer);
begin
  FRequestedIndex := ARequestedIndex;
  FPreferredDevice := '';
end;

function TDashboardDisplayPreference.Resolve(const ADevices: TArray<string>;
  const APrimaryIndex: Integer): Integer;
var
  I, PrimaryIndex: Integer;
begin
  Result := -1;
  if Length(ADevices) = 0 then
    Exit;
  PrimaryIndex := APrimaryIndex;
  if (PrimaryIndex < 0) or (PrimaryIndex >= Length(ADevices)) then
    PrimaryIndex := 0;
  if FPreferredDevice <> '' then
    for I := 0 to High(ADevices) do
      if SameText(ADevices[I], FPreferredDevice) then
        Exit(I);

  if (FPreferredDevice = '') and (FRequestedIndex >= 0) and
     (FRequestedIndex < Length(ADevices)) then
  begin
    Result := FRequestedIndex;
    FPreferredDevice := ADevices[Result];
    Exit;
  end;

  Result := PrimaryIndex;
  for I := 0 to High(ADevices) do
    if I <> PrimaryIndex then
    begin
      Result := I;
      Break;
    end;
  { Auto mode learns an external display when one first becomes available.
    Neither a missing explicit choice nor a missing device is overwritten. }
  if (FPreferredDevice = '') and (FRequestedIndex < 0) and
     (Result <> PrimaryIndex) then
    FPreferredDevice := ADevices[Result];
end;

end.
