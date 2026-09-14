unit Dashboard.Platform;

interface


uses
  System.Types,
  System.UITypes,
  FMX.Forms,
  FMX.Graphics,
  Dashboard.DisplayPolicy
{$IF Defined(MSWINDOWS)}
  , System.Generics.Collections,
  Winapi.Windows,
  Winapi.Messages
{$ENDIF}
{$IF Defined(ANDROID)}
  , Androidapi.JNI.App,
  Androidapi.JNI.Hardware,
  Androidapi.JNI.GraphicsContentViewText,
  Androidapi.JNI.Widget,
  Androidapi.JNIBridge,
  Androidapi.Jni
{$ENDIF}
  ;

type
{$IF Defined(ANDROID)}
  JDashboardPresentation = interface;

  JDashboardPresentationClass = interface(JDialogClass)
    ['{7E9B92B4-459E-4AAC-80D7-317F77AE7447}']
    {class} function init(outerContext: JContext;
      display: JDisplay): JDashboardPresentation; cdecl; overload;
    {class} function init(outerContext: JContext;
      display: JDisplay; theme: Integer): JDashboardPresentation; cdecl; overload;
  end;

  [JavaSignature('android/app/Presentation')]
  JDashboardPresentation = interface(JDialog)
    ['{34AAF5D0-8F3B-43F2-9FF5-0265EF855196}']
    function getDisplay: JDisplay; cdecl;
  end;

  TJDashboardPresentation = class(
    TJavaGenericImport<JDashboardPresentationClass, JDashboardPresentation>);
{$ENDIF}

  TPlatformCoordinator = class
  private
    FMainForm: TCommonCustomForm;
    FKeepAwake: Boolean;
    FTargetDisplay: Integer;
    FExternalSize: TSize;
{$IF Defined(MSWINDOWS)}
    FBlackForms: TObjectList<TForm>;
    FCollectorOnly: Boolean;
    FKnownDisplayCount: Integer;
    FDisplaySignature: string;
    FLastInputTick: Cardinal;
    FRevealUntilTick: UInt64;
    FLastKeepAwakeRefreshTick: UInt64;
    FAppliedExecutionState: EXECUTION_STATE;
    FLastPowerErrorTick: UInt64;
    FDisplayPreference: TDashboardDisplayPreference;
    FRequestedDisplay: Integer;
    FMessageWindow: HWND;
    FDisplayRefreshAfterTick: UInt64;
    FDisplayRestoreUntilTick: UInt64;
    FResumePending: Boolean;
    procedure QueueWindowsDisplayRefresh;
    procedure PlaceWindowsDashboard;
    function WindowsDisplayDevice(const AIndex: Integer): string;
    procedure RebuildWindowsDisplays;
    procedure SetWindowsBlackout(const ABlack: Boolean);
    function WindowsDisplaySignature: string;
{$ENDIF}
{$IF Defined(ANDROID)}
    FDisplayManager: JDisplayManager;
    FPresentations: TArray<JDashboardPresentation>;
    FImages: TArray<JImageView>;
    FDisplayIds: TArray<Integer>;
    FExternalImageIndex: Integer;
    FExternalBitmap: JBitmap;
    FPreviousExternalBitmap: JBitmap;
    procedure ClearAndroidDisplays;
    procedure RebuildAndroidDisplays;
    function AndroidDisplaysChanged: Boolean;
    procedure SetAndroidKeepAwake(const AEnabled: Boolean);
{$ENDIF}
  protected
    procedure SetKeepAwake(const AEnabled: Boolean);
{$IF Defined(MSWINDOWS)}
    procedure WindowsMessage(var AMessage: TMessage);
    function ApplyWindowsExecutionState(const AFlags: EXECUTION_STATE): Boolean; virtual;
    procedure WakeWindowsDisplays; virtual;
    procedure LogWindowsEvent(const AText: string); virtual;
{$ENDIF}
  public
    constructor Create(const AMainForm: TCommonCustomForm);
    destructor Destroy; override;
    procedure PlaceDashboard(const ARequestedDisplay: Integer);
{$IF Defined(MSWINDOWS)}
    procedure SetCollectorOnly(const AEnabled: Boolean);
{$ENDIF}
    procedure GetDisplayChoices(out AValues: TArray<Integer>;
      out ACaptions: TArray<string>);
    procedure Tick(const AStartHour, AEndHour, AIdleMinutes: Integer);
    procedure NotifyInteraction(const AIdleMinutes: Integer);
    function ExternalDisplayActive: Boolean;
    function ExternalRenderSize: TSize;
    procedure UpdateExternalBitmap(const ABitmap: FMX.Graphics.TBitmap);
    property KeepAwake: Boolean read FKeepAwake;
    property TargetDisplay: Integer read FTargetDisplay;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.Math,
  FMX.Types
{$IF Defined(MSWINDOWS)}
  , System.IOUtils,
  Winapi.MultiMon,
  FMX.Platform.Win
{$ENDIF}
{$IF Defined(ANDROID)}
  , Androidapi.Helpers,
  Androidapi.JNI.JavaTypes,
  Androidapi.JNI.Os,
  FMX.Helpers.Android
{$ENDIF}
  ;

