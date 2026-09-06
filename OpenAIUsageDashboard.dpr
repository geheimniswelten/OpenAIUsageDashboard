program OpenAIUsageDashboard;

uses
  System.StartUpCopy,
  FMX.Forms,
  Dashboard.Codex in 'Dashboard.Codex.pas',
  Dashboard.Model in 'Dashboard.Model.pas',
  Dashboard.OpenAI in 'Dashboard.OpenAI.pas',
  Dashboard.Platform in 'Dashboard.Platform.pas',
  Dashboard.Renderer in 'Dashboard.Renderer.pas',
  Dashboard.Secrets in 'Dashboard.Secrets.pas',
  Dashboard.Settings in 'Dashboard.Settings.pas',
  Dashboard.Transport in 'Dashboard.Transport.pas',
  Dashboard.Tray in 'Dashboard.Tray.pas',
  Dashboard.Main in 'Dashboard.Main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
