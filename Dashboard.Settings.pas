unit Dashboard.Settings;

interface

type
  TDashboardSettings = class
  private
    FFileName: string;
  public
    CollectorUrl: string;
    ViewerToken: string;
    ListenPort: Integer;
    DashboardDisplay: Integer;
    StartInTray: Boolean;
    SpendingLimit: Double;
    BillingDay: Integer;
    RefreshSeconds: Integer;
    OtherDisplayIdleMinutes: Integer;
    KeepAwakeStartHour: Integer;
    KeepAwakeEndHour: Integer;
    UseDemoWhenUnavailable: Boolean;
    constructor Create;
    procedure Load;
    procedure Save;
    property FileName: string read FFileName;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.IOUtils,
  System.IniFiles;

constructor TDashboardSettings.Create;
begin
  inherited Create;
  FFileName := TPath.Combine(TPath.GetDocumentsPath, 'OpenAIUsageDashboard.ini');
  CollectorUrl := 'http://127.0.0.1:8787/snapshot';
  ViewerToken := '';
  ListenPort := 8787;
  DashboardDisplay := -1;
  StartInTray := False;
  SpendingLimit := 0;
  BillingDay := 1;
  RefreshSeconds := 30;
  OtherDisplayIdleMinutes := 10;
  KeepAwakeStartHour := 10;
  KeepAwakeEndHour := 18;
  UseDemoWhenUnavailable := True;
end;

procedure TDashboardSettings.Load;
var
  Ini: TIniFile;
begin
  if not TFile.Exists(FFileName) then
    Exit;
  Ini := TIniFile.Create(FFileName);
  try
    CollectorUrl := Ini.ReadString('Network', 'CollectorUrl', CollectorUrl);
    ViewerToken := Ini.ReadString('Network', 'ViewerToken', ViewerToken);
    ListenPort := EnsureRange(Ini.ReadInteger('Network', 'ListenPort', ListenPort), 1, 65535);
    DashboardDisplay := Ini.ReadInteger('Display', 'DashboardDisplay', DashboardDisplay);
    StartInTray := Ini.ReadBool('Display', 'StartInTray', StartInTray);
    SpendingLimit := Ini.ReadFloat('Usage', 'SpendingLimit', SpendingLimit);
    BillingDay := EnsureRange(Ini.ReadInteger('Usage', 'BillingDay', BillingDay), 1, 28);
    RefreshSeconds := EnsureRange(Ini.ReadInteger('Usage', 'RefreshSeconds', RefreshSeconds), 10, 3600);
    OtherDisplayIdleMinutes := EnsureRange(Ini.ReadInteger('Display', 'OtherDisplayIdleMinutes',
      OtherDisplayIdleMinutes), 1, 120);
    KeepAwakeStartHour := EnsureRange(Ini.ReadInteger('Display', 'KeepAwakeStartHour',
      KeepAwakeStartHour), 0, 23);
    KeepAwakeEndHour := EnsureRange(Ini.ReadInteger('Display', 'KeepAwakeEndHour',
      KeepAwakeEndHour), 1, 24);
    UseDemoWhenUnavailable := Ini.ReadBool('Usage', 'UseDemoWhenUnavailable', UseDemoWhenUnavailable);
  finally
    Ini.Free;
  end;
end;

procedure TDashboardSettings.Save;
var
  Ini: TIniFile;
begin
  ForceDirectories(TPath.GetDirectoryName(FFileName));
  Ini := TIniFile.Create(FFileName);
  try
    Ini.WriteString('Network', 'CollectorUrl', CollectorUrl);
    Ini.WriteString('Network', 'ViewerToken', ViewerToken);
    Ini.WriteInteger('Network', 'ListenPort', ListenPort);
    Ini.WriteInteger('Display', 'DashboardDisplay', DashboardDisplay);
    Ini.WriteBool('Display', 'StartInTray', StartInTray);
    Ini.WriteFloat('Usage', 'SpendingLimit', SpendingLimit);
    Ini.WriteInteger('Usage', 'BillingDay', BillingDay);
    Ini.WriteInteger('Usage', 'RefreshSeconds', RefreshSeconds);
    Ini.WriteInteger('Display', 'OtherDisplayIdleMinutes', OtherDisplayIdleMinutes);
    Ini.WriteInteger('Display', 'KeepAwakeStartHour', KeepAwakeStartHour);
    Ini.WriteInteger('Display', 'KeepAwakeEndHour', KeepAwakeEndHour);
    Ini.WriteBool('Usage', 'UseDemoWhenUnavailable', UseDemoWhenUnavailable);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
