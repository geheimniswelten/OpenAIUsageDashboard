unit Dashboard.Tray;

interface

uses
  System.SysUtils,
  Dashboard.Model
{$IF Defined(MSWINDOWS)}
  , Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Graphics
{$ENDIF}
  ;

type
  TTrayAction = (taToggleDashboard, taShowSettings, taCollectorMode, taExit);
  TTrayActionEvent = procedure(Sender: TObject; AAction: TTrayAction) of object;

  // The FMX application uses this wrapper on its main thread. VCL is confined
  // to the Windows tray component and its native popup menu.
  TDashboardTray = class
  private
    FVisible: Boolean;
    FShowRequested: Boolean;
    FRecoveryCount: Cardinal;
    FStatus: string;
    FHintText: string;
    FHasLimit: Boolean;
    FMaximumUsed: Double;
    FWarningActive: Boolean;
{$IF Defined(MSWINDOWS)}
    FTray: TTrayIcon;
    FNormalIcon, FWarningIcon: TIcon;
    FMenu: TPopupMenu;
    FDashboardItem: TMenuItem;
    FCollectorItem: TMenuItem;
    procedure MenuClick(Sender: TObject);
    procedure AddMenuItem(const ACaption: string; const AAction: TTrayAction);
{$ENDIF}
    procedure UpdateHint;
    procedure SetWarning(const AWarning: Boolean);
  public
    constructor Create(const AOnAction: TTrayActionEvent);
    destructor Destroy; override;
    function Show(out AError: string): Boolean;
    // Call periodically on the main thread. Explorer can lose an icon without
    // changing VCL's Visible flag; failed registrations must also be retried.
    // When Hide was requested, the hidden state already satisfies this call.
    function EnsureVisible(out AError: string): Boolean;
    procedure Hide;
    procedure UpdateStatus(const AStatus: string);
    procedure UpdateSnapshot(const ASnapshot: TUsageSnapshot);
    procedure SetCollectorMode(const AValue: Boolean);
    property Visible: Boolean read FVisible;
    property RecoveryCount: Cardinal read FRecoveryCount;
    property HintText: string read FHintText;
    property WarningActive: Boolean read FWarningActive;
  end;

implementation

uses
  System.Math,
  System.StrUtils
{$IF Defined(MSWINDOWS)}
  , Winapi.Windows,
  Winapi.Messages,
  Winapi.ShellAPI
{$ENDIF}
  ;

{$IF Defined(MSWINDOWS)}
{$R 'Dashboard.TrayIcons.res'}

const
  CActionMessage = WM_APP + $472;

type
  TCheckedTrayIcon = class(TTrayIcon)
  private
    FActionHandler: TTrayActionEvent;
    FActionSender: TObject;
  protected
    procedure WindowProc(var Message: TMessage); override;
  public
    function RegisterIcon(out AError: string; out ARecovered: Boolean): Boolean;
    procedure UnregisterIcon;
    procedure QueueAction(const AAction: TTrayAction);
  end;

function TCheckedTrayIcon.RegisterIcon(out AError: string;
  out ARecovered: Boolean): Boolean;
var
  ErrorCode: DWORD;
begin
  AError := '';
  ARecovered := False;
  SetLastError(ERROR_SUCCESS);
  Visible := True;
  // TCustomTrayIcon.SetVisible discards the NIM_ADD result. A successful
  // modification verifies that the Shell actually registered the icon before
  // the dashboard is allowed to hide.
  Result := Refresh(NIM_MODIFY);
  if not Result then
  begin
    // Explorer may have restarted or discarded the icon. Setting Visible to
    // True again does not send NIM_ADD while VCL still believes it is visible.
    // Reset that flag, re-add, then verify the Shell accepted the new icon.
    UnregisterIcon;
    SetLastError(ERROR_SUCCESS);
    Visible := True;
    Result := Refresh(NIM_MODIFY);
    ARecovered := Result;
  end;
  if not Result then
  begin
    ErrorCode := GetLastError;
    if FindWindow('Shell_TrayWnd', nil) = 0 then
      AError := 'Der Windows-Infobereich ist auf diesem Desktop nicht verfügbar'
    else
    begin
      AError := 'Tray-Symbol konnte nicht angezeigt werden';
      if ErrorCode <> ERROR_SUCCESS then
        AError := AError + ': ' + SysErrorMessage(ErrorCode) +
          ' ($' + IntToHex(ErrorCode, 8) + ')';
    end;
    UnregisterIcon;
  end;
end;

