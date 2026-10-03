program OpenAIUsageDashboard;

uses
  System.StartUpCopy,
  {$IF Defined(MSWINDOWS)}
    System.SysUtils,
    Winapi.Windows,
    Dashboard.Instance in 'Dashboard.Instance.pas',
  {$ENDIF}
  FMX.Forms,
  Dashboard.Codex in 'Dashboard.Codex.pas',
  Dashboard.DisplayPolicy in 'Dashboard.DisplayPolicy.pas',
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

{$IF Defined(MSWINDOWS)}
procedure RunWindowsDashboard;
var
  InstanceGuard: TDashboardInstance;
  ExistingWindow: HWND;
  ExistingProcess: DWORD;
  IsPreview, CollectorLaunch: Boolean;
begin
  InstanceGuard := nil;
  try
    { Preview rendering runs independently without taking the live instance's
      lock or asking it to display its dashboard. }
    IsPreview := SameText(ParamStr(1), '--render-preview') or
      SameText(ParamStr(1), '--render-settings-preview') or
      FindCmdLineSwitch('render-preview', True) or
      FindCmdLineSwitch('render-settings-preview', True);
    if not IsPreview then
    begin
      InstanceGuard := TDashboardInstance.Create;
      if not InstanceGuard.IsPrimary then
      begin
        CollectorLaunch := SameText(ParamStr(1), '--collector') or
          FindCmdLineSwitch('collector', True);
        if not CollectorLaunch then
        begin
          { A user-launched second process can transfer its foreground right
            to the real FMX dashboard; showing it still works if denied. }
          ExistingWindow := FindWindow(PChar('FM' + TMainForm.ClassName),
            'OpenAI Usage Dashboard');
          ExistingProcess := 0;
          if ExistingWindow <> 0 then
          begin
            GetWindowThreadProcessId(ExistingWindow, ExistingProcess);
            if ExistingProcess <> 0 then
              AllowSetForegroundWindow(ExistingProcess);
          end;
          InstanceGuard.RequestActivation;
        end;
        Exit;  { No form, collector, tray or power request in a second process. }
      end;
    end;
    Application.Initialize;
    try
      { FMX creates registered forms lazily inside Application.Run. }
      TMainForm.AttachInstance(InstanceGuard);
      Application.CreateForm(TMainForm, MainForm);
      Application.Run;
    finally
      { Keep ownership until all workers, servers, tray and display resources
        have been released; FMX unit finalization happens later. }
      TMainForm.AttachInstance(nil);
      FreeAndNil(MainForm);
    end;
  finally
    InstanceGuard.Free;
  end;
end;
{$ENDIF}

begin
{$IF Defined(MSWINDOWS)}
  try
    RunWindowsDashboard;
  except
    on E: Exception do
    begin
      MessageBox(0, PChar(E.Message), 'OpenAI Usage Dashboard',
        MB_OK or MB_ICONERROR);
      ExitCode := 1;
    end;
  end;
{$ELSE}
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
{$ENDIF}
end.
