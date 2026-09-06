unit Dashboard.Tray;

interface

uses
  System.SysUtils
{$IF Defined(MSWINDOWS)}
  , Vcl.ExtCtrls,
  Vcl.Menus
{$ENDIF}
  ;

type
  TTrayAction = (taShowDashboard, taShowSettings, taCollectorMode, taExit);
  TTrayActionEvent = procedure(Sender: TObject; AAction: TTrayAction) of object;

  // The FMX application uses this wrapper on its main thread. VCL is confined
  // to the Windows tray component and its native popup menu.
  TDashboardTray = class
  private
    FVisible: Boolean;
    FCollectorMode: Boolean;
    FStatus: string;
{$IF Defined(MSWINDOWS)}
    FTray: TTrayIcon;
    FMenu: TPopupMenu;
    FCollectorItem: TMenuItem;
    procedure TrayClick(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    procedure AddMenuItem(const ACaption: string; const AAction: TTrayAction);
{$ENDIF}
  public
    constructor Create(const AOnAction: TTrayActionEvent);
    destructor Destroy; override;
    function Show(out AError: string): Boolean;
    procedure Hide;
    procedure UpdateStatus(const AStatus: string);
    procedure SetCollectorMode(const AValue: Boolean);
    property Visible: Boolean read FVisible;
  end;

implementation

{$IF Defined(MSWINDOWS)}
uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.ShellAPI;

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
    function RegisterIcon(out AError: string): Boolean;
    procedure UnregisterIcon;
    procedure QueueAction(const AAction: TTrayAction);
  end;

function TCheckedTrayIcon.RegisterIcon(out AError: string): Boolean;
var
  ErrorCode: DWORD;
begin
  AError := '';
  SetLastError(ERROR_SUCCESS);
  Visible := True;
  // TCustomTrayIcon.SetVisible discards the NIM_ADD result. A successful
  // modification verifies that the Shell actually registered the icon before
  // the dashboard is allowed to hide.
  Result := Refresh(NIM_MODIFY);
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
  // TTrayIcon handles its popup, click events and TaskbarCreated recovery.
  inherited;
end;
{$ENDIF}

constructor TDashboardTray.Create(const AOnAction: TTrayActionEvent);
{$IF Defined(MSWINDOWS)}
var
  SharedIcon: HICON;
{$ENDIF}
begin
  inherited Create;
{$IF Defined(MSWINDOWS)}
  FTray := TCheckedTrayIcon.Create(nil);
  TCheckedTrayIcon(FTray).FActionHandler := AOnAction;
  TCheckedTrayIcon(FTray).FActionSender := Self;
  FTray.OnClick := TrayClick;
  SharedIcon := LoadIcon(HInstance, 'MAINICON');
  if SharedIcon = 0 then
    SharedIcon := LoadIcon(0, IDI_APPLICATION);
  if SharedIcon <> 0 then
    FTray.Icon.Handle := CopyIcon(SharedIcon);

  FMenu := TPopupMenu.Create(nil);
  AddMenuItem('Dashboard anzeigen', taShowDashboard);
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
{$ENDIF}
  inherited;
end;

function TDashboardTray.Show(out AError: string): Boolean;
begin
  AError := '';
{$IF Defined(MSWINDOWS)}
  try
    Result := TCheckedTrayIcon(FTray).RegisterIcon(AError);
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
{$IF Defined(MSWINDOWS)}
  if FTray <> nil then
    TCheckedTrayIcon(FTray).UnregisterIcon;
{$ENDIF}
  FVisible := False;
end;

procedure TDashboardTray.UpdateStatus(const AStatus: string);
{$IF Defined(MSWINDOWS)}
var
  Tip: string;
{$ENDIF}
begin
  FStatus := AStatus;
{$IF Defined(MSWINDOWS)}
  Tip := 'OpenAI-Nutzung';
  if FCollectorMode then
    Tip := Tip + ' · Nur Sammler';
  if FStatus <> '' then
    Tip := Tip + #13#10 + FStatus;
  FTray.Hint := Copy(Tip, 1, 127);
{$ENDIF}
end;

procedure TDashboardTray.SetCollectorMode(const AValue: Boolean);
begin
  FCollectorMode := AValue;
{$IF Defined(MSWINDOWS)}
  FCollectorItem.Checked := AValue;
{$ENDIF}
  UpdateStatus(FStatus);
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

procedure TDashboardTray.TrayClick(Sender: TObject);
begin
  TCheckedTrayIcon(FTray).QueueAction(taShowDashboard);
end;

procedure TDashboardTray.MenuClick(Sender: TObject);
begin
  TCheckedTrayIcon(FTray).QueueAction(TTrayAction(TMenuItem(Sender).Tag));
end;
{$ENDIF}

end.