procedure TCheckedTrayIcon.UnregisterIcon;
begin
  try
    Visible := False;
  except
    // The setter already cleared its Visible flag. Explorer may have removed
    // the icon itself, in which case VCL raises for the failed NIM_DELETE.
  end;
end;

procedure TCheckedTrayIcon.QueueAction(const AAction: TTrayAction);
begin
  PostMessage(Data.Wnd, CActionMessage, Ord(AAction), 0);
end;

procedure TCheckedTrayIcon.WindowProc(var Message: TMessage);
var
  Handler: TTrayActionEvent;
  Sender: TObject;
begin
  // Only the left double-click toggles. Handling the first button-up as well
  // would toggle twice during one double-click and leave the window unchanged.
  if (Message.Msg = WM_SYSTEM_TRAY_MESSAGE) and
     (Message.LParam = WM_LBUTTONDBLCLK) then
    QueueAction(taToggleDashboard);
  if Message.Msg = CActionMessage then
  begin
    Message.Result := 0;
    Handler := FActionHandler;
    Sender := FActionSender;
    if Assigned(Handler) and (Message.WParam <= Ord(High(TTrayAction))) then
      Handler(Sender, TTrayAction(Message.WParam));
    // Beenden may free this component. Do not access it after the callback.
    Exit;
  end;
  // TTrayIcon handles its popup, click events and the first TaskbarCreated
  // recovery attempt. EnsureVisible verifies/retries if Explorer was not ready.
  inherited;
end;
{$ENDIF}

constructor TDashboardTray.Create(const AOnAction: TTrayActionEvent);
{$IF Defined(MSWINDOWS)}
var
  TrayIconHandle: HICON;
{$ENDIF}
begin
  inherited Create;
{$IF Defined(MSWINDOWS)}
  FTray := TCheckedTrayIcon.Create(nil);
  FNormalIcon := TIcon.Create;
  FWarningIcon := TIcon.Create;
  TCheckedTrayIcon(FTray).FActionHandler := AOnAction;
  TCheckedTrayIcon(FTray).FActionSender := Self;
  { Load the native small-icon size directly so the Shell does not have to
    shrink a large app icon, which blurs the knot and its small U badge. }
  TrayIconHandle := LoadImage(HInstance, 'MAINICON', IMAGE_ICON,
    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0);
  if TrayIconHandle = 0 then
    TrayIconHandle := CopyIcon(LoadIcon(0, IDI_APPLICATION));
  if TrayIconHandle <> 0 then
    FNormalIcon.Handle := TrayIconHandle;
  FTray.Icon.Assign(FNormalIcon);
  TrayIconHandle := LoadImage(HInstance, 'TRAYWARNING', IMAGE_ICON,
    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0);
  if TrayIconHandle = 0 then
    TrayIconHandle := CopyIcon(LoadIcon(0, IDI_WARNING));
  if TrayIconHandle <> 0 then
    FWarningIcon.Handle := TrayIconHandle;

  FMenu := TPopupMenu.Create(nil);
  AddMenuItem('Dashboard ausblenden', taToggleDashboard);
  FDashboardItem := FMenu.Items[0];
  FMenu.Items[0].Default := True;
  AddMenuItem('Einstellungen', taShowSettings);
  AddMenuItem('Nur Sammler', taCollectorMode);
  FCollectorItem := FMenu.Items[2];
  FMenu.Items.Add(NewLine);
  AddMenuItem('Beenden', taExit);
  FTray.PopupMenu := FMenu;
  UpdateStatus('');
{$ENDIF}
end;

destructor TDashboardTray.Destroy;
begin
{$IF Defined(MSWINDOWS)}
  if FTray <> nil then
  begin
    TCheckedTrayIcon(FTray).FActionHandler := nil;
    TCheckedTrayIcon(FTray).FActionSender := nil;
    FTray.OnClick := nil;
    FTray.PopupMenu := nil;
    Hide;
    FreeAndNil(FTray);
  end;
  FMenu.Free;
  FWarningIcon.Free;
  FNormalIcon.Free;
{$ENDIF}
  inherited;
end;

function TDashboardTray.Show(out AError: string): Boolean;
begin
  FShowRequested := True;
  Result := EnsureVisible(AError);
end;

function TDashboardTray.EnsureVisible(out AError: string): Boolean;
{$IF Defined(MSWINDOWS)}
var
  Recovered: Boolean;
{$ENDIF}
begin
  AError := '';
  if not FShowRequested then
    Exit(True);
{$IF Defined(MSWINDOWS)}
  try
    Result := TCheckedTrayIcon(FTray).RegisterIcon(AError, Recovered);
    if Result and Recovered then
      Inc(FRecoveryCount);
  except
    on E: Exception do
    begin
      Result := False;
      AError := 'Tray-Symbol konnte nicht angezeigt werden: ' + E.Message;
      TCheckedTrayIcon(FTray).UnregisterIcon;
    end;
  end;
{$ELSE}
  Result := False;
  AError := 'Das Tray-Symbol ist nur unter Windows verfügbar.';
{$ENDIF}
  FVisible := Result;
