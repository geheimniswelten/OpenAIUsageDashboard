program DashboardTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  System.DateUtils,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.Transport in '..\Dashboard.Transport.pas';

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

var
  Source, CopySnapshot, Remote, FullDays, SparseDays: TUsageSnapshot;
  Json, ErrorText: string;
  RateBefore: Double;
  Publisher: TSnapshotPublisher;
begin
  Source := TUsageSnapshot.Create;
  CopySnapshot := TUsageSnapshot.Create;
  Remote := TUsageSnapshot.Create;
  FullDays := TUsageSnapshot.Create;
  SparseDays := TUsageSnapshot.Create;
  Publisher := nil;
  try
    Source.MakeDemo;
    Check(Length(Source.DailyCosts) = 30, 'Demo-Tageswerte fehlen.');
    Check(Length(Source.Forecast) = 4, 'Vier Prognosewochen erwartet.');
    RateBefore := Source.ForecastDailyRate;
    Source.DailyCosts[High(Source.DailyCosts)].Amount := 9999;
    Source.Recalculate;
    Check(SameValue(RateBefore, Source.ForecastDailyRate, 0.000001),
      'Der heutige Teilwert darf die Prognosesteigung nicht ändern.');

    FullDays.Clear;
    SparseDays.Clear;
    FullDays.PeriodStart := IncDay(Date, -6);
    FullDays.PeriodEnd := IncMonth(FullDays.PeriodStart, 1);
    SparseDays.PeriodStart := FullDays.PeriodStart;
    SparseDays.PeriodEnd := FullDays.PeriodEnd;
    SetLength(FullDays.DailyCosts, 6);
    FullDays.DailyCosts[0].Day := IncDay(Date, -6);
    FullDays.DailyCosts[1].Day := IncDay(Date, -5);
    FullDays.DailyCosts[1].Amount := 1;
    FullDays.DailyCosts[2].Day := IncDay(Date, -4);
    FullDays.DailyCosts[3].Day := IncDay(Date, -3);
    FullDays.DailyCosts[4].Day := IncDay(Date, -2);
    FullDays.DailyCosts[5].Day := IncDay(Date, -1);
    FullDays.DailyCosts[5].Amount := 1;
    SetLength(SparseDays.DailyCosts, 2);
    SparseDays.DailyCosts[0] := FullDays.DailyCosts[1];
    SparseDays.DailyCosts[1] := FullDays.DailyCosts[5];
    FullDays.Recalculate;
    SparseDays.Recalculate;
    Check(SameValue(FullDays.ForecastDailyRate,
      SparseDays.ForecastDailyRate, 0.000001),
      'Fehlende Null-Buckets dürfen die Prognose nicht beschleunigen.');

    Json := Source.ToJson;
    CopySnapshot.FromJson(Json);
    Check(Length(CopySnapshot.Forecast) = 4, 'JSON-Prognose wurde nicht übertragen.');
    Check(CopySnapshot.CostToday > 9000, 'JSON-Tageswert wurde nicht übertragen.');
    Check(CopySnapshot.OrganizationId = Source.OrganizationId,
      'JSON-Organisations-ID stimmt nicht.');

    Publisher := TSnapshotPublisher.Create(18787, 'self-test-token');
    Check(Publisher.Start(ErrorText), 'Testserver startet nicht: ' + ErrorText);
    Publisher.Publish(Source);
    Check(FetchRemoteSnapshot('http://127.0.0.1:18787/snapshot',
      'self-test-token', Remote, ErrorText), 'Snapshot-Abruf fehlgeschlagen: ' + ErrorText);
    Check(Remote.OrganizationId = Source.OrganizationId,
      'Snapshot-Transport verändert Daten.');
    Publisher.Stop;
    Writeln('SELF_TEST_OK');
  finally
    Publisher.Free;
    SparseDays.Free;
    FullDays.Free;
    Remote.Free;
    CopySnapshot.Free;
    Source.Free;
  end;
end.
