program OpenAIUsageDashboard;

uses
  System.StartUpCopy,
  FMX.Forms,
  Dashboard.Codex,
  Dashboard.Model,
  Dashboard.OpenAI,
  Dashboard.Platform,
  Dashboard.Renderer,
  Dashboard.Secrets,
  Dashboard.Settings,
  Dashboard.Transport,
  Dashboard.Tray,
  Dashboard.Main in 'Dashboard.Main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
