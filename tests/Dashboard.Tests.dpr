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

procedure TestDailyChart;
var
  Source, Assigned, RoundTrip: TUsageSnapshot;
  Days: TArray<TDailyChartDay>;
  UtcDay: TDateTime;
begin
  Source := TUsageSnapshot.Create;
  Assigned := TUsageSnapshot.Create;
  RoundTrip := TUsageSnapshot.Create;
  try
    Check(Length(Source.GetDailyChartDays) = 0, 'Ein leeres Dashboard braucht keine erfundenen Tageswerte.');
    UtcDay := EncodeDate(2026, 8, 31);
    Source.LastUpdated := TTimeZone.Local.ToLocalTime(UtcDay + EncodeTime(23, 30, 0, 0));
    SetLength(Source.DailyCosts, 3);
    Source.DailyCosts[0].Day := UtcDay - 1;
    Source.DailyCosts[0].Amount := 1.25;
    Source.DailyCosts[0].HasCostData := True;
    Source.DailyCosts[1].Day := UtcDay - 1;
    Source.DailyCosts[1].Amount := 0.75;
    Source.DailyCosts[1].HasCostData := True;
    Source.DailyCosts[2].Day := UtcDay - 2;
    Source.DailyCosts[2].HasCostData := True;
    SetLength(Source.DailyModelUsage, 4);
    Source.DailyModelUsage[0].Day := UtcDay;
    Source.DailyModelUsage[0].Requests := 50;
    Source.DailyModelUsage[0].Tokens := 9007199254740993;
    Source.DailyModelUsage[0].HasRequestData := True;
    Source.DailyModelUsage[0].HasTokenData := True;
    Source.DailyModelUsage[1].Day := UtcDay;
    Source.DailyModelUsage[1].Requests := 4;
    Source.DailyModelUsage[1].Tokens := 7;
    Source.DailyModelUsage[1].HasRequestData := True;
    Source.DailyModelUsage[1].HasTokenData := True;
    Source.DailyModelUsage[2].Day := UtcDay - 2;
    Source.DailyModelUsage[2].HasRequestData := True;
    Source.DailyModelUsage[2].HasTokenData := True;
    Source.DailyModelUsage[3].Day := UtcDay - 20;
    Source.DailyModelUsage[3].Requests := 999;
    Source.DailyModelUsage[3].HasRequestData := True;
    Days := Source.GetDailyChartDays;
    Check((Length(Days) = 14) and SameDate(Days[0].Day, UtcDay - 13) and
      SameDate(Days[13].Day, UtcDay), 'Diagramm muss beim UTC-Tag des Sammlers enden.');
    Check((Days[13].Requests = 54) and (Days[13].Tokens = 9007199254741000) and
      Days[13].HasRequestData and Days[13].HasTokenData and not Days[13].HasCostData,
      'Heutige Nutzung muss ohne Kostenwert erhalten bleiben und gleiche Tage zusammenführen.');
    Check(SameValue(Days[12].Amount, 2.0) and Days[12].HasCostData and
      not Days[12].HasRequestData, 'Kosten müssen tageweise unabhängig von Anfragen zusammengeführt werden.');
    Check(Days[11].HasCostData and Days[11].HasRequestData and Days[11].HasTokenData and
      (Days[11].Requests = 0), 'Explizite Nullwerte müssen als gemeldet erhalten bleiben.');
    Check(not Days[10].HasCostData and not Days[10].HasRequestData and not Days[10].HasTokenData,
      'Fehlende Tage dürfen keine gemeldeten Nullwerte erzeugen.');
    Check(Length(Source.GetDailyChartDays(0)) = 0, 'Null Tage müssen ein leeres Diagramm ergeben.');
    Assigned.Assign(Source);
    Source.DailyModelUsage[0].Requests := 999;
    Check(Assigned.DailyModelUsage[0].Requests = 50, 'Assign muss Tagesnutzung unabhängig kopieren.');
    RoundTrip.FromJson(Assigned.ToJson);
    Days := RoundTrip.GetDailyChartDays;
    Check((Days[13].Requests = 54) and (Days[13].Tokens = 9007199254741000) and
      SameDate(Days[13].Day, UtcDay) and Days[13].HasRequestData and not Days[13].HasCostData,
      'JSON muss Tagesdatum, Int64-Werte und getrennte Verfügbarkeit erhalten.');
    RoundTrip.FromJson('{"lastUpdated":"2026-08-31T23:30:00Z",' +
      '"dailyCosts":[{"day":"2026-08-30","amount":1.25,"hasCostData":true}]}');
    Check(Length(RoundTrip.DailyModelUsage) = 0, 'Ältere Snapshots dürfen keine Tagesnutzung erfinden.');
    Days := RoundTrip.GetDailyChartDays;
    Check((Length(Days) = 14) and not Days[13].HasRequestData and
      SameDate(Days[13].Day, UtcDay), 'Alte Snapshots müssen mit fehlender Tagesnutzung weiter funktionieren.');
    Assigned.DailyCosts := nil;
    Days := Assigned.GetDailyChartDays;
    Check((Length(Days) = 14) and (Days[13].Requests = 54) and not Days[13].HasCostData,
      'Nutzung allein muss für ein Tagesdiagramm genügen.');
    Assigned.Clear;
    Check(Length(Assigned.DailyModelUsage) = 0, 'Clear muss Tagesnutzung entfernen.');
  finally
    RoundTrip.Free;
    Assigned.Free;
    Source.Free;
  end;