{ TPlatformCoordinator }

constructor TPlatformCoordinator.Create(const AMainForm: TCommonCustomForm);
{$IF Defined(MSWINDOWS)}
var
  Input: TLastInputInfo;
{$ENDIF}
{$IF Defined(ANDROID)}
var
  Service: JObject;
{$ENDIF}
begin
  inherited Create;
  FMainForm := AMainForm;
  FTargetDisplay := -1;
  FExternalSize := TSize.Create(0, 0);
{$IF Defined(MSWINDOWS)}
  FBlackForms := TObjectList<TForm>.Create(True);
  FKnownDisplayCount := -1;
  FDisplayPreference := TDashboardDisplayPreference.Create(-1);
  FRequestedDisplay := -1;
  { A hidden top-level window receives sent broadcasts too. Application.OnMessage
    only observes queued messages; VCL application events do not belong to FMX. }
  FMessageWindow := AllocateHWnd(WindowsMessage);
  FillChar(Input, SizeOf(Input), 0);
  Input.cbSize := SizeOf(Input);
  if GetLastInputInfo(Input) then
    FLastInputTick := Input.dwTime;
{$ENDIF}
{$IF Defined(ANDROID)}
  FExternalImageIndex := -1;
  Service := TAndroidHelper.Activity.getSystemService(TJContext.JavaClass.DISPLAY_SERVICE);
  if Service <> nil then
    FDisplayManager := TJDisplayManager.Wrap(Service);
{$ENDIF}
end;

destructor TPlatformCoordinator.Destroy;
begin
{$IF Defined(MSWINDOWS)}
  if FMessageWindow <> 0 then
    DeallocateHWnd(FMessageWindow);
  FMessageWindow := 0;
  ApplyWindowsExecutionState(ES_CONTINUOUS);
  FBlackForms.Free;
{$ELSE}
  SetKeepAwake(False);
{$ENDIF}
{$IF Defined(ANDROID)}
  ClearAndroidDisplays;
  if FExternalBitmap <> nil then
    FExternalBitmap.recycle;
  if FPreviousExternalBitmap <> nil then
    FPreviousExternalBitmap.recycle;
  FExternalBitmap := nil;
  FPreviousExternalBitmap := nil;
{$ENDIF}
  inherited;
end;