end;

procedure TDashboardTray.Hide;
begin
  FShowRequested := False;
{$IF Defined(MSWINDOWS)}
  if FTray <> nil then
    TCheckedTrayIcon(FTray).UnregisterIcon;
{$ENDIF}
  FVisible := False;
end;

procedure TDashboardTray.UpdateStatus(const AStatus: string);
const
  CurrentPrefix = 'Aktuell · ';
begin
  FStatus := Trim(AStatus);
  if SameText(FStatus, 'Aktuell') then
    FStatus := ''
  else if StartsText(CurrentPrefix, FStatus) then
    FStatus := Trim(Copy(FStatus, Length(CurrentPrefix) + 1, MaxInt));
  UpdateHint;
end;

procedure TDashboardTray.UpdateHint;
begin
  FHintText := 'OpenAI-Nutzung';
  if FHasLimit then
    FHintText := FHintText + ' · ' + FormatFloat('0.##', FMaximumUsed) + ' % verbraucht';
  if FStatus <> '' then
    FHintText := FHintText + #13#10 + FStatus;
  FHintText := Copy(FHintText, 1, 127);
{$IF Defined(MSWINDOWS)}
  FTray.Hint := FHintText;
{$ENDIF}
end;

procedure TDashboardTray.SetWarning(const AWarning: Boolean);
begin
  if FWarningActive = AWarning then Exit;
{$IF Defined(MSWINDOWS)}
  if AWarning then
    FTray.Icon.Assign(FWarningIcon)
  else
    FTray.Icon.Assign(FNormalIcon);
{$ENDIF}
  FWarningActive := AWarning;
end;

procedure TDashboardTray.UpdateSnapshot(const ASnapshot: TUsageSnapshot);
var
  Limit: TRateLimitWindow;
  Status: string;

  procedure Consider(const AUsed: Double);
  begin
    if IsNan(AUsed) or IsInfinite(AUsed) or (AUsed < 0) then Exit;
    if not FHasLimit or (AUsed > FMaximumUsed) then
      FMaximumUsed := AUsed;
    FHasLimit := True;
  end;

begin
  FHasLimit := False;
  FMaximumUsed := 0;
  if not IsNan(ASnapshot.SpendingLimit) and not IsInfinite(ASnapshot.SpendingLimit) and
    (ASnapshot.SpendingLimit > 0) and not IsNan(ASnapshot.PeriodCost) and
    not IsInfinite(ASnapshot.PeriodCost) then
    Consider(100 * (ASnapshot.PeriodCost / ASnapshot.SpendingLimit));
  if ASnapshot.CodexRateLimitsAvailable then
    for Limit in ASnapshot.RateLimits do
      if Limit.Available then
        Consider(Limit.UsedPercent);
  SetWarning(FHasLimit and (FMaximumUsed > 90));
  Status := ASnapshot.StatusText;
  if ASnapshot.CodexError <> '' then
  begin
    if (Trim(Status) = '') or StartsText('Aktuell', Status) then
      Status := 'Codex: ' + ASnapshot.CodexError
    else if not ContainsText(Status, ASnapshot.CodexError) then
      Status := Status + ' · Codex: ' + ASnapshot.CodexError;
  end;
  UpdateStatus(Status);
end;

procedure TDashboardTray.SetCollectorMode(const AValue: Boolean);
begin
{$IF Defined(MSWINDOWS)}
  if AValue then
    FDashboardItem.Caption := 'Dashboard anzeigen'
  else
    FDashboardItem.Caption := 'Dashboard ausblenden';
  FCollectorItem.Checked := AValue;
{$ENDIF}
end;

{$IF Defined(MSWINDOWS)}
procedure TDashboardTray.AddMenuItem(const ACaption: string;
  const AAction: TTrayAction);
var
  Item: TMenuItem;
begin
  Item := TMenuItem.Create(FMenu);
  Item.Caption := ACaption;
  Item.Tag := Ord(AAction);
  Item.OnClick := MenuClick;
  FMenu.Items.Add(Item);
end;

procedure TDashboardTray.MenuClick(Sender: TObject);
begin
  TCheckedTrayIcon(FTray).QueueAction(TTrayAction(TMenuItem(Sender).Tag));
end;
{$ENDIF}

end.
