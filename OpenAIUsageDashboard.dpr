program OpenAIUsageDashboard;

uses
  System.StartUpCopy,
  FMX.Forms,
  Dashboard.Main in 'Dashboard.Main.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