procedure TPlatformCoordinator.SetKeepAwake(const AEnabled: Boolean);
{$IF Defined(MSWINDOWS)}
var
  NowTick: UInt64;
  Flags: EXECUTION_STATE;
  WakeDisplay, StateChanged: Boolean;
{$ENDIF}
begin
{$IF Defined(MSWINDOWS)}
  { The dashboard's morning timer needs a running PC even while its display
    request is released overnight. Collector-only mode keeps its old schedule. }
  Flags := ES_CONTINUOUS;
  if not FCollectorOnly or AEnabled then
    Flags := Flags or ES_SYSTEM_REQUIRED;
  if AEnabled and not FCollectorOnly then
    Flags := Flags or ES_DISPLAY_REQUIRED;
  NowTick := GetTickCount64;
  StateChanged := (Flags <> FAppliedExecutionState) or (FKeepAwake <> AEnabled);
  WakeDisplay := AEnabled and not FCollectorOnly and
    (not FKeepAwake or FResumePending);
  if StateChanged or FResumePending or
     (NowTick - FLastKeepAwakeRefreshTick >= 60000) then
  begin
    if not ApplyWindowsExecutionState(Flags) then
    begin
      if (FLastPowerErrorTick = 0) or (NowTick - FLastPowerErrorTick >= 60000) then
      begin
        LogWindowsEvent('SetThreadExecutionState failed; flags=$' + IntToHex(Flags, 8));
        FLastPowerErrorTick := NowTick;
      end;
      Exit;  { Do not mark an unsuccessful request as applied; retry next tick. }
    end;
    FAppliedExecutionState := Flags;
    FLastKeepAwakeRefreshTick := NowTick;
    FLastPowerErrorTick := 0;
    if StateChanged or FResumePending then
      LogWindowsEvent(Format('KeepAwake=%s CollectorOnly=%s flags=$%s Resume=%s',
        [BoolToStr(AEnabled, True), BoolToStr(FCollectorOnly, True),
         IntToHex(Flags, 8), BoolToStr(FResumePending, True)]));
  end;
  FKeepAwake := AEnabled;
  FResumePending := False;
  if WakeDisplay then
    WakeWindowsDisplays;
{$ELSE}
  if FKeepAwake = AEnabled then
    Exit;
{$ENDIF}
{$IF Defined(ANDROID)}
  SetAndroidKeepAwake(AEnabled);
{$ENDIF}
  FKeepAwake := AEnabled;
end;

{$IF Defined(MSWINDOWS)}
procedure TPlatformCoordinator.SetCollectorOnly(const AEnabled: Boolean);
begin
  if FCollectorOnly = AEnabled then
    Exit;
  FCollectorOnly := AEnabled;
  { Reapply even if the time window itself did not change. }
  FResumePending := True;
  SetKeepAwake(FKeepAwake);
  FBlackForms.Clear;
  FKnownDisplayCount := -1;
  FDisplaySignature := '';
end;
{$ENDIF}

procedure TPlatformCoordinator.PlaceDashboard(const ARequestedDisplay: Integer);
begin
{$IF Defined(MSWINDOWS)}
  if FCollectorOnly then
    Exit;
  if FRequestedDisplay <> ARequestedDisplay then
  begin
    FRequestedDisplay := ARequestedDisplay;
    FDisplayPreference := TDashboardDisplayPreference.Create(ARequestedDisplay);
  end;
  FMainForm.BorderStyle := TFmxFormBorderStyle.None;
  FMainForm.FormStyle := TFormStyle.StayOnTop;
  FMainForm.Position := TFormPosition.Designed;
  Screen.UpdateDisplayInformation;
  RebuildWindowsDisplays;
{$ELSE}
  FTargetDisplay := ARequestedDisplay;
  FMainForm.BorderStyle := TFmxFormBorderStyle.None;
  FMainForm.FullScreen := True;
{$IF Defined(ANDROID)}
  RebuildAndroidDisplays;
{$ENDIF}
{$ENDIF}
end;

