unit Dashboard.Main;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Objects,
  FMX.Layouts,
  FMX.StdCtrls,
  FMX.Edit,
  FMX.ListBox,
  Dashboard.Model,
  Dashboard.Settings,
  Dashboard.Renderer,
  Dashboard.Platform,
  Dashboard.Transport,
  Dashboard.Codex,
  Dashboard.OpenAI;

type
  TMainForm = class(TForm)
  private
    FPaintBox: TPaintBox;
    FTimer: TTimer;
    FSettingsPanel: TRectangle;
    FSettingsScroll: TScrollBox;
{$IF Defined(MSWINDOWS)}
    FKeyEdit: TEdit;
{$ENDIF}
    FCollectorEdit: TEdit;
    FViewerTokenEdit: TEdit;
    FLimitEdit: TEdit;
    FBillingDayEdit: TEdit;
    FDisplayCombo: TComboBox;
    FDisplayValues: TArray<Integer>;
    FIdleEdit: TEdit;
    FMessageLabel: TLabel;
    FSnapshot: TUsageSnapshot;
    FSettings: TDashboardSettings;
    FRenderer: TDashboardRenderer;
    FPlatform: TPlatformCoordinator;
    FPublisher: TSnapshotPublisher;
    FCodexClient: TCodexClient;
{$IF Defined(MSWINDOWS)}
    FActiveOpenAIClient: TOpenAIUsageClient;
{$ENDIF}
    FWorker: TThread;
    FFetching: Boolean;
    FClosing: Boolean;
    FNextRefresh: TDateTime;
    FLastExternalRender: TDateTime;
    FCompanionRevealUntil: TDateTime;
    FWasExternal: Boolean;
    procedure BuildUi;
    procedure BuildSettingsPanel;
    function AddSettingsLabel(const AText: string; const AX, AY,
      AWidth: Single): TLabel;
    procedure PopulateDisplayChoices;
    procedure PaintDashboard(Sender: TObject; Canvas: TCanvas);
    procedure TimerTick(Sender: TObject);
    procedure FormShown(Sender: TObject);
    procedure FormResized(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure DashboardMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure DashboardMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure SettingsInteraction(Sender: TObject);
    procedure RegisterInteraction;
    procedure ToggleSettings(Sender: TObject);
    procedure SaveSettings(Sender: TObject);
    procedure CancelSettings(Sender: TObject);
    procedure ShowDemo(Sender: TObject);
    procedure ExitApplication(Sender: TObject);
{$IF Defined(MSWINDOWS)}
    procedure DeleteKey(Sender: TObject);
{$ENDIF}
    procedure BeginRefresh;
    procedure ApplyRefresh(const ANewSnapshot: TUsageSnapshot;
      const ASuccess: Boolean; const AError: string);
    procedure StartPublisher;
    procedure UpdateExternalDisplay(const AForce: Boolean);
{$IF Defined(ANDROID)}
    procedure RevealCompanion;
{$ENDIF}
    procedure RenderPreviewAndExit;
    procedure RenderSettingsPreviewAndExit;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

uses
  System.DateUtils,
  System.Math,
  System.IOUtils,
  Dashboard.Secrets;

const
  BackgroundColor = TAlphaColor($FF06140F);
  PanelColor = TAlphaColor($FF0B2018);
  BorderColor = TAlphaColor($FF2A7053);
  TextColor = TAlphaColor($FFF4FFF9);
  MutedColor = TAlphaColor($FF83CDB1);

constructor TMainForm.Create(AOwner: TComponent);
{$IF Defined(MSWINDOWS)}
var
  Key, ErrorText: string;
{$ENDIF}
begin
  inherited Create(AOwner);
  Caption := 'OpenAI Usage Dashboard';
  Width := 1600;
  Height := 900;
  Fill.Color := BackgroundColor;
  FSnapshot := TUsageSnapshot.Create;
  FSettings := TDashboardSettings.Create;
  FSettings.Load;
  if FSettings.UseDemoWhenUnavailable then
    FSnapshot.MakeDemo;
  FRenderer := TDashboardRenderer.Create(FSnapshot);
  FPlatform := TPlatformCoordinator.Create(Self);
  BuildUi;
  FCodexClient := TCodexClient.Create;
  FPublisher := TSnapshotPublisher.Create(FSettings.ListenPort, FSettings.ViewerToken);
  StartPublisher;
  FNextRefresh := 0;
  FLastExternalRender := 0;
  OnShow := FormShown;
  OnResize := FormResized;
  OnKeyDown := FormKeyDown;
{$IF Defined(MSWINDOWS)}
  if not TSecretStore.LoadAdminKey(Key, ErrorText) then
    FSettingsPanel.Visible := True;
{$ENDIF}
{$IF Defined(ANDROID)}
  if Pos('127.0.0.1', FSettings.CollectorUrl) > 0 then
    FSettingsPanel.Visible := True;
{$ENDIF}
end;

destructor TMainForm.Destroy;
begin
  FClosing := True;
  FTimer.Enabled := False;
  if FCodexClient <> nil then
    FCodexClient.Stop;
{$IF Defined(MSWINDOWS)}
  TMonitor.Enter(Self);
  try
    if FActiveOpenAIClient <> nil then
      FActiveOpenAIClient.Cancel;
  finally
    TMonitor.Exit(Self);
  end;
{$ENDIF}
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    TThread.RemoveQueuedEvents(FWorker);
    FreeAndNil(FWorker);
  end;
  FCodexClient.Free;
  FPublisher.Free;
  FPlatform.Free;
  FRenderer.Free;
  FSettings.Free;
  FSnapshot.Free;
  inherited;
end;

procedure TMainForm.BuildUi;
begin
  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.Align := TAlignLayout.Client;
  FPaintBox.OnPaint := PaintDashboard;
  FPaintBox.OnMouseDown := DashboardMouseDown;
  FPaintBox.OnMouseMove := DashboardMouseMove;

  BuildSettingsPanel;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

function TMainForm.AddSettingsLabel(const AText: string; const AX, AY,
  AWidth: Single): TLabel;
begin
  Result := TLabel.Create(FSettingsScroll);
  Result.Parent := FSettingsScroll;
  Result.Text := AText;
  Result.StyledSettings := [];
  Result.TextSettings.Font.Size := 12;
  Result.TextSettings.FontColor := TextColor;
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Width := AWidth;
  Result.Height := 22;
end;

procedure TMainForm.PopulateDisplayChoices;
var
  I, SelectedIndex: Integer;
  Captions: TArray<string>;
  SavedOnChange: TNotifyEvent;
begin
  if (FDisplayCombo = nil) or (FPlatform = nil) then
    Exit;
  FPlatform.GetDisplayChoices(FDisplayValues, Captions);
  SavedOnChange := FDisplayCombo.OnChange;
  FDisplayCombo.OnChange := nil;
  FDisplayCombo.Items.BeginUpdate;
  try
    FDisplayCombo.Items.Clear;
    for I := 0 to High(Captions) do
      FDisplayCombo.Items.Add(Captions[I]);
    SelectedIndex := 0;
    for I := 0 to High(FDisplayValues) do
      if FDisplayValues[I] = FSettings.DashboardDisplay then
      begin
        SelectedIndex := I;
        Break;
      end;
    if FDisplayCombo.Count > 0 then
      FDisplayCombo.ItemIndex := EnsureRange(SelectedIndex, 0,
        FDisplayCombo.Count - 1);
    for I := 0 to FDisplayCombo.Count - 1 do
    begin
      FDisplayCombo.ListItems[I].StyledSettings := [];
      FDisplayCombo.ListItems[I].TextSettings.Font.Size := 12;
      FDisplayCombo.ListItems[I].TextSettings.FontColor := TAlphaColor($FF102018);
    end;
  finally
    FDisplayCombo.Items.EndUpdate;
    FDisplayCombo.OnChange := SavedOnChange;
  end;
end;

procedure TMainForm.BuildSettingsPanel;

  function NewEdit(const AY: Single; const APassword: Boolean = False): TEdit;
  begin
    Result := TEdit.Create(FSettingsScroll);
    Result.Parent := FSettingsScroll;
    Result.Position.X := 28;
    Result.Position.Y := AY;
    Result.Width := 604;
    Result.Height := 38;
    Result.StyledSettings := [];
    Result.TextSettings.Font.Size := 12;
    Result.TextSettings.FontColor := TextColor;
    Result.Password := APassword;
    Result.OnClick := SettingsInteraction;
    Result.OnTyping := SettingsInteraction;
  end;

  function NewButton(const AText: string; const AX, AY, AWidth: Single;
    const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FSettingsScroll);
    Result.Parent := FSettingsScroll;
    Result.Text := AText;
    Result.Position.X := AX;
    Result.Position.Y := AY;
    Result.Width := AWidth;
    Result.Height := 44;
    Result.OnClick := AClick;
  end;

begin
  FSettingsPanel := TRectangle.Create(Self);
  FSettingsPanel.Parent := Self;
  FSettingsPanel.Align := TAlignLayout.Center;
  FSettingsPanel.Width := 660;
  FSettingsPanel.Height := 650;
  FSettingsPanel.XRadius := 18;
  FSettingsPanel.YRadius := 18;
  FSettingsPanel.Fill.Color := PanelColor;
  FSettingsPanel.Stroke.Color := BorderColor;
  FSettingsPanel.Stroke.Thickness := 2;
  FSettingsPanel.Visible := False;

  FSettingsScroll := TScrollBox.Create(FSettingsPanel);
  FSettingsScroll.Parent := FSettingsPanel;
  FSettingsScroll.Align := TAlignLayout.Client;
  FSettingsScroll.Margins.Rect := TRectF.Create(3, 3, 3, 3);

  with AddSettingsLabel('Einstellungen', 28, 15, 604) do
  begin
    TextSettings.Font.Size := 22;
    TextSettings.Font.Style := [TFontStyle.fsBold];
    TextSettings.FontColor := TextColor;
    Height := 38;
  end;

{$IF Defined(MSWINDOWS)}
  AddSettingsLabel('OpenAI Organization Admin-Key (leer = unverändert)', 28, 61, 604);
  FKeyEdit := NewEdit(84, True);
  FKeyEdit.TextPrompt := 'sk-admin-…';
{$ELSE}
  AddSettingsLabel('Android enthält absichtlich keinen OpenAI-Admin-Key.', 28, 68, 604);
{$ENDIF}

  AddSettingsLabel('Schreibgeschützter Windows-Sammler', 28, 132, 604);
  FCollectorEdit := NewEdit(155);
  FCollectorEdit.Text := FSettings.CollectorUrl;
  AddSettingsLabel('Viewer-Token für den Sammler', 28, 202, 604);
  FViewerTokenEdit := NewEdit(225, True);
  FViewerTokenEdit.Text := FSettings.ViewerToken;

  AddSettingsLabel('Monats-/Periodenlimit in USD (0 = API bzw. unbekannt)', 28, 272, 390);
  AddSettingsLabel('Abrechnungstag (1–28)', 440, 272, 192);
  FLimitEdit := NewEdit(295);
  FLimitEdit.Width := 390;
  FLimitEdit.Text := FloatToStr(FSettings.SpendingLimit);
  FBillingDayEdit := NewEdit(295);
  FBillingDayEdit.Position.X := 440;
  FBillingDayEdit.Width := 192;
  FBillingDayEdit.Text := IntToStr(FSettings.BillingDay);

  AddSettingsLabel('Dashboard auf Bildschirm', 28, 342, 390);
  AddSettingsLabel('Schwarz nach Minuten', 440, 342, 192);
  FDisplayCombo := TComboBox.Create(FSettingsScroll);
  FDisplayCombo.Parent := FSettingsScroll;
  FDisplayCombo.Position.X := 28;
  FDisplayCombo.Position.Y := 365;
  FDisplayCombo.Width := 390;
  FDisplayCombo.Height := 38;
  FDisplayCombo.DropDownCount := 8;
  FDisplayCombo.DisableMouseWheel := True;
  PopulateDisplayChoices;
  FDisplayCombo.OnClick := SettingsInteraction;
  FDisplayCombo.OnChange := SettingsInteraction;
  FIdleEdit := NewEdit(365);
  FIdleEdit.Position.X := 440;
  FIdleEdit.Width := 192;
  FIdleEdit.Text := IntToStr(FSettings.OtherDisplayIdleMinutes);

  FMessageLabel := TLabel.Create(FSettingsScroll);
  FMessageLabel.Parent := FSettingsScroll;
  FMessageLabel.Position.X := 28;
  FMessageLabel.Position.Y := 418;
  FMessageLabel.Width := 604;
  FMessageLabel.Height := 65;
  FMessageLabel.WordWrap := True;
  FMessageLabel.StyledSettings := [];
  FMessageLabel.TextSettings.FontColor := TextColor;
  FMessageLabel.Text := 'Wachhalten: Montag bis Freitag, 10:00–18:00 Uhr. ' +
    'Windows speichert den Key als AES-GCM → DPAPI (aktueller Nutzer) → Credential Manager.';

  NewButton('Speichern', 28, 500, 138, SaveSettings);
  NewButton('Abbrechen', 176, 500, 138, CancelSettings);
  NewButton('Demo anzeigen', 324, 500, 148, ShowDemo);
  NewButton('App beenden', 482, 500, 150, ExitApplication);
{$IF Defined(MSWINDOWS)}
  NewButton('Gespeicherten API-Key löschen', 28, 552, 294, DeleteKey);
  NewButton('Jetzt aktualisieren', 332, 552, 300, SaveSettings);
{$ELSE}
  NewButton('Jetzt aktualisieren', 28, 552, 604, SaveSettings);
{$ENDIF}
end;

procedure TMainForm.PaintDashboard(Sender: TObject; Canvas: TCanvas);
{$IF Defined(ANDROID)}
var
  SecondsRemaining: Integer;
{$ENDIF}
begin
{$IF Defined(ANDROID)}
  if FPlatform.ExternalDisplayActive then
  begin
    SecondsRemaining := Max(0, SecondsBetween(Now, FCompanionRevealUntil));
    FRenderer.RenderCompanion(Canvas, FPaintBox.LocalRect,
      FCompanionRevealUntil > Now, SecondsRemaining);
    Exit;
  end;
{$ENDIF}
  FRenderer.Render(Canvas, FPaintBox.LocalRect);
end;

procedure TMainForm.FormShown(Sender: TObject);
begin
  if ((ParamCount > 0) and SameText(ParamStr(1), '--render-settings-preview')) or
     FindCmdLineSwitch('render-settings-preview', True) then
  begin
    RenderSettingsPreviewAndExit;
    Exit;
  end;
  if ((ParamCount > 0) and SameText(ParamStr(1), '--render-preview')) or
     FindCmdLineSwitch('render-preview', True) then
  begin
    RenderPreviewAndExit;
    Exit;
  end;
  FPlatform.PlaceDashboard(FSettings.DashboardDisplay);
  PopulateDisplayChoices;
  FSettingsPanel.BringToFront;
  BeginRefresh;
end;

procedure TMainForm.RenderPreviewAndExit;
var
  Bitmap: TBitmap;
  FileName: string;
begin
  FileName := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'dashboard-preview.png';
  if ParamCount >= 2 then
    FileName := ExpandFileName(ParamStr(2));
  try
    Bitmap := TBitmap.Create(1920, 1080);
    try
      if Bitmap.Canvas.BeginScene then
      try
        FRenderer.Render(Bitmap.Canvas, TRectF.Create(0, 0, 1920, 1080));
      finally
        Bitmap.Canvas.EndScene;
      end;
      Bitmap.SaveToFile(FileName);
    finally
      Bitmap.Free;
    end;
  except
    on E: Exception do
      TFile.WriteAllText(ChangeFileExt(FileName, '.error.txt'),
        E.ClassName + ': ' + E.Message, TEncoding.UTF8);
  end;
  Application.Terminate;
end;

procedure TMainForm.RenderSettingsPreviewAndExit;
var
  Bitmap: TBitmap;
  FileName: string;
begin
  FileName := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'settings-preview.png';
  if ParamCount >= 2 then
    FileName := ExpandFileName(ParamStr(2));
  try
    FSettingsPanel.Width := 660;
    FSettingsPanel.Height := 650;
    FSettingsPanel.Visible := True;
    FDisplayCombo.ApplyStyleLookup;
    FCollectorEdit.Text := 'http://192.168.1.20:8787/snapshot';
    FViewerTokenEdit.Text := '';
    FLimitEdit.Text := '30,00';
    FBillingDayEdit.Text := '1';
    if FDisplayCombo.Items.Count > 1 then
      FDisplayCombo.ItemIndex := 1;
    FIdleEdit.Text := '10';
    Bitmap := TBitmap.Create(720, 690);
    try
      if Bitmap.Canvas.BeginScene then
      try
        Bitmap.Canvas.Clear(BackgroundColor);
        FSettingsPanel.PaintTo(Bitmap.Canvas,
          TRectF.Create(30, 20, 690, 670));
      finally
        Bitmap.Canvas.EndScene;
      end;
      Bitmap.SaveToFile(FileName);
    finally
      Bitmap.Free;
    end;
  except
    on E: Exception do
      TFile.WriteAllText(ChangeFileExt(FileName, '.error.txt'),
        E.ClassName + ': ' + E.Message, TEncoding.UTF8);
  end;
  Application.Terminate;
end;

procedure TMainForm.FormResized(Sender: TObject);
begin
  if FSettingsPanel <> nil then
  begin
    FSettingsPanel.Width := Min(660, Max(330, ClientWidth - 24));
    FSettingsPanel.Height := Min(650, Max(500, ClientHeight - 24));
  end;
  FPaintBox.Repaint;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  RegisterInteraction;
  if Key = vkF2 then
    ToggleSettings(Sender)
  else if Key = vkEscape then
    FSettingsPanel.Visible := False;
end;

procedure TMainForm.DashboardMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
{$IF Defined(ANDROID)}
var
  WasRevealed: Boolean;
{$ENDIF}
begin
{$IF Defined(ANDROID)}
  WasRevealed := FCompanionRevealUntil > Now;
{$ENDIF}
  RegisterInteraction;
{$IF Defined(ANDROID)}
  if FPlatform.ExternalDisplayActive then
  begin
    if WasRevealed then
      ToggleSettings(Sender);
    Exit;
  end;
{$ENDIF}
  if FRenderer.SettingsHitRect(FPaintBox.LocalRect).Contains(TPointF.Create(X, Y)) then
    ToggleSettings(Sender);
end;

procedure TMainForm.DashboardMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
begin
  RegisterInteraction;
{$IF Defined(MSWINDOWS)}
  if FRenderer.SettingsHitRect(FPaintBox.LocalRect).Contains(TPointF.Create(X, Y)) then
    FPaintBox.Cursor := crHandPoint
  else
    FPaintBox.Cursor := crDefault;
{$ENDIF}
end;

procedure TMainForm.SettingsInteraction(Sender: TObject);
begin
  RegisterInteraction;
end;

procedure TMainForm.RegisterInteraction;
begin
  if FPlatform = nil then
    Exit;
  FPlatform.NotifyInteraction(FSettings.OtherDisplayIdleMinutes);
{$IF Defined(ANDROID)}
  if FPlatform.ExternalDisplayActive then
    RevealCompanion;
{$ENDIF}
end;

procedure TMainForm.ToggleSettings(Sender: TObject);
begin
  RegisterInteraction;
  FSettingsPanel.Visible := not FSettingsPanel.Visible;
  if FSettingsPanel.Visible then
  begin
    FCollectorEdit.Text := FSettings.CollectorUrl;
    FViewerTokenEdit.Text := FSettings.ViewerToken;
    FLimitEdit.Text := FloatToStr(FSettings.SpendingLimit);
    FBillingDayEdit.Text := IntToStr(FSettings.BillingDay);
    PopulateDisplayChoices;
    FIdleEdit.Text := IntToStr(FSettings.OtherDisplayIdleMinutes);
    FSettingsPanel.BringToFront;
  end;
end;

procedure TMainForm.SaveSettings(Sender: TObject);
var
  FloatValue: Double;
  IntValue: Integer;
{$IF Defined(MSWINDOWS)}
  ErrorText: string;
{$ENDIF}
begin
  RegisterInteraction;
  FMessageLabel.TextSettings.FontColor := TextColor;
{$IF Defined(MSWINDOWS)}
  if (FKeyEdit <> nil) and (Trim(FKeyEdit.Text) <> '') then
  begin
    if not TSecretStore.SaveAdminKey(FKeyEdit.Text, ErrorText) then
    begin
      FMessageLabel.TextSettings.FontColor := TAlphaColor($FFFF8A80);
      FMessageLabel.Text := 'API-Key konnte nicht gespeichert werden: ' + ErrorText;
      Exit;
    end;
    FKeyEdit.Text := '';
  end;
{$ENDIF}
  FSettings.CollectorUrl := Trim(FCollectorEdit.Text);
  FSettings.ViewerToken := FViewerTokenEdit.Text;
  if TryStrToFloat(FLimitEdit.Text, FloatValue) then
    FSettings.SpendingLimit := Max(0, FloatValue);
  if TryStrToInt(FBillingDayEdit.Text, IntValue) then
    FSettings.BillingDay := EnsureRange(IntValue, 1, 28);
  if (FDisplayCombo.ItemIndex >= 0) and
     (FDisplayCombo.ItemIndex < Length(FDisplayValues)) then
    FSettings.DashboardDisplay := FDisplayValues[FDisplayCombo.ItemIndex]
  else
    FSettings.DashboardDisplay := -1;
  if TryStrToInt(FIdleEdit.Text, IntValue) then
    FSettings.OtherDisplayIdleMinutes := EnsureRange(IntValue, 1, 120);
  FSettings.Save;
  FreeAndNil(FPublisher);
  FPublisher := TSnapshotPublisher.Create(FSettings.ListenPort, FSettings.ViewerToken);
  StartPublisher;
  FPlatform.PlaceDashboard(FSettings.DashboardDisplay);
  FSettingsPanel.Visible := False;
  FNextRefresh := 0;
  BeginRefresh;
end;

procedure TMainForm.CancelSettings(Sender: TObject);
begin
  RegisterInteraction;
  FSettingsPanel.Visible := False;
end;

procedure TMainForm.ShowDemo(Sender: TObject);
begin
  RegisterInteraction;
  FSnapshot.MakeDemo;
  FSnapshot.SpendingLimit := Max(FSnapshot.SpendingLimit, FSettings.SpendingLimit);
  FSnapshot.Recalculate;
  FPublisher.Publish(FSnapshot);
  FSettingsPanel.Visible := False;
  FPaintBox.Repaint;
  UpdateExternalDisplay(True);
end;

procedure TMainForm.ExitApplication(Sender: TObject);
begin
  RegisterInteraction;
  Application.Terminate;
end;

{$IF Defined(MSWINDOWS)}
procedure TMainForm.DeleteKey(Sender: TObject);
var
  ErrorText: string;
begin
  RegisterInteraction;
  if TSecretStore.DeleteAdminKey(ErrorText) then
    FMessageLabel.Text := 'Der gespeicherte API-Key wurde entfernt.'
  else
    FMessageLabel.Text := 'Löschen fehlgeschlagen: ' + ErrorText;
end;
{$ENDIF}

procedure TMainForm.BeginRefresh;
var
  NewSnapshot: TUsageSnapshot;
{$IF Defined(MSWINDOWS)}
  AdminKey, KeyError: string;
  SpendingLimit: Double;
  BillingDay: Integer;
{$ELSE}
  Collector, ViewerToken: string;
{$ENDIF}
begin
  if FFetching or FClosing then
    Exit;
  FFetching := True;
  FNextRefresh := IncSecond(Now, FSettings.RefreshSeconds);
{$IF Defined(MSWINDOWS)}
  SpendingLimit := FSettings.SpendingLimit;
  BillingDay := FSettings.BillingDay;
  TSecretStore.LoadAdminKey(AdminKey, KeyError);
{$ELSE}
  Collector := FSettings.CollectorUrl;
  ViewerToken := FSettings.ViewerToken;
{$ENDIF}
  FWorker := TThread.CreateAnonymousThread(
    procedure
    var
{$IF Defined(MSWINDOWS)}
      Client: TOpenAIUsageClient;
      CanFetch: Boolean;
      CodexError: string;
{$ENDIF}
      Success: Boolean;
      ErrorText: string;
    begin
      NewSnapshot := TUsageSnapshot.Create;
{$IF Defined(MSWINDOWS)}
      if AdminKey = '' then
      begin
        Success := False;
        ErrorText := KeyError;
      end
      else
      begin
        Client := TOpenAIUsageClient.Create(AdminKey, SpendingLimit, BillingDay);
        TMonitor.Enter(Self);
        try
          CanFetch := not FClosing;
          if CanFetch then
            FActiveOpenAIClient := Client;
        finally
          TMonitor.Exit(Self);
        end;
        try
          if CanFetch then
            Success := Client.Fetch(NewSnapshot, ErrorText)
          else
          begin
            Success := False;
            ErrorText := 'Anwendung wird beendet.';
          end;
        finally
          TMonitor.Enter(Self);
          try
            if FActiveOpenAIClient = Client then
              FActiveOpenAIClient := nil;
          finally
            TMonitor.Exit(Self);
          end;
          Client.Free;
        end;
        if Success and not FClosing then
        begin
          FCodexClient.Enrich(NewSnapshot, CodexError);
          if CodexError <> '' then
            NewSnapshot.StatusText := 'Aktuell · Codex teilweise nicht verfügbar';
        end;
      end;
{$ELSE}
      Success := FetchRemoteSnapshot(Collector, ViewerToken, NewSnapshot, ErrorText);
{$ENDIF}
      TThread.ForceQueue(TThread.CurrentThread,
        procedure
        begin
          try
            if not FClosing then
              ApplyRefresh(NewSnapshot, Success, ErrorText);
          finally
            NewSnapshot.Free;
          end;
        end);
    end);
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

procedure TMainForm.ApplyRefresh(const ANewSnapshot: TUsageSnapshot;
  const ASuccess: Boolean; const AError: string);
begin
  FFetching := False;
  if ASuccess then
  begin
    FSnapshot.Assign(ANewSnapshot);
    if (FSnapshot.SpendingLimit <= 0) and (FSettings.SpendingLimit > 0) then
      FSnapshot.SpendingLimit := FSettings.SpendingLimit;
    FSnapshot.Recalculate;
    FPublisher.Publish(FSnapshot);
  end
  else
  begin
    if (Length(FSnapshot.DailyCosts) = 0) and FSettings.UseDemoWhenUnavailable then
      FSnapshot.MakeDemo;
    FSnapshot.StatusText := 'Veraltet · ' + AError;
  end;
  FPaintBox.Repaint;
  UpdateExternalDisplay(True);
end;

procedure TMainForm.StartPublisher;
{$IF Defined(MSWINDOWS)}
var
  ErrorText: string;
{$ENDIF}
begin
{$IF Defined(MSWINDOWS)}
  if not FPublisher.Start(ErrorText) then
    FSnapshot.StatusText := 'Snapshot-Server: ' + ErrorText;
  FPublisher.Publish(FSnapshot);
{$ENDIF}
end;

procedure TMainForm.UpdateExternalDisplay(const AForce: Boolean);
var
  Size: TSize;
  Bitmap: TBitmap;
begin
  if not FPlatform.ExternalDisplayActive then
    Exit;
  if not AForce and (SecondsBetween(Now, FLastExternalRender) < 10) then
    Exit;
  Size := FPlatform.ExternalRenderSize;
  if (Size.cx <= 0) or (Size.cy <= 0) then
    Exit;
  Bitmap := TBitmap.Create(Size.cx, Size.cy);
  try
    if Bitmap.Canvas.BeginScene then
    try
      FRenderer.Render(Bitmap.Canvas, TRectF.Create(0, 0, Size.cx, Size.cy));
    finally
      Bitmap.Canvas.EndScene;
    end;
    FPlatform.UpdateExternalBitmap(Bitmap);
    FLastExternalRender := Now;
  finally
    Bitmap.Free;
  end;
end;

{$IF Defined(ANDROID)}
procedure TMainForm.RevealCompanion;
var
  WasHidden: Boolean;
begin
  WasHidden := FCompanionRevealUntil <= Now;
  FCompanionRevealUntil := IncMinute(Now, FSettings.OtherDisplayIdleMinutes);
  if WasHidden then
    FPaintBox.Repaint;
end;
{$ENDIF}

procedure TMainForm.TimerTick(Sender: TObject);
var
  ExternalNow: Boolean;
begin
  if (FWorker <> nil) and FWorker.Finished and not FFetching then
    FreeAndNil(FWorker);
  FPlatform.Tick(FSettings.KeepAwakeStartHour, FSettings.KeepAwakeEndHour,
    FSettings.OtherDisplayIdleMinutes);
  ExternalNow := FPlatform.ExternalDisplayActive;
  if ExternalNow <> FWasExternal then
  begin
    FWasExternal := ExternalNow;
    FLastExternalRender := 0;
    FCompanionRevealUntil := 0;
    FPaintBox.Repaint;
  end;
  if ExternalNow then
  begin
    UpdateExternalDisplay(False);
    if (FCompanionRevealUntil > 0) and (FCompanionRevealUntil <= Now) then
    begin
      FCompanionRevealUntil := 0;
      FSettingsPanel.Visible := False;
      FPaintBox.Repaint;
    end;
  end;
  if (FNextRefresh = 0) or (Now >= FNextRefresh) then
    BeginRefresh;
end;

end.
