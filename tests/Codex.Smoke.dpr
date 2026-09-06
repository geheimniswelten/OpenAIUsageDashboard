program CodexSmoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.Codex in '..\Dashboard.Codex.pas';

type
  TDiagnosticClient = class(TCodexClient)
  public
    function Discover(out APath: string): Boolean;
  end;

function TDiagnosticClient.Discover(out APath: string): Boolean;
begin
  Result := FindLauncher(APath);
end;

var
  Snapshot: TUsageSnapshot;
  Client: TDiagnosticClient;
  ErrorText, LauncherPath: string;

begin
  try
    Snapshot := TUsageSnapshot.Create;
    Client := TDiagnosticClient.Create;
    try
      if SameText(ParamStr(1), '--discover') then
      begin
        if Client.Discover(LauncherPath) then
          Writeln('CODEX_LAUNCHER_FOUND ', LauncherPath)
        else
        begin
          Writeln('CODEX_LAUNCHER_UNAVAILABLE');
          ExitCode := 2;
        end;
        Exit;
      end;
      if Client.Enrich(Snapshot, ErrorText) then
      begin
        if ErrorText = '' then
          Writeln('CODEX_SMOKE_OK')
        else
        begin
          Writeln('CODEX_SMOKE_PARTIAL ', ErrorText);
          ExitCode := 2;
        end;
        Writeln('limits_available=', Snapshot.CodexRateLimitsAvailable,
          ' lifetime_available=', Snapshot.CodexLifetimeAvailable,
          ' daily_usage_available=', Snapshot.CodexDailyUsageAvailable);
      end
      else
      begin
        Writeln('CODEX_SMOKE_UNAVAILABLE ', ErrorText);
        ExitCode := 2;
      end;
    finally
      Client.Free;
      Snapshot.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('CODEX_SMOKE_FAILED ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