procedure TPlatformCoordinator.GetDisplayChoices(out AValues: TArray<Integer>;
  out ACaptions: TArray<string>);
{$IF Defined(MSWINDOWS)}
var
  I: Integer;
  Bounds: TRect;
  Description: string;
{$ENDIF}
{$IF Defined(ANDROID)}
var
  Displays: TJavaObjectArray<JDisplay>;
  I: Integer;
  Point: JPoint;
  DisplayName: string;
{$ENDIF}
begin
{$IF Defined(MSWINDOWS)}
  SetLength(AValues, Screen.DisplayCount + 1);
  SetLength(ACaptions, Screen.DisplayCount + 1);
  AValues[0] := -1;
  ACaptions[0] := 'Automatisch · externer Bildschirm';
  for I := 0 to Screen.DisplayCount - 1 do
  begin
    Bounds := Screen.Displays[I].PhysicalBounds;
    Description := Format('Monitor %d · %d×%d', [I + 1,
      Bounds.Width, Bounds.Height]);
    if Screen.Displays[I].Primary then
      Description := Description + ' · Haupt';
    AValues[I + 1] := I;
    ACaptions[I + 1] := Description;
  end;
{$ELSEIF Defined(ANDROID)}
  Displays := nil;
  try
    if FDisplayManager <> nil then
      Displays := FDisplayManager.getDisplays(
        TJDisplayManager.JavaClass.DISPLAY_CATEGORY_PRESENTATION);
  except
    Displays := nil;
  end;
  if Displays = nil then
  begin
    SetLength(AValues, 2);
    SetLength(ACaptions, 2);
  end
  else
  begin
    SetLength(AValues, Displays.Length + 2);
    SetLength(ACaptions, Displays.Length + 2);
  end;
  AValues[0] := -1;
  ACaptions[0] := 'Automatisch · externer Bildschirm';
  AValues[1] := -2;
  ACaptions[1] := 'Tablet · integrierter Bildschirm';
  if Displays <> nil then
    for I := 0 to Displays.Length - 1 do
    begin
      Point := TJPoint.Create;
      Displays.Items[I].getRealSize(Point);
      DisplayName := JStringToString(Displays.Items[I].getName);
      if DisplayName = '' then
        DisplayName := 'Externer Bildschirm ' + IntToStr(I + 1);
      AValues[I + 2] := Displays.Items[I].getDisplayId;
      ACaptions[I + 2] := Format('%s · %d×%d', [DisplayName, Point.x, Point.y]);
    end;
{$ELSE}
  SetLength(AValues, 1);
  SetLength(ACaptions, 1);
  AValues[0] := -1;
  ACaptions[0] := 'Automatisch';
{$ENDIF}
end;

procedure TPlatformCoordinator.Tick(const AStartHour, AEndHour,
  AIdleMinutes: Integer);
{$IF Defined(MSWINDOWS)}
var
  Input: TLastInputInfo;
  NowTick: UInt64;
{$ENDIF}
begin
  SetKeepAwake(InKeepAwakeWindow(Now, AStartHour, AEndHour));
{$IF Defined(MSWINDOWS)}
  { The collector continues to run, but never takes ownership of any monitor. }
  if FCollectorOnly then
    Exit;
  NowTick := GetTickCount64;
  if (FDisplayRefreshAfterTick <> 0) and (NowTick >= FDisplayRefreshAfterTick) then
  begin
    FDisplayRefreshAfterTick := 0;
    Screen.UpdateDisplayInformation;
    RebuildWindowsDisplays;
  end
  else if (FDisplayRefreshAfterTick = 0) and
    ((Screen.DisplayCount <> FKnownDisplayCount) or
     (WindowsDisplaySignature <> FDisplaySignature)) then
    RebuildWindowsDisplays;
  { Some display drivers/Windows restore window bounds after WM_DISPLAYCHANGE.
    Reassert native fullscreen bounds briefly, without stealing focus. }
  if (FDisplayRefreshAfterTick = 0) and (FDisplayRestoreUntilTick <> 0) then
  begin
    PlaceWindowsDashboard;
    if NowTick >= FDisplayRestoreUntilTick then
      FDisplayRestoreUntilTick := 0;
  end;
  FillChar(Input, SizeOf(Input), 0);
  Input.cbSize := SizeOf(Input);
  NowTick := GetTickCount64;
  if GetLastInputInfo(Input) and (Input.dwTime <> FLastInputTick) then
  begin
    FLastInputTick := Input.dwTime;
    FRevealUntilTick := NowTick + UInt64(Max(1, AIdleMinutes)) * 60000;
    SetWindowsBlackout(False);
  end;
  if (FRevealUntilTick = 0) or (NowTick >= FRevealUntilTick) then
    SetWindowsBlackout(True);
{$ENDIF}
{$IF Defined(ANDROID)}
  if AndroidDisplaysChanged then
    RebuildAndroidDisplays;
  { New presentation windows also need the current keep-awake state. }
  SetAndroidKeepAwake(FKeepAwake);
{$ENDIF}
end;