end;

procedure RunTests;
var
  Source, CopySnapshot, Remote, FullDays, SparseDays: TUsageSnapshot;
  Json, ErrorText: string;
  RateBefore: Double;
  Publisher: TSnapshotPublisher;
  UtcToday: TDateTime;
begin
  TestDailyChart;
  UtcToday := DateOf(TTimeZone.Local.ToUniversalTime(Now));
  Source := TUsageSnapshot.Create;
  CopySnapshot := TUsageSnapshot.Create;
  Remote := TUsageSnapshot.Create;
  FullDays := TUsageSnapshot.Create;
  SparseDays := TUsageSnapshot.Create;
  Publisher := nil;
  try
    Source.MakeDemo;
    Check(Length(Source.DailyCosts) = 30, 'Demo-Tageswerte fehlen.');
    Check((Length(Source.DailyModelUsage) = 30) and (Source.RequestsToday > 0),
      'Demo muss auch heutige Modellanfragen enthalten.');
    Check(Length(Source.Forecast) = 4, 'Vier Prognosewochen erwartet.');
    RateBefore := Source.ForecastDailyRate;
    Source.DailyCosts[High(Source.DailyCosts)].Amount := 9999;
    Source.Recalculate;
    Check(SameValue(RateBefore, Source.ForecastDailyRate, 0.000001),
      'Der heutige Teilwert darf die Prognosesteigung nicht ändern.');

    FullDays.Clear;
    SparseDays.Clear;
    FullDays.PeriodStart := IncDay(UtcToday, -6);
    FullDays.PeriodEnd := IncMonth(FullDays.PeriodStart, 1);
    SparseDays.PeriodStart := FullDays.PeriodStart;
    SparseDays.PeriodEnd := FullDays.PeriodEnd;
    SetLength(FullDays.DailyCosts, 6);
    FullDays.DailyCosts[0].Day := IncDay(UtcToday, -6);
    FullDays.DailyCosts[1].Day := IncDay(UtcToday, -5);
    FullDays.DailyCosts[1].Amount := 1;
    FullDays.DailyCosts[2].Day := IncDay(UtcToday, -4);
    FullDays.DailyCosts[3].Day := IncDay(UtcToday, -3);
    FullDays.DailyCosts[4].Day := IncDay(UtcToday, -2);
    FullDays.DailyCosts[5].Day := IncDay(UtcToday, -1);
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
    Check(CopySnapshot.CodexLifetimeAvailable and CopySnapshot.CodexDailyUsageAvailable and CopySnapshot.CodexTodayUsageAvailable,
      'Codex-Verfügbarkeit wurde nicht übertragen.');
    Source.CodexLifetimeAvailable := False;
    Source.CodexTodayUsageAvailable := False;
    Source.CodexError := 'Tokenstatistik nicht verfügbar';
    CopySnapshot.FromJson(Source.ToJson);
    Check(not CopySnapshot.CodexLifetimeAvailable and CopySnapshot.CodexDailyUsageAvailable,
      'Getrennte Codex-Verfügbarkeit wurde nicht erhalten.');
    Check(not CopySnapshot.CodexTodayUsageAvailable,
      'Verfügbarkeit des heutigen Codex-Buckets wurde nicht erhalten.');
    Check(CopySnapshot.CodexError = Source.CodexError,
      'Codex-Diagnose wurde nicht übertragen.');

    Publisher := TSnapshotPublisher.Create(18787, 'self-test-token');
    Check(Publisher.Start(ErrorText), 'Testserver startet nicht: ' + ErrorText);
    Publisher.Publish(Source);
    Check(FetchRemoteSnapshot('http://127.0.0.1:18787/snapshot',
      'self-test-token', Remote, ErrorText), 'Snapshot-Abruf fehlgeschlagen: ' + ErrorText);
    Check(Remote.OrganizationId = Source.OrganizationId,
      'Snapshot-Transport verändert Daten.');
    Check((Length(Remote.DailyModelUsage) = Length(Source.DailyModelUsage)) and
      (Remote.DailyModelUsage[29].Requests = Source.DailyModelUsage[29].Requests) and
      Remote.DailyModelUsage[29].HasRequestData,
      'Tagesnutzung muss über den Sammler-Transport erhalten bleiben.');
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
end;

begin
  try
    RunTests;
  except
    on E: Exception do
    begin
      Writeln('SELF_TEST_FAILED: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
