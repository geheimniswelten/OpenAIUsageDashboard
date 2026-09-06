unit Dashboard.Main;

interface

uses
  {$IFDEF MSWINDOWS}
    Winapi.Windows,
  {$IFEND}
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
  Dashboard.OpenAI
  {$IFDEF MSWINDOWS}
    , Dashboard.Tray
  {$IFEND}
  ;

type
  TSettingsFieldLayout = record
    Container: TLayout;
    Caption: TLabel;
    Editor: TControl;
  end;

  TSettingsRowLayout = record
    Controls: TArray<TControl>;
    MinimumHeights: TArray<Single>;
    MinimumWidth: Single;
  end;

  TMainForm = class(TForm)
  private
    FPaintBox: TPaintBox;
    FTimer: TTimer;
    FSettingsPanel: TRectangle;
    FSettingsScroll: TScrollBox;
    FSettingsFields: TArray<TSettingsFieldLayout>;
    FSettingsRows: TArray<TSettingsRowLayout>;
    FSettingsSafeInsets: TRectF;
    FSettingsKeyboardBounds: TRect;
    FSettingsKeyboardVisible: Boolean;
    FSettingsLayoutBusy: Boolean;
    {$IFDEF MSWINDOWS}
      FKeyEdit: TEdit;
      FStartInTrayCheck: TCheckBox;
    {$IFEND}
    FCollectorEdit: TEdit;
    FViewerTokenEdit: TEdit;
    FLimitEdit: TEdit;
    FBillingDayEdit: TEdit;
    FDisplayCombo: TComboBox;
    FDisplayValues: TArray<Integer>;
    FIdleEdit: TEdit;
    FMessageLabel: TLabel;
    FDataStatusLabel: TLabel;
    FSnapshot: TUsageSnapshot;
    FSettings: TDashboardSettings;
    FRenderer: TDashboardRenderer;
    FPlatform: TPlatformCoordinator;
    FPublisher: TSnapshotPublisher;
    FCodexClient: TCodexClient;
    {$IFDEF MSWINDOWS}
      FActiveOpenAIClient: TOpenAIUsageClient;
      FTray: TDashboardTray;
      FCollectorMode: Boolean;
      FAllowCollectorSettings: Boolean;
    {$IFEND}
    FWorker: TThread;
    FFetching: Boolean;
    FClosing: Boolean;
    FNextRefresh: TDateTime;
    FLastExternalRender: TDateTime;
    FCompanionRevealUntil: TDateTime;
    FWasExternal: Boolean;
    FStarted: Boolean;
    procedure BuildUi;
    procedure BuildSettingsPanel;
    function AddSettingsField(const ACaption: string; const AEditor: TControl): TLayout;
    procedure AddSettingsRow(const AControls: array of TControl; const AMinimumWidth: Single = 0);
    procedure LayoutSettingsControls;
    procedure LayoutSettingsPanel(const AViewport: TRectF);
    procedure SettingsSafeAreaChanged(Sender: TObject; const AInsets: TRectF);
    procedure SettingsKeyboardChanged(Sender: TObject; KeyboardVisible: Boolean; const Bounds: TRect);
    procedure SettingsEditorEntered(Sender: TObject);
    procedure RevealSettingsEditor;
    function AddSettingsLabel(const AText: string; const AX, AY, AWidth: Single): TLabel;
    procedure PopulateDisplayChoices;
    procedure PaintDashboard(Sender: TObject; Canvas: TCanvas);
    procedure TimerTick(Sender: TObject);
    procedure FormShown(Sender: TObject);
    procedure FormResized(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure DashboardMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure DashboardMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure SettingsInteraction(Sender: TObject);
    procedure RegisterInteraction;
    procedure ToggleSettings(Sender: TObject);
    procedure SaveSettings(Sender: TObject);
    procedure CancelSettings(Sender: TObject);
    procedure ShowDemo(Sender: TObject);
    procedure ExitApplication(Sender: TObject);
    {$IFDEF MSWINDOWS}
      procedure DeleteKey(Sender: TObject);
      procedure TrayAction(Sender: TObject; AAction: TTrayAction);
      procedure EnterCollectorMode(Sender: TObject);
      procedure ShowDashboard;
      procedure ShowCollectorSettings;
      procedure FormClosing(Sender: TObject; var Action: TCloseAction);
    {$IFEND}
    procedure BeginRefresh;
    procedure ApplyRefresh(const ANewSnapshot: TUsageSnapshot; const ASuccess: Boolean; const AError: string);
    procedure StartPublisher;
    procedure UpdateExternalDisplay(const AForce: Boolean);
    {$IFDEF ANDROID}
      procedure RevealCompanion;
    {$IFEND}
    procedure RenderPreviewAndExit;
    procedure RenderSettingsPreviewAndExit;
  public
    function CanShow: Boolean; override;
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
  FMX.TextLayout,
  FMX.BehaviorManager,
  Dashboard.Secrets
  {$IFDEF MSWINDOWS}
    , FMX.Platform.Win
  {$IFEND}
  ;

const
  BackgroundColor = TAlphaColor($FF06140F);
  PanelColor = TAlphaColor($FF0B2018);
  BorderColor = TAlphaColor($FF2A7053);
  TextColor = TAlphaColor($FFF4FFF9);
  MutedColor = TAlphaColor($FF83CDB1);

constructor TMainForm.Create(AOwner: TComponent);
{$IFDEF MSWINDOWS}
var
  Key, ErrorText: string;
  IsPreview, WantCollector: Boolean;
{$IFEND}
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
  OnSafeAreaChanged := SettingsSafeAreaChanged;
  OnVirtualKeyboardShown := SettingsKeyboardChanged;
  OnVirtualKeyboardHidden := SettingsKeyboardChanged;
  FormResized(Self);
  OnKeyDown := FormKeyDown;
  {$IFDEF MSWINDOWS}
    if not TSecretStore.LoadAdminKey(Key, ErrorText) then
      FSettingsPanel.Visible := True;
    IsPreview := (Pos('--render-', LowerCase(ParamStr(1))) = 1);
    if not IsPreview then
    begin
      FTray := TDashboardTray.Create(TrayAction);
      FTray.Show(ErrorText);
      WantCollector := FSettings.StartInTray or SameText(ParamStr(1), '--collector') or FindCmdLineSwitch('collector', True);
      if WantCollector and (Key <> '') then
        EnterCollectorMode(nil);
    end;
    Key := '';
    OnClose := FormClosing;
  {$IFEND}
  {$IFDEF ANDROID}
    if Pos('127.0.0.1', FSettings.CollectorUrl) > 0 then
      FSettingsPanel.Visible := True;
  {$IFEND}
end;

destructor TMainForm.Destroy;
begin
  FClosing := True;
  {$IFDEF MSWINDOWS}
    FreeAndNil(FTray);
  {$IFEND}
  FTimer.Enabled := False;
  if FCodexClient <> nil then
    FCodexClient.Stop;
  {$IFDEF MSWINDOWS}
    TMonitor.Enter(Self);
    try
      if FActiveOpenAIClient <> nil then
        FActiveOpenAIClient.Cancel;
    finally
      TMonitor.Exit(Self);
    end;
  {$IFEND}
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

function TMainForm.CanShow: Boolean;
begin
  Result := inherited CanShow;
  {$IFDEF MSWINDOWS}
    Result := Result and (not FCollectorMode or FAllowCollectorSettings);
  {$IFEND}
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

function TMainForm.AddSettingsLabel(const AText: string; const AX, AY, AWidth: Single): TLabel;
begin
  Result := TLabel.Create(FSettingsScroll);
  Result.Parent := FSettingsScroll;
  Result.Text := AText;
  Result.StyledSettings := [];
  Result.TextSettings.Font.Size := 14;
  Result.TextSettings.FontColor := TextColor;
  Result.Position.X := AX;
  Result.Position.Y := AY;
  Result.Width := AWidth;
  Result.Height := 22;
  Result.WordWrap := True;
  Result.TextSettings.VertAlign := TTextAlign.Leading;
end;

function TMainForm.AddSettingsField(const ACaption: string; const AEditor: TControl): TLayout;
var
  Index: Integer;
begin
  Result := TLayout.Create(FSettingsScroll);
  Result.Parent := FSettingsScroll;
  Result.Height := 80;
  Index := Length(FSettingsFields);
  SetLength(FSettingsFields, Index + 1);
  FSettingsFields[Index].Container := Result;
  FSettingsFields[Index].Caption := AddSettingsLabel(ACaption, 0, 0, 604);
  FSettingsFields[Index].Caption.Parent := Result;
  FSettingsFields[Index].Editor := AEditor;
  AEditor.Parent := Result;
  AEditor.OnEnter := SettingsEditorEntered;
end;

procedure TMainForm.AddSettingsRow(const AControls: array of TControl; const AMinimumWidth: Single);
var
  Index, I: Integer;
begin
  Index := Length(FSettingsRows);
  SetLength(FSettingsRows, Index + 1);
  SetLength(FSettingsRows[Index].Controls, Length(AControls));
  SetLength(FSettingsRows[Index].MinimumHeights, Length(AControls));
  FSettingsRows[Index].MinimumWidth := AMinimumWidth;
  for I := 0 to High(AControls) do
  begin
    FSettingsRows[Index].Controls[I] := AControls[I];
    FSettingsRows[Index].MinimumHeights[I] := AControls[I].Height;
  end;
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
      FDisplayCombo.ListItems[I].TextSettings.Font.Size := 21.6;
      {$IFDEF ANDROID}
        FDisplayCombo.ListItems[I].TextSettings.FontColor := TAlphaColors.White;
      {$ELSE}
        FDisplayCombo.ListItems[I].TextSettings.FontColor := TAlphaColor($FF102018);
      {$IFEND}
    end;
  finally
    FDisplayCombo.Items.EndUpdate;
    FDisplayCombo.OnChange := SavedOnChange;
  end;
end;

procedure TMainForm.BuildSettingsPanel;

  function NewEdit(const APassword: Boolean = False): TEdit;
  begin
    Result := TEdit.Create(FSettingsScroll);
    Result.Parent := FSettingsScroll;
    Result.Width := 604;
    Result.Height := 54;
    Result.StyledSettings := Result.StyledSettings - [TStyledSetting.Size];
    Result.TextSettings.Font.Size := 21.6;
    {$IFDEF ANDROID}
      Result.StyledSettings := Result.StyledSettings - [TStyledSetting.FontColor];
      Result.TextSettings.FontColor := TAlphaColors.White;
    {$IFEND}
    Result.Password := APassword;
    Result.OnClick := SettingsInteraction;
    Result.OnTyping := SettingsInteraction;
  end;

  function NewButton(const AText: string; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FSettingsScroll);
    Result.Parent := FSettingsScroll;
    Result.Text := AText;
    Result.Width := 190;
    Result.Height := 56;
    Result.StyledSettings := Result.StyledSettings - [TStyledSetting.Size];
    Result.TextSettings.Font.Size := 21.6;
    {$IFDEF ANDROID}
      Result.StyledSettings := Result.StyledSettings - [TStyledSetting.FontColor];
      Result.TextSettings.FontColor := TAlphaColors.White;
    {$IFEND}
    Result.OnClick := AClick;
  end;

var
  Heading: TLabel;
begin
  FSettingsPanel := TRectangle.Create(Self);
  FSettingsPanel.Parent := Self;
  FSettingsPanel.Align := TAlignLayout.None;
  FSettingsPanel.Width := 660;
  FSettingsPanel.Height := 650;
  FSettingsPanel.XRadius := 18;
  FSettingsPanel.YRadius := 18;
  FSettingsPanel.Fill.Color := PanelColor;
  FSettingsPanel.Stroke.Color := BorderColor;
  FSettingsPanel.Stroke.Thickness := 2;
  FSettingsPanel.Visible := False;
  FSettingsPanel.ClipChildren := True;

  FSettingsScroll := TScrollBox.Create(FSettingsPanel);
  FSettingsScroll.Parent := FSettingsPanel;
  FSettingsScroll.Align := TAlignLayout.Client;
  FSettingsScroll.Margins.Rect := TRectF.Create(3, 3, 3, 3);

  FSettingsScroll.ClipChildren := True;
  FSettingsScroll.Bounces := TBehaviorBoolean.False;
  Heading := AddSettingsLabel('Einstellungen', 28, 12, 604);
  with Heading do
  begin
    TextSettings.Font.Size := 24;
    TextSettings.Font.Style := [TFontStyle.fsBold];
    TextSettings.FontColor := TextColor;
    Height := 38;
  end;
  AddSettingsRow([Heading]);

  {$IFDEF MSWINDOWS}
    FKeyEdit := NewEdit(True);
    FKeyEdit.TextPrompt := 'sk-admin-…';
    AddSettingsRow([AddSettingsField('OpenAI Organization Admin-Key (leer = unverändert)', FKeyEdit)]);
  {$ELSE}
    AddSettingsRow([AddSettingsLabel('Android erhält die Werte vom Windows-Sammler.', 28, 54, 604)]);
  {$IFEND}

  FCollectorEdit := NewEdit;
  FCollectorEdit.Text := FSettings.CollectorUrl;
  AddSettingsRow([AddSettingsField('Schreibgeschützter Windows-Sammler', FCollectorEdit)]);
  FViewerTokenEdit := NewEdit(True);
  FViewerTokenEdit.Text := FSettings.ViewerToken;
  FViewerTokenEdit.TextPrompt := 'Nur Windows: leer lassen';
  AddSettingsRow([AddSettingsField('Viewer-Token (selbst wählen; auf beiden Geräten gleich)', FViewerTokenEdit)]);

  FLimitEdit := NewEdit;
  FLimitEdit.Text := FloatToStr(FSettings.SpendingLimit);
  FBillingDayEdit := NewEdit;
  FBillingDayEdit.Text := IntToStr(FSettings.BillingDay);
  AddSettingsRow([
    AddSettingsField('Monats-/Periodenlimit in USD (0 = API bzw. unbekannt)', FLimitEdit),
    AddSettingsField('Abrechnungstag (1–28)', FBillingDayEdit)], 250);

  FDisplayCombo := TComboBox.Create(FSettingsScroll);
  FDisplayCombo.Parent := FSettingsScroll;
  FDisplayCombo.Width := 390;
  FDisplayCombo.Height := 54;
  FDisplayCombo.ItemHeight := 50;
  FDisplayCombo.DropDownCount := 8;
  FDisplayCombo.DisableMouseWheel := True;
  {$IFDEF ANDROID}
    FDisplayCombo.StyledSettings := FDisplayCombo.StyledSettings - [TStyledSetting.FontColor];
    FDisplayCombo.TextSettings.FontColor := TAlphaColors.White;
  {$IFEND}
  PopulateDisplayChoices;
  FDisplayCombo.OnClick := SettingsInteraction;
  FDisplayCombo.OnChange := SettingsInteraction;
  FIdleEdit := NewEdit;
  FIdleEdit.Text := IntToStr(FSettings.OtherDisplayIdleMinutes);
  AddSettingsRow([
    AddSettingsField('Dashboard auf Bildschirm', FDisplayCombo),
    AddSettingsField('Schwarz nach Minuten', FIdleEdit)], 250);

  {$IFDEF MSWINDOWS}
    FStartInTrayCheck := TCheckBox.Create(FSettingsScroll);
    FStartInTrayCheck.Parent := FSettingsScroll;
    FStartInTrayCheck.Text := 'Beim Start nur Sammler (Tray-Symbol)';
    FStartInTrayCheck.StyledSettings := [];
    FStartInTrayCheck.TextSettings.Font.Size := 18;
    FStartInTrayCheck.TextSettings.FontColor := TextColor;
    FStartInTrayCheck.WordWrap := True;
    FStartInTrayCheck.Height := 54;
    FStartInTrayCheck.IsChecked := FSettings.StartInTray;
    FStartInTrayCheck.OnClick := SettingsInteraction;
    AddSettingsRow([FStartInTrayCheck]);
  {$IFEND}

  FMessageLabel := TLabel.Create(FSettingsScroll);
  FMessageLabel.Parent := FSettingsScroll;
  FMessageLabel.Position.X := 28;
  FMessageLabel.Position.Y := 447;
  FMessageLabel.Width := 604;
  FMessageLabel.Height := 50;
  FMessageLabel.WordWrap := True;
  FMessageLabel.StyledSettings := [];
  FMessageLabel.TextSettings.Font.Size := 13;
  FMessageLabel.TextSettings.FontColor := TextColor;
  FMessageLabel.Text := 'Wachhalten: Montag bis Freitag, 10:00–18:00 Uhr. '
  {$IFDEF MSWINDOWS}
    + 'Windows speichert den Key als AES-GCM → DPAPI (aktueller Nutzer) → Credential Manager.';
  {$ELSE}
    + 'Sammler-Adresse und Viewer-Token müssen zum Windows-Gerät passen.';
  {$IFEND}
  AddSettingsRow([FMessageLabel]);

  AddSettingsRow([NewButton('Speichern', SaveSettings),
    NewButton('Abbrechen', CancelSettings),
    NewButton('App beenden', ExitApplication)], 180);
  {$IFDEF MSWINDOWS}
    AddSettingsRow([NewButton('Demo anzeigen', ShowDemo),
      NewButton('API-Key löschen', DeleteKey),
      NewButton('Jetzt aktualisieren', SaveSettings)], 180);
    AddSettingsRow([NewButton('Nur Sammler / Tray', EnterCollectorMode)]);
  {$ELSE}
    AddSettingsRow([NewButton('Demo anzeigen', ShowDemo),
      NewButton('Jetzt aktualisieren', SaveSettings)], 180);
  {$IFEND}
  FDataStatusLabel := AddSettingsLabel('Codex: noch nicht abgefragt.', 28, 642, 604);
  FDataStatusLabel.Height := 120;
  FDataStatusLabel.WordWrap := True;
  FDataStatusLabel.TextSettings.VertAlign := TTextAlign.Leading;
  AddSettingsRow([FDataStatusLabel]);
  LayoutSettingsControls;
end;

procedure TMainForm.PaintDashboard(Sender: TObject; Canvas: TCanvas);
{$IFDEF ANDROID}
var
  SecondsRemaining: Integer;
{$IFEND}
begin
  {$IFDEF ANDROID}
    if FPlatform.ExternalDisplayActive then
    begin
      SecondsRemaining := Max(0, SecondsBetween(Now, FCompanionRevealUntil));
      FRenderer.RenderCompanion(Canvas, FPaintBox.LocalRect,
        FCompanionRevealUntil > Now, SecondsRemaining);
      Exit;
    end;
  {$IFEND}
  FRenderer.Render(Canvas, FPaintBox.LocalRect);
end;

procedure TMainForm.FormShown(Sender: TObject);
begin
  FormResized(Self);
  if FStarted then
    Exit;
  FStarted := True;
  if ((ParamCount > 0) and SameText(ParamStr(1), '--render-settings-preview')) or FindCmdLineSwitch('render-settings-preview', True) then
  begin
    RenderSettingsPreviewAndExit;
    Exit;
  end;
  if ((ParamCount > 0) and SameText(ParamStr(1), '--render-preview')) or FindCmdLineSwitch('render-preview', True) then
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
  FSnapshot.MakeDemo;
  FileName := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'dashboard-preview.png';
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
      TFile.WriteAllText(ChangeFileExt(FileName, '.error.txt'), E.ClassName + ': ' + E.Message, TEncoding.UTF8);
  end;
  Application.Terminate;
end;

procedure TMainForm.RenderSettingsPreviewAndExit;
var
  Bitmap: TBitmap;
  FileName: string;
  PreviewWidth, PreviewHeight: Integer;
begin
  FileName := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'settings-preview.png';
  if ParamCount >= 2 then
    FileName := ExpandFileName(ParamStr(2));
  PreviewWidth := 720;
  PreviewHeight := 690;
  if ParamCount >= 3 then
    PreviewWidth := EnsureRange(StrToIntDef(ParamStr(3), PreviewWidth), 160, 8192);
  if ParamCount >= 4 then
    PreviewHeight := EnsureRange(StrToIntDef(ParamStr(4), PreviewHeight), 160, 8192);
  try
    FSettingsSafeInsets := TRectF.Empty;
    FSettingsKeyboardVisible := False;
    FSettingsPanel.Visible := True;
    {$IFDEF MSWINDOWS}
      FKeyEdit.ApplyStyleLookup;
    {$IFEND}
    FDisplayCombo.ApplyStyleLookup;
    FCollectorEdit.ApplyStyleLookup;
    FViewerTokenEdit.ApplyStyleLookup;
    FLimitEdit.ApplyStyleLookup;
    FBillingDayEdit.ApplyStyleLookup;
    FIdleEdit.ApplyStyleLookup;
    FCollectorEdit.Text := 'http://192.168.1.20:8787/snapshot';
    FViewerTokenEdit.Text := '';
    FLimitEdit.Text := '30,00';
    FBillingDayEdit.Text := '1';
    if FDisplayCombo.Items.Count > 1 then
      FDisplayCombo.ItemIndex := 1;
    FIdleEdit.Text := '10';
    LayoutSettingsPanel(TRectF.Create(0, 0, PreviewWidth, PreviewHeight));
    FSettingsScroll.ViewportPosition := TPointF.Zero;
    if ParamCount >= 5 then
      FSettingsScroll.ViewportPosition := TPointF.Create(0,
        EnsureRange(Single(StrToIntDef(ParamStr(5), 0)), Single(0),
          Max(Single(0), FSettingsScroll.ContentBounds.Bottom - FSettingsScroll.ClientHeight)));
    Bitmap := TBitmap.Create(PreviewWidth, PreviewHeight);
    try
      if Bitmap.Canvas.BeginScene then
      try
        Bitmap.Canvas.Clear(BackgroundColor);
        FSettingsPanel.PaintTo(Bitmap.Canvas,
          TRectF.Create(FSettingsPanel.Position.X, FSettingsPanel.Position.Y,
            FSettingsPanel.Position.X + FSettingsPanel.Width,
            FSettingsPanel.Position.Y + FSettingsPanel.Height));
      finally
        Bitmap.Canvas.EndScene;
      end;
      Bitmap.SaveToFile(FileName);
    finally
      Bitmap.Free;
    end;
  except
    on E: Exception do
      TFile.WriteAllText(ChangeFileExt(FileName, '.error.txt'), E.ClassName + ': ' + E.Message, TEncoding.UTF8);
  end;
  Application.Terminate;
end;

procedure TMainForm.FormResized(Sender: TObject);
begin
  LayoutSettingsPanel(ClientRect);
  if FPaintBox <> nil then
    FPaintBox.Repaint;
end;

procedure TMainForm.LayoutSettingsControls;
const
  HorizontalPadding = 20;
  ControlGap = 12;
var
  RowIndex, ItemIndex, ColumnIndex, Columns, CountInLine, FieldIndex: Integer;
  ContentWidth, ItemWidth, X, Y, RowHeight, ItemHeight, CaptionHeight: Single;
  Item: TControl;
  TextLayout: TTextLayout;

  function TextHeight(const AText: string; const AFont: TFont; const AWidth, AMinimumHeight: Single): Single;
  begin
    TextLayout.BeginUpdate;
    try
      TextLayout.Font.Assign(AFont);
      TextLayout.WordWrap := True;
      TextLayout.MaxSize := TPointF.Create(Max(1, AWidth), 10000);
      TextLayout.Text := AText;
    finally
      TextLayout.EndUpdate;
    end;
    Result := Max(AMinimumHeight, Ceil(TextLayout.TextHeight) + 4);
  end;

begin
  if (FSettingsScroll = nil) or FSettingsLayoutBusy then
    Exit;
  FSettingsLayoutBusy := True;
  TextLayout := nil;
  try
    // The style owns the viewport and scrollbars needed for ContentBounds.
    FSettingsScroll.ApplyStyleLookup;
    TextLayout := TTextLayoutManager.DefaultTextLayout.Create;
    // Reserve room for a persistent scrollbar without reducing text or touch sizes.
    ContentWidth := Max(1, FSettingsScroll.Width - 2 * HorizontalPadding - 16);
    Y := 12;
    for RowIndex := 0 to High(FSettingsRows) do
    begin
      Columns := Length(FSettingsRows[RowIndex].Controls);
      if FSettingsRows[RowIndex].MinimumWidth > 0 then
        Columns := Min(Columns, Max(1, Floor((ContentWidth + ControlGap) / (FSettingsRows[RowIndex].MinimumWidth + ControlGap))));
      ItemIndex := 0;
      while ItemIndex < Length(FSettingsRows[RowIndex].Controls) do
      begin
        CountInLine := Min(Columns, Length(FSettingsRows[RowIndex].Controls) - ItemIndex);
        ItemWidth := (ContentWidth - (CountInLine - 1) * ControlGap) / CountInLine;
        RowHeight := 0;
        for ColumnIndex := 0 to CountInLine - 1 do
        begin
          Item := FSettingsRows[RowIndex].Controls[ItemIndex + ColumnIndex];
          ItemHeight := FSettingsRows[RowIndex].MinimumHeights[ItemIndex + ColumnIndex];
          if Item is TLabel then
            ItemHeight := TextHeight(TLabel(Item).Text, TLabel(Item).TextSettings.Font, ItemWidth, ItemHeight)
          else if Item is TCheckBox then
            ItemHeight := TextHeight(TCheckBox(Item).Text, TCheckBox(Item).TextSettings.Font, ItemWidth - 36, ItemHeight);
          for FieldIndex := 0 to High(FSettingsFields) do
            if FSettingsFields[FieldIndex].Container = Item then
            begin
              // PaintTo cannot load styles itself; initialize nested labels here.
              FSettingsFields[FieldIndex].Caption.ApplyStyleLookup;
              CaptionHeight := TextHeight(FSettingsFields[FieldIndex].Caption.Text, FSettingsFields[FieldIndex].Caption.TextSettings.Font, ItemWidth, 22);
              FSettingsFields[FieldIndex].Caption.SetBounds(0, 0, ItemWidth, CaptionHeight);
              FSettingsFields[FieldIndex].Editor.SetBounds(0, CaptionHeight + 4, ItemWidth, 54);
              ItemHeight := CaptionHeight + 4 + 54;
              Break;
            end;
          X := HorizontalPadding + ColumnIndex * (ItemWidth + ControlGap);
          Item.SetBounds(X, Y, ItemWidth, ItemHeight);
          RowHeight := Max(RowHeight, ItemHeight);
        end;
        // Keep the paired editors on the same baseline when one caption wraps.
        for ColumnIndex := 0 to CountInLine - 1 do
        begin
          Item := FSettingsRows[RowIndex].Controls[ItemIndex + ColumnIndex];
          for FieldIndex := 0 to High(FSettingsFields) do
            if FSettingsFields[FieldIndex].Container = Item then
            begin
              Item.Height := RowHeight;
              FSettingsFields[FieldIndex].Editor.Position.Y := RowHeight - 54;
              Break;
            end;
        end;
        Y := Y + RowHeight + ControlGap;
        Inc(ItemIndex, CountInLine);
      end;
    end;
    FSettingsScroll.RealignContent;
    FSettingsScroll.ViewportPosition := TPointF.Create(0,
      EnsureRange(FSettingsScroll.ViewportPosition.Y, Single(0), Max(Single(0), Y - FSettingsScroll.ClientHeight)));
  finally
    TextLayout.Free;
    FSettingsLayoutBusy := False;
  end;
end;

procedure TMainForm.LayoutSettingsPanel(const AViewport: TRectF);
var
  Available: TRectF;
  KeyboardTop: Single;
  PanelWidth, PanelHeight, Margin: Single;
begin
  if (FSettingsPanel = nil) or FSettingsLayoutBusy then
    Exit;
  Available := TRectF.Create(
    AViewport.Left + Max(0, FSettingsSafeInsets.Left),
    AViewport.Top + Max(0, FSettingsSafeInsets.Top),
    AViewport.Right - Max(0, FSettingsSafeInsets.Right),
    AViewport.Bottom - Max(0, FSettingsSafeInsets.Bottom));
  if FSettingsKeyboardVisible and (FSettingsKeyboardBounds.Height > 0) then
  begin
    KeyboardTop := ScreenToClient(TPointF.Create(FSettingsKeyboardBounds.Left, FSettingsKeyboardBounds.Top)).Y;
    if KeyboardTop > Available.Top then
      Available.Bottom := Min(Available.Bottom, KeyboardTop);
  end;
  if (Available.Width <= 0) or (Available.Height <= 0) then
    Available := AViewport;
  Margin := Min(12, Max(0, Min(Available.Width, Available.Height) / 20));
  PanelWidth := Max(1, Min(660, Available.Width - 2 * Margin));
  PanelHeight := Max(1, Min(650, Available.Height - 2 * Margin));
  FSettingsPanel.SetBounds(
    Available.Left + (Available.Width - PanelWidth) / 2,
    Available.Top + (Available.Height - PanelHeight) / 2,
    PanelWidth, PanelHeight);
  LayoutSettingsControls;
  RevealSettingsEditor;
end;

procedure TMainForm.SettingsSafeAreaChanged(Sender: TObject; const AInsets: TRectF);
begin
  FSettingsSafeInsets := AInsets;
  FormResized(Sender);
end;

procedure TMainForm.SettingsKeyboardChanged(Sender: TObject;
  KeyboardVisible: Boolean; const Bounds: TRect);
begin
  FSettingsKeyboardVisible := KeyboardVisible;
  FSettingsKeyboardBounds := Bounds;
  FormResized(Sender);
end;

procedure TMainForm.SettingsEditorEntered(Sender: TObject);
begin
  RegisterInteraction;
  RevealSettingsEditor;
end;

procedure TMainForm.RevealSettingsEditor;
var
  Editor: TControl;
  TopLeft, BottomRight: TPointF;
  Offset, NewY: Single;
begin
  if (FSettingsScroll = nil) or not FSettingsPanel.Visible or (Focused = nil) then
    Exit;
  if not (Focused.GetObject is TControl) then
    Exit;
  Editor := TControl(Focused.GetObject);
  if not FSettingsScroll.IsChild(Editor) then
    Exit;
  TopLeft := FSettingsScroll.AbsoluteToLocal(Editor.LocalToAbsolute(TPointF.Zero));
  BottomRight := FSettingsScroll.AbsoluteToLocal(Editor.LocalToAbsolute(TPointF.Create(Editor.Width, Editor.Height)));
  Offset := 0;
  if TopLeft.Y < 12 then
    Offset := TopLeft.Y - 12
  else if BottomRight.Y > FSettingsScroll.ClientHeight - 12 then
    Offset := BottomRight.Y - FSettingsScroll.ClientHeight + 12;
  NewY := EnsureRange(FSettingsScroll.ViewportPosition.Y + Offset, Single(0),
    Max(Single(0), FSettingsScroll.ContentBounds.Bottom - FSettingsScroll.ClientHeight));
  FSettingsScroll.ViewportPosition := TPointF.Create(0, NewY);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  RegisterInteraction;
  if Key = vkF2 then
    ToggleSettings(Sender)
  else if Key = vkEscape then
    CancelSettings(Sender);
end;

procedure TMainForm.DashboardMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
{$IFDEF ANDROID}
var
  WasRevealed: Boolean;
{$IFEND}
begin
  {$IFDEF ANDROID}
    WasRevealed := FCompanionRevealUntil > Now;
  {$IFEND}
  RegisterInteraction;
  {$IFDEF ANDROID}
    if FPlatform.ExternalDisplayActive then
    begin
      if WasRevealed then
        ToggleSettings(Sender);
      Exit;
    end;
  {$IFEND}
  {$IFDEF MSWINDOWS}
    if (Button = TMouseButton.mbLeft) and (ssDouble in Shift) and not FSettingsPanel.Visible
      and not FRenderer.SettingsHitRect(FPaintBox.LocalRect).Contains(TPointF.Create(X, Y)) then
    begin
      EnterCollectorMode(Sender);
      Exit;
    end;
  {$IFEND}
  if FRenderer.SettingsHitRect(FPaintBox.LocalRect).Contains(TPointF.Create(X, Y)) then
    ToggleSettings(Sender);
end;

procedure TMainForm.DashboardMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
begin
  RegisterInteraction;
  {$IFDEF MSWINDOWS}
    if FRenderer.SettingsHitRect(FPaintBox.LocalRect).Contains(TPointF.Create(X, Y)) then
      FPaintBox.Cursor := crHandPoint
    else
      FPaintBox.Cursor := crDefault;
  {$IFEND}
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
  {$IFDEF ANDROID}
    if FPlatform.ExternalDisplayActive then
      RevealCompanion;
  {$IFEND}
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
    {$IFDEF MSWINDOWS}
      FStartInTrayCheck.IsChecked := FSettings.StartInTray;
    {$IFEND}
    FormResized(Self);
    FSettingsScroll.ViewportPosition := TPointF.Zero;
    FSettingsPanel.BringToFront;
  end
  {$IFDEF MSWINDOWS}
    else if FCollectorMode then
      EnterCollectorMode(nil)
  {$IFEND}
  ;
end;

procedure TMainForm.SaveSettings(Sender: TObject);
var
  FloatValue: Double;
  IntValue: Integer;
  {$IFDEF MSWINDOWS}
    ErrorText: string;
  {$IFEND}
begin
  RegisterInteraction;
  FMessageLabel.TextSettings.FontColor := TextColor;
  {$IFDEF MSWINDOWS}
    if (FKeyEdit <> nil) and (Trim(FKeyEdit.Text) <> '') then
    begin
      if not TSecretStore.SaveAdminKey(FKeyEdit.Text, ErrorText) then
      begin
        FMessageLabel.TextSettings.FontColor := TAlphaColor($FFFF8A80);
        FMessageLabel.Text := 'API-Key konnte nicht gespeichert werden: ' + ErrorText;
        LayoutSettingsControls;
        Exit;
      end;
      FKeyEdit.Text := '';
    end;
  {$IFEND}
  FSettings.CollectorUrl := Trim(FCollectorEdit.Text);
  FSettings.ViewerToken := FViewerTokenEdit.Text;
  if TryStrToFloat(FLimitEdit.Text, FloatValue) then
    FSettings.SpendingLimit := Max(0, FloatValue);
  if TryStrToInt(FBillingDayEdit.Text, IntValue) then
    FSettings.BillingDay := EnsureRange(IntValue, 1, 28);
  if (FDisplayCombo.ItemIndex >= 0) and (FDisplayCombo.ItemIndex < Length(FDisplayValues)) then
    FSettings.DashboardDisplay := FDisplayValues[FDisplayCombo.ItemIndex]
  else
    FSettings.DashboardDisplay := -1;
  if TryStrToInt(FIdleEdit.Text, IntValue) then
    FSettings.OtherDisplayIdleMinutes := EnsureRange(IntValue, 1, 120);
  {$IFDEF MSWINDOWS}
    FSettings.StartInTray := FStartInTrayCheck.IsChecked;
  {$IFEND}
  FSettings.Save;
  FreeAndNil(FPublisher);
  FPublisher := TSnapshotPublisher.Create(FSettings.ListenPort, FSettings.ViewerToken);
  StartPublisher;
  FPlatform.PlaceDashboard(FSettings.DashboardDisplay);
  FSettingsPanel.Visible := False;
  FNextRefresh := 0;
  BeginRefresh;
  {$IFDEF MSWINDOWS}
    if FCollectorMode then
      EnterCollectorMode(nil);
  {$IFEND}
end;

procedure TMainForm.CancelSettings(Sender: TObject);
begin
  RegisterInteraction;
  FSettingsPanel.Visible := False;
  {$IFDEF MSWINDOWS}
    if FCollectorMode then
      EnterCollectorMode(nil);
  {$IFEND}
end;

procedure TMainForm.ShowDemo(Sender: TObject);
begin
  RegisterInteraction;
  {$IFDEF MSWINDOWS}
    if FCollectorMode then
      ShowDashboard;
  {$IFEND}
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

{$IFDEF MSWINDOWS}
procedure TMainForm.TrayAction(Sender: TObject; AAction: TTrayAction);
begin
  if FClosing then
    Exit;
  case AAction of
    taShowDashboard: ShowDashboard;
    taShowSettings: ShowCollectorSettings;
    taCollectorMode: EnterCollectorMode(Sender);
    taExit: ExitApplication(Sender);
  end;
end;

procedure TMainForm.EnterCollectorMode(Sender: TObject);
var
  ErrorText: string;
begin
  { Never hide the only UI unless the tray icon is actually available. }
  if (FTray = nil) or not FTray.Show(ErrorText) then
  begin
    FMessageLabel.Text := 'Sammlermodus nicht verfügbar: ' + ErrorText;
    FSettingsPanel.Visible := True;
    FormResized(Self);
    Exit;
  end;
  FPlatform.SetCollectorOnly(True);
  FCollectorMode := True;
  FAllowCollectorSettings := False;
  FTray.SetCollectorMode(True);
  FTray.UpdateStatus(FSnapshot.StatusText);
  FSettingsPanel.Visible := False;
  Hide;
  Winapi.Windows.ShowWindow(FMX.Platform.Win.ApplicationHWND, SW_HIDE);
  { A hidden initial main form never receives OnShow. The timer starts fetching. }
end;

procedure TMainForm.ShowDashboard;
begin
  FCollectorMode := False;
  FAllowCollectorSettings := False;
  FPlatform.SetCollectorOnly(False);
  if FTray <> nil then
    FTray.SetCollectorMode(False);
  WindowState := TWindowState.wsNormal;
  FPlatform.PlaceDashboard(FSettings.DashboardDisplay);
  FStarted := True;
  Winapi.Windows.ShowWindow(FMX.Platform.Win.ApplicationHWND, SW_SHOWNOACTIVATE);
  Show;
  BringToFront;
  FormResized(Self);
  RegisterInteraction;
end;

procedure TMainForm.ShowCollectorSettings;
var
  WorkArea: TRectF;
  WindowWidth, WindowHeight: Single;
begin
  if FCollectorMode then
  begin
    FAllowCollectorSettings := True;
    FStarted := True;
    WindowState := TWindowState.wsNormal;
    FullScreen := False;
    FormStyle := TFormStyle.Normal;
    BorderStyle := TFmxFormBorderStyle.Sizeable;
    WorkArea := Screen.DisplayFromPoint(Screen.MousePos).Workarea;
    WindowWidth := Min(720, Max(1, WorkArea.Width - 24));
    WindowHeight := Min(780, Max(1, WorkArea.Height - 24));
    Position := TFormPosition.Designed;
    SetBoundsF(TRectF.Create(WorkArea.CenterPoint.X - WindowWidth / 2, WorkArea.CenterPoint.Y - WindowHeight / 2,
      WorkArea.CenterPoint.X + WindowWidth / 2, WorkArea.CenterPoint.Y + WindowHeight / 2));
    Winapi.Windows.ShowWindow(FMX.Platform.Win.ApplicationHWND, SW_SHOWNOACTIVATE);
    Show;
    BringToFront;
  end
  else
    ShowDashboard;
  FSettingsPanel.Visible := False;
  ToggleSettings(Self);
end;

procedure TMainForm.FormClosing(Sender: TObject; var Action: TCloseAction);
begin
  if FCollectorMode and not FClosing then
  begin
    Action := TCloseAction.caNone;
    EnterCollectorMode(Sender);
  end;
end;

procedure TMainForm.DeleteKey(Sender: TObject);
var
  ErrorText: string;
begin
  RegisterInteraction;
  if TSecretStore.DeleteAdminKey(ErrorText) then
    FMessageLabel.Text := 'Der gespeicherte API-Key wurde entfernt.'
  else
    FMessageLabel.Text := 'Löschen fehlgeschlagen: ' + ErrorText;
  LayoutSettingsControls;
end;
{$IFEND}

procedure TMainForm.BeginRefresh;
var
  NewSnapshot: TUsageSnapshot;
  {$IFDEF MSWINDOWS}
    AdminKey, KeyError: string;
    SpendingLimit: Double;
    BillingDay: Integer;
  {$ELSE}
    Collector, ViewerToken: string;
  {$IFEND}
begin
  if FFetching or FClosing then
    Exit;
  if FWorker <> nil then
  begin
    if not FWorker.Finished then
      Exit;
    FreeAndNil(FWorker);
  end;
  FFetching := True;
  FNextRefresh := IncSecond(Now, FSettings.RefreshSeconds);
  {$IFDEF MSWINDOWS}
    SpendingLimit := FSettings.SpendingLimit;
    BillingDay := FSettings.BillingDay;
    TSecretStore.LoadAdminKey(AdminKey, KeyError);
  {$ELSE}
    Collector := FSettings.CollectorUrl;
    ViewerToken := FSettings.ViewerToken;
  {$IFEND}
  FWorker := TThread.CreateAnonymousThread(
    procedure
    var
      {$IFDEF MSWINDOWS}
        Client: TOpenAIUsageClient;
        CanFetch: Boolean;
        CodexError: string;
      {$IFEND}
      Success: Boolean;
      ErrorText: string;
    begin
      NewSnapshot := TUsageSnapshot.Create;
      {$IFDEF MSWINDOWS}
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
            begin
              if NewSnapshot.CodexRateLimitsAvailable or NewSnapshot.CodexUsageAvailable then
                NewSnapshot.StatusText := 'Aktuell · Codex teilweise nicht verfügbar'
              else
                NewSnapshot.StatusText := 'Aktuell · Codex nicht verfügbar';
            end;
          end;
        end;
      {$ELSE}
        Success := FetchRemoteSnapshot(Collector, ViewerToken, NewSnapshot, ErrorText);
      {$IFEND}
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

procedure TMainForm.ApplyRefresh(const ANewSnapshot: TUsageSnapshot; const ASuccess: Boolean; const AError: string);
var
  PreviousCostToday: Double;
  PreviousCodexTodayTokens, PreviousCodexSevenDayTokens, PreviousCodexMonthTokens: Int64;
  PreserveCostToday, PreserveCodexToday, PreserveCodexDailyUsage: Boolean;
  PreviousUtcDay, NewUtcDay: TDateTime;
  DailyCost: TDailyCost;
  I, TodayCostIndex: Integer;
begin
  FFetching := False;
  if ASuccess then
  begin
    PreserveCostToday := False;
    PreserveCodexToday := False;
    PreserveCodexDailyUsage := False;
    if (FSnapshot.LastUpdated > 0) and (ANewSnapshot.LastUpdated > 0) then
    begin
      PreviousUtcDay := DateOf(TTimeZone.Local.ToUniversalTime(FSnapshot.LastUpdated));
      NewUtcDay := DateOf(TTimeZone.Local.ToUniversalTime(ANewSnapshot.LastUpdated));
      PreserveCostToday := FSnapshot.CostTodayAvailable and not ANewSnapshot.CostTodayAvailable and SameDate(PreviousUtcDay, NewUtcDay);
      PreserveCodexToday := FSnapshot.CodexTodayUsageAvailable and not ANewSnapshot.CodexTodayUsageAvailable
        and SameDate(FSnapshot.LastUpdated, ANewSnapshot.LastUpdated);
      PreserveCodexDailyUsage := FSnapshot.CodexDailyUsageAvailable and not ANewSnapshot.CodexDailyUsageAvailable
        and SameDate(FSnapshot.LastUpdated, ANewSnapshot.LastUpdated);
    end;
    PreviousCostToday := FSnapshot.CostToday;
    PreviousCodexTodayTokens := FSnapshot.CodexTodayTokens;
    PreviousCodexSevenDayTokens := FSnapshot.CodexSevenDayTokens;
    PreviousCodexMonthTokens := FSnapshot.CodexMonthTokens;
    if PreserveCostToday then
    begin
      TodayCostIndex := -1;
      for I := 0 to High(ANewSnapshot.DailyCosts) do
        if SameDate(ANewSnapshot.DailyCosts[I].Day, NewUtcDay) then
        begin
          TodayCostIndex := I;
          Break;
        end;
      if TodayCostIndex < 0 then
      begin
        TodayCostIndex := Length(ANewSnapshot.DailyCosts);
        SetLength(ANewSnapshot.DailyCosts, TodayCostIndex + 1);
      end;
      DailyCost.Day := NewUtcDay;
      DailyCost.Amount := PreviousCostToday;
      DailyCost.HasCostData := True;
      ANewSnapshot.DailyCosts[TodayCostIndex] := DailyCost;
    end;
    FSnapshot.Assign(ANewSnapshot);
    if (FSnapshot.SpendingLimit <= 0) and (FSettings.SpendingLimit > 0) then
      FSnapshot.SpendingLimit := FSettings.SpendingLimit;
    FSnapshot.Recalculate;
    if PreserveCodexDailyUsage then
    begin
      FSnapshot.CodexSevenDayTokens := PreviousCodexSevenDayTokens;
      FSnapshot.CodexMonthTokens := PreviousCodexMonthTokens;
      FSnapshot.CodexDailyUsageAvailable := True;
      FSnapshot.CodexUsageAvailable := True;
    end;
    if PreserveCodexToday then
    begin
      FSnapshot.CodexTodayTokens := PreviousCodexTodayTokens;
      FSnapshot.CodexTodayUsageAvailable := True;
      FSnapshot.CodexUsageAvailable := True;
    end;
    FPublisher.Publish(FSnapshot);
  end
  else
  begin
    if (Length(FSnapshot.DailyCosts) = 0) and FSettings.UseDemoWhenUnavailable then
      FSnapshot.MakeDemo;
    FSnapshot.StatusText := 'Veraltet · ' + AError;
  end;
  if FSnapshot.CodexError <> '' then
    FDataStatusLabel.Text := 'Codex: ' + FSnapshot.CodexError
  else if FSnapshot.CodexUsageAvailable then
    FDataStatusLabel.Text := 'Codex-Nutzungsdaten verfügbar.'
  else
    FDataStatusLabel.Text := 'Codex: noch keine Nutzungsdaten erhalten.';
  if FSettingsPanel.Visible then
    LayoutSettingsControls;
  {$IFDEF MSWINDOWS}
    if FTray <> nil then
      FTray.UpdateStatus(FSnapshot.StatusText);
  {$IFEND}
  FPaintBox.Repaint;
  UpdateExternalDisplay(True);
end;

procedure TMainForm.StartPublisher;
{$IFDEF MSWINDOWS}
var
  ErrorText: string;
{$IFEND}
begin
  {$IFDEF MSWINDOWS}
    if not FPublisher.Start(ErrorText) then
      FSnapshot.StatusText := 'Snapshot-Server: ' + ErrorText;
    FPublisher.Publish(FSnapshot);
  {$IFEND}
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

{$IFDEF ANDROID}
procedure TMainForm.RevealCompanion;
var
  WasHidden: Boolean;
begin
  WasHidden := FCompanionRevealUntil <= Now;
  FCompanionRevealUntil := IncMinute(Now, FSettings.OtherDisplayIdleMinutes);
  if WasHidden then
    FPaintBox.Repaint;
end;
{$IFEND}

procedure TMainForm.TimerTick(Sender: TObject);
var
  ExternalNow: Boolean;
begin
  if (FWorker <> nil) and FWorker.Finished and not FFetching then
    FreeAndNil(FWorker);
  FPlatform.Tick(FSettings.KeepAwakeStartHour, FSettings.KeepAwakeEndHour, FSettings.OtherDisplayIdleMinutes);
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