procedure TPlatformCoordinator.NotifyInteraction(const AIdleMinutes: Integer);
begin
{$IF Defined(MSWINDOWS)}
  FRevealUntilTick := GetTickCount64 + UInt64(Max(1, AIdleMinutes)) * 60000;
  SetWindowsBlackout(False);
{$ENDIF}
end;

function TPlatformCoordinator.ExternalDisplayActive: Boolean;
begin
{$IF Defined(ANDROID)}
  Result := (FExternalImageIndex >= 0) and
    (FExternalImageIndex < Length(FPresentations)) and
    (FPresentations[FExternalImageIndex] <> nil);
{$ELSE}
  Result := False;
{$ENDIF}
end;

function TPlatformCoordinator.ExternalRenderSize: TSize;
begin
  Result := FExternalSize;
end;

procedure TPlatformCoordinator.UpdateExternalBitmap(
  const ABitmap: FMX.Graphics.TBitmap);
{$IF Defined(ANDROID)}
var
  ImageIndex: Integer;
  NewBitmap, OldBitmap, StaleBitmap: JBitmap;
{$ENDIF}
begin
{$IF Defined(ANDROID)}
  ImageIndex := FExternalImageIndex;
  if (ImageIndex < 0) or (ImageIndex >= Length(FImages)) or
     (FImages[ImageIndex] = nil) or (ABitmap = nil) or
     ABitmap.IsEmpty then
    Exit;
  NewBitmap := nil;
  try
    NewBitmap := TJBitmap.JavaClass.createBitmap(ABitmap.Width, ABitmap.Height,
      TJBitmap_Config.JavaClass.ARGB_8888);
    if not BitmapToJBitmap(ABitmap, NewBitmap) then
    begin
      NewBitmap.recycle;
      NewBitmap := nil;
      Exit;
    end;
    FImages[ImageIndex].setImageBitmap(NewBitmap);
    StaleBitmap := FPreviousExternalBitmap;
    OldBitmap := FExternalBitmap;
    FPreviousExternalBitmap := OldBitmap;
    FExternalBitmap := NewBitmap;
    NewBitmap := nil;
    { Keep the immediately preceding bitmap alive for another frame. }
    if StaleBitmap <> nil then
      StaleBitmap.recycle;
  except
    { A display can disappear between enumeration and setImageBitmap.  The
      next timer tick rebuilds the presentation list. }
  end;
  if NewBitmap <> nil then
    NewBitmap.recycle;
{$ENDIF}
end;

{$IF Defined(MSWINDOWS)}
function TPlatformCoordinator.ApplyWindowsExecutionState(
  const AFlags: EXECUTION_STATE): Boolean;
begin
  Result := SetThreadExecutionState(AFlags) <> 0;
end;

procedure TPlatformCoordinator.LogWindowsEvent(const AText: string);
var
  FileName: string;
begin
  OutputDebugString(PChar('OpenAIUsageDashboard: ' + AText));
  try
    FileName := TPath.Combine(TPath.GetTempPath, 'OpenAIUsageDashboard-display.log');
    if TFile.Exists(FileName) and (TFile.GetSize(FileName) >= 1024 * 1024) then
    begin
      if TFile.Exists(FileName + '.previous') then
        TFile.Delete(FileName + '.previous');
      TFile.Move(FileName, FileName + '.previous');
    end;
    TFile.AppendAllText(FileName, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) +
      ' ' + AText + sLineBreak, TEncoding.UTF8);
  except
    { Diagnostics must not prevent wake-up/placement on a read-only profile. }
  end;
end;

