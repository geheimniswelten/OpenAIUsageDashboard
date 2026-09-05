program CodexSmoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dashboard.Model in '..\Dashboard.Model.pas',
  Dashboard.Codex in '..\Dashboard.Codex.pas';

var
  Snapshot: TUsageSnapshot;
  Client: TCodexClient;
  ErrorText: string;

begin
  Snapshot := TUsageSnapshot.Create;
  Client := TCodexClient.Create;
  try
    Snapshot.MakeDemo;
    if Client.Enrich(Snapshot, ErrorText) then
      Writeln('CODEX_SMOKE_OK limits=', Length(Snapshot.RateLimits),
        ' lifetime_tokens=', Snapshot.CodexLifetimeTokens)
    else
    begin
      Writeln('CODEX_SMOKE_UNAVAILABLE ', ErrorText);
      ExitCode := 2;
    end;
  finally
    Client.Free;
    Snapshot.Free;
  end;
end.
