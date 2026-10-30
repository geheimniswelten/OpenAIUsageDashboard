program ServiceOrderTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dashboard.Model in '..\Dashboard.Model.pas';

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure Run;
var
  Snapshot, RoundTrip: TUsageSnapshot;
  Sorted: TArray<TServiceUsage>;
  I: Integer;

  procedure SetService(const AIndex: Integer; const AName, AUnit: string;
    const AValue: Double; const ARequests: Int64; const AAvailable: Boolean);
  begin
    Snapshot.Services[AIndex].Name := AName;
    Snapshot.Services[AIndex].UnitText := AUnit;
    Snapshot.Services[AIndex].Value := AValue;
    Snapshot.Services[AIndex].Requests := ARequests;
    Snapshot.Services[AIndex].Available := AAvailable;
  end;

begin
  Snapshot := TUsageSnapshot.Create;
  RoundTrip := TUsageSnapshot.Create;
  try
    Check(Length(Snapshot.GetServicesByUsage) = 0, 'Empty input must stay empty');
    SetLength(Snapshot.Services, 9);
    SetService(0, 'unknown', 'Tokens', 900000, High(Int64), False);
    SetService(1, 'zero-first', '', 0, 0, True);
    SetService(2, 'storage', 'B', 1E12, 0, True);
    SetService(3, 'web', '', 6, 6, True);
    SetService(4, 'embedding', 'Tokens', 779000, 61, True);
    SetService(5, 'zero-second', 'Sek.', 0, 0, True);
    SetService(6, 'request-only', '', 0, High(Int64), True);
    SetService(7, 'seconds', 'Sek.', 30, 6, True);
    SetService(8, 'unknown-last', '', 0, 0, False);
    Sorted := Snapshot.GetServicesByUsage;
    Check(Length(Sorted) = 9, 'Sorting must not discard hidden cards');
    Check(Sorted[0].Name = 'request-only', 'Request-only use and Int64 counts');
    Check(Sorted[1].Name = 'embedding', 'Descending request counts');
    Check(Sorted[2].Name = 'web', 'Stable ties across incomparable units');
    Check(Sorted[3].Name = 'seconds', 'Stable ties across incomparable units');
    Check(Sorted[4].Name = 'storage', 'Positive storage with no requests precedes zero use');
    Check(Sorted[5].Name = 'zero-first', 'Known zero precedes missing data');
    Check(Sorted[6].Name = 'zero-second', 'Stable zero ordering');
    Check(Sorted[7].Name = 'unknown', 'Unavailable values must never rank as use');
    Check(Sorted[8].Name = 'unknown-last', 'Stable unavailable ordering');
    Check(Snapshot.Services[0].Name = 'unknown', 'Snapshot must not be reordered');
    Sorted[0].Name := 'changed copy';
    Check(Snapshot.Services[6].Name = 'request-only', 'Returned array must be independent');
    RoundTrip.FromJson(Snapshot.ToJson);
    Sorted := RoundTrip.GetServicesByUsage;
    Check(Length(Sorted) = 9, 'Viewer round-trip must retain every service');
    Check(Sorted[0].Name = 'request-only', 'Viewer must use the same ordering');
    for I := 0 to High(Snapshot.Services) do
      Check(RoundTrip.Services[I].Name = Snapshot.Services[I].Name,
        'Wire order must remain unchanged');
    Writeln('SERVICE_ORDER_OK');
  finally
    RoundTrip.Free;
    Snapshot.Free;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