procedure TPlatformCoordinator.QueueWindowsDisplayRefresh;
begin
  FDisplayRefreshAfterTick := GetTickCount64 + 750;
  FDisplayRestoreUntilTick := FDisplayRefreshAfterTick + 5000;
end;

procedure TPlatformCoordinator.WindowsMessage(var AMessage: TMessage);
begin
  case AMessage.Msg of
    WM_DISPLAYCHANGE, WM_DEVICECHANGE:
      QueueWindowsDisplayRefresh;
    WM_SETTINGCHANGE:
      if (AMessage.WParam = SPI_SETWORKAREA) or (AMessage.WParam = 0) then
        QueueWindowsDisplayRefresh;
    WM_POWERBROADCAST:
      if AMessage.WParam = PBT_APMSUSPEND then
        LogWindowsEvent('Windows suspend notification')
      else if (AMessage.WParam = PBT_APMRESUMEAUTOMATIC) or
         (AMessage.WParam = PBT_APMRESUMESUSPEND) or
         (AMessage.WParam = PBT_APMRESUMECRITICAL) then
      begin
        FResumePending := True;
        QueueWindowsDisplayRefresh;
      end;
  end;
  AMessage.Result := DefWindowProc(FMessageWindow, AMessage.Msg,
    AMessage.WParam, AMessage.LParam);
end;

