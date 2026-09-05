program PlatformTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  FMX.Forms,
  Dashboard.Platform in '..\Dashboard.Platform.pas';

type
  TSuppressedForm = class(TForm)
  public
    function CanShow: Boolean; override;
  end;

function TSuppressedForm.CanShow: Boolean;
begin
  Result := False;
end;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure Run;
var
  Form: TSuppressedForm;
  Coordinator: TPlatformCoordinator;
  FormCount: Integer;
  Bounds: TRectF;
begin
  Application.Initialize;
  Form := TSuppressedForm.CreateNew(nil);
  try
    Form.SetBounds(17, 23, 320, 200);
    Form.Show;
    Check(not Form.Visible, 'CanShow must suppress the initial FMX window');
    FormCount := Screen.FormCount;
    Bounds := TRectF.Create(Form.Left, Form.Top, Form.Left + Form.Width,
      Form.Top + Form.Height);
    Coordinator := TPlatformCoordinator.Create(Form);
    try
      Coordinator.SetCollectorOnly(True);
      Coordinator.Tick(10, 18, 10);
      Coordinator.PlaceDashboard(-1);
      Coordinator.NotifyInteraction(10);
      Check(not Form.Visible, 'Collector operations must not reveal the main window');
      Check(Screen.FormCount = FormCount, 'Collector must not create blackout forms');
      Check((Form.Left = Bounds.Left) and (Form.Top = Bounds.Top) and
        (Form.Width = Bounds.Width) and (Form.Height = Bounds.Height),
        'Collector must not move or resize the main window');
      Coordinator.SetCollectorOnly(False);
      Check(Screen.FormCount = FormCount, 'Mode switch alone must not create blackout forms');
    finally
      Coordinator.Free;
    end;
  finally
    Form.Free;
  end;
end;

begin
  try
    Run;
    Writeln('COLLECTOR_PLATFORM_TESTS_OK');
  except
    on E: Exception do
    begin
      Writeln('COLLECTOR_PLATFORM_TESTS_FAILED: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