procedure TPlatformCoordinator.WakeWindowsDisplays;
begin
  { Keep the idle timer reset AND explicitly request display power-on. Use our
    own window's default procedure, so no broadcast can block on another app. }
  DefWindowProc(FMessageWindow, WM_SYSCOMMAND, SC_MONITORPOWER, -1);
  LogWindowsEvent('Display power-on requested (SC_MONITORPOWER -1)');
  QueueWindowsDisplayRefresh;
end;

function TPlatformCoordinator.WindowsDisplayDevice(const AIndex: Integer): string;
var
  Info: TMonitorInfoEx;
  Device: TDisplayDevice;
  DeviceIndex: DWORD;
begin
  Result := '';
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if not GetMonitorInfo(HMONITOR(Screen.Displays[AIndex].Id), @Info) then
    Exit;
  DeviceIndex := 0;
  repeat
    FillChar(Device, SizeOf(Device), 0);
    Device.cb := SizeOf(Device);
    if not EnumDisplayDevices(@Info.szDevice[0], DeviceIndex, Device,
      EDD_GET_DEVICE_INTERFACE_NAME) then
      Break;
    if (Device.StateFlags and DISPLAY_DEVICE_ATTACHED_TO_DESKTOP <> 0) and
       (Device.DeviceID[0] <> #0) then
      Exit(string(Device.DeviceID));
    Inc(DeviceIndex);
  until False;
  { Remote/virtual displays may not expose a monitor device interface. }
  Result := string(Info.szDevice);
end;

procedure TPlatformCoordinator.PlaceWindowsDashboard;
var
  Display: TDisplay;
  Bounds: TRect;
begin
  if FCollectorOnly or (FTargetDisplay < 0) or
     (FTargetDisplay >= Screen.DisplayCount) then
    Exit;
  Display := Screen.Displays[FTargetDisplay];
  FMainForm.WindowState := TWindowState.wsNormal;
  FMainForm.SetBoundsF(Display.Bounds);
  Bounds := Display.PhysicalBounds;
  { SetBoundsF can be a no-op if FMX still caches the old bounds after Windows
    moved a borderless window. Native physical bounds also handle mixed DPI. }
  SetWindowPos(FormToHWND(FMainForm), 0, Bounds.Left, Bounds.Top,
    Bounds.Width, Bounds.Height, SWP_NOACTIVATE or SWP_NOZORDER);
end;

function TPlatformCoordinator.WindowsDisplaySignature: string;
var
  I: Integer;
  Bounds: TRectF;
begin
  Result := IntToStr(Screen.DisplayCount);
  for I := 0 to Screen.DisplayCount - 1 do
  begin
    Bounds := Screen.Displays[I].Bounds;
    Result := Result + Format('|%d:%s:%s:%d:%d:%d:%d:%.3f',
      [I, WindowsDisplayDevice(I), BoolToStr(Screen.Displays[I].Primary, True),
       Round(Bounds.Left), Round(Bounds.Top), Round(Bounds.Right),
       Round(Bounds.Bottom), Screen.Displays[I].Scale]);
  end;
end;

procedure TPlatformCoordinator.RebuildWindowsDisplays;
var
  I, PrimaryIndex: Integer;
  Devices: TArray<string>;
  BlackForm: TForm;
  Display: TDisplay;
  WindowHandle: HWND;
  ExtendedStyle: NativeInt;
begin
  FBlackForms.Clear;
  FKnownDisplayCount := Screen.DisplayCount;
  FDisplaySignature := WindowsDisplaySignature;
  if FCollectorOnly then
    Exit;
  SetLength(Devices, FKnownDisplayCount);
  PrimaryIndex := 0;
  for I := 0 to FKnownDisplayCount - 1 do
  begin
    Devices[I] := WindowsDisplayDevice(I);
    if Screen.Displays[I].Primary then
      PrimaryIndex := I;
  end;
  FTargetDisplay := FDisplayPreference.Resolve(Devices, PrimaryIndex);
  LogWindowsEvent(Format('Display layout: target=%d topology=%s',
    [FTargetDisplay, FDisplaySignature]));
  if FTargetDisplay < 0 then
    Exit;
  PlaceWindowsDashboard;
  for I := 0 to FKnownDisplayCount - 1 do
    if I <> FTargetDisplay then
    begin
      Display := Screen.Displays[I];
      BlackForm := TForm.CreateNew(nil);
      BlackForm.Caption := 'OpenAI Dashboard · abgedunkelter Bildschirm';
      BlackForm.BorderStyle := TFmxFormBorderStyle.None;
      BlackForm.FormStyle := TFormStyle.StayOnTop;
      BlackForm.Position := TFormPosition.Designed;
      BlackForm.Fill.Kind := TBrushKind.Solid;
      BlackForm.Fill.Color := TAlphaColorRec.Black;
      BlackForm.SetBoundsF(Display.Bounds);
      WindowHandle := FormToHWND(BlackForm);
      ExtendedStyle := GetWindowLongPtr(WindowHandle, GWL_EXSTYLE);
      SetWindowLongPtr(WindowHandle, GWL_EXSTYLE, ExtendedStyle or
        WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW);
      FBlackForms.Add(BlackForm);
      if (FRevealUntilTick = 0) or (GetTickCount64 >= FRevealUntilTick) then
        BlackForm.Show;
    end;
end;

procedure TPlatformCoordinator.SetWindowsBlackout(const ABlack: Boolean);
var
  Form: TForm;
begin
  for Form in FBlackForms do
    if ABlack then
    begin
      if not Form.Visible then
        Form.Show;
    end
    else if Form.Visible then
      Form.Hide;
end;
{$ENDIF}

{$IF Defined(ANDROID)}
procedure TPlatformCoordinator.ClearAndroidDisplays;
var
  I: Integer;
begin
  for I := 0 to High(FPresentations) do
    if FPresentations[I] <> nil then
      try
        FPresentations[I].dismiss;
      except
        { The display may already have been detached. }
      end;
  FPresentations := nil;
  FImages := nil;
  FDisplayIds := nil;
  FExternalImageIndex := -1;
  FExternalSize := TSize.Create(0, 0);
end;

function TPlatformCoordinator.AndroidDisplaysChanged: Boolean;
var
  Displays: TJavaObjectArray<JDisplay>;
  I: Integer;
begin
  try
    if FDisplayManager = nil then
      Exit(False);
    Displays := FDisplayManager.getDisplays(
      TJDisplayManager.JavaClass.DISPLAY_CATEGORY_PRESENTATION);
    if Displays = nil then
      Exit(Length(FDisplayIds) <> 0);
    if Displays.Length <> Length(FDisplayIds) then
      Exit(True);
    for I := 0 to Displays.Length - 1 do
      if Displays.Items[I].getDisplayId <> FDisplayIds[I] then
        Exit(True);
    Result := False;
  except
    Result := True;
  end;
end;

procedure TPlatformCoordinator.RebuildAndroidDisplays;
const
  UiFlags = $00001000 { immersive sticky } or $00000004 { fullscreen } or
    $00000002 { hide navigation } or $00000400 { layout fullscreen } or
    $00000200 { layout hide navigation } or $00000100 { layout stable };
var
  Displays: TJavaObjectArray<JDisplay>;
  I, W, H, TargetIndex: Integer;
  Point: JPoint;
  View: JImageView;
  Presentation: JDashboardPresentation;
begin
  ClearAndroidDisplays;
  if FDisplayManager = nil then
    Exit;
  try
    Displays := FDisplayManager.getDisplays(
      TJDisplayManager.JavaClass.DISPLAY_CATEGORY_PRESENTATION);
  except
    Exit;
  end;
  if (Displays = nil) or (Displays.Length = 0) then
    Exit;
  try
    TargetIndex := -1;
    if FTargetDisplay <> -2 then
      if FTargetDisplay < 0 then
        TargetIndex := 0
      else
        for I := 0 to Displays.Length - 1 do
          if Displays.Items[I].getDisplayId = FTargetDisplay then
          begin
            TargetIndex := I;
            Break;
          end;
    SetLength(FPresentations, Displays.Length);
    SetLength(FImages, Displays.Length);
    SetLength(FDisplayIds, Displays.Length);
    for I := 0 to Displays.Length - 1 do
    begin
      FDisplayIds[I] := Displays.Items[I].getDisplayId;
      Presentation := TJDashboardPresentation.JavaClass.init(
        TAndroidHelper.Activity, Displays.Items[I]);
      View := TJImageView.JavaClass.init(Presentation.getContext);
      View.setBackgroundColor(TJColor.JavaClass.BLACK);
      View.setScaleType(TJImageView_ScaleType.JavaClass.FIT_CENTER);
      Presentation.setContentView(View);
      if Presentation.getWindow <> nil then
      begin
        Presentation.getWindow.getDecorView.setSystemUiVisibility(UiFlags);
        Presentation.getWindow.setLayout(-1, -1);
      end;
      Presentation.show;
      FPresentations[I] := Presentation;
      FImages[I] := View;
      if I = TargetIndex then
      begin
        Point := TJPoint.Create;
        Displays.Items[I].getRealSize(Point);
        W := Max(1, Point.x);
        H := Max(1, Point.y);
        if W > 1920 then
        begin
          H := Round(H * (1920 / W));
          W := 1920;
        end;
        if H > 1080 then
        begin
          W := Round(W * (1080 / H));
          H := 1080;
        end;
        FExternalSize := TSize.Create(W, H);
      end;
    end;
    FExternalImageIndex := TargetIndex;
    SetAndroidKeepAwake(FKeepAwake);
  except
    ClearAndroidDisplays;
  end;
end;

procedure TPlatformCoordinator.SetAndroidKeepAwake(const AEnabled: Boolean);
var
  I, Flag: Integer;
begin
  Flag := TJWindowManager_LayoutParams.JavaClass.FLAG_KEEP_SCREEN_ON;
  try
    if (TAndroidHelper.Activity <> nil) and
       (TAndroidHelper.Activity.getWindow <> nil) then
      if AEnabled then
        TAndroidHelper.Activity.getWindow.addFlags(Flag)
      else
        TAndroidHelper.Activity.getWindow.clearFlags(Flag);
  except
    { Activity teardown can race the timer. }
  end;
  for I := 0 to High(FPresentations) do
    try
      if (FPresentations[I] <> nil) and (FPresentations[I].getWindow <> nil) then
      begin
        if AEnabled then
          FPresentations[I].getWindow.addFlags(Flag)
        else
          FPresentations[I].getWindow.clearFlags(Flag);
      end;
    except
      { A presentation display can be unplugged at any moment. }
    end;
end;
{$ENDIF}

end.
