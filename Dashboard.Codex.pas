unit Dashboard.Codex;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Dashboard.Model
  {$IF Defined(MSWINDOWS)}
  , Winapi.Windows,
  System.JSON
  {$ENDIF}
  ;

type
  { Keeps one Codex app-server process alive for the lifetime of the client.
    Enrich is deliberately non-throwing: a missing/not signed-in Codex CLI must
    never prevent the OpenAI organization data from being displayed. }
  TCodexClient = class
  private
    FLock: TCriticalSection;
    FStopRequested: Integer;
    {$IF Defined(MSWINDOWS)}
    FProcessHandle: THandle;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FErrorRead: THandle;
    FReadBuffer: TBytes;
    FRpcId: Int64;
    function ProcessIsRunning: Boolean;
    procedure StartServer;
    procedure StopServer;
    procedure EnsureServer;
    procedure SendLine(const AJson: string);
    function ExtractBufferedLine(out ALine: string): Boolean;
    function ReadErrorOutput: string;
    function ReadResponse(const ARequestId: Int64;
      const ATimeoutMilliseconds: Cardinal = 15000): string;
    function InvokeRequest(const AMethod: string): string;
    {$ENDIF}
  protected
    {$IF Defined(MSWINDOWS)}
    function FindLauncher(out APath: string): Boolean;
    procedure ApplyRateLimits(ASnapshot: TUsageSnapshot;
      const AJson: string);
    procedure ApplyUsage(ASnapshot: TUsageSnapshot; const AJson: string);
    {$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;
    class function Supported: Boolean; static;
    function Enrich(ASnapshot: TUsageSnapshot; out AError: string): Boolean;
    procedure Stop;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.Math,
  System.StrUtils
  {$IF Defined(MSWINDOWS)}
  , System.IOUtils
  {$ENDIF}
  ;

constructor TCodexClient.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FStopRequested := 0;
  {$IF Defined(MSWINDOWS)}
  FProcessHandle := 0;
  FInputWrite := 0;
  FOutputRead := 0;
  FErrorRead := 0;
  FReadBuffer := nil;
  FRpcId := 1;
  {$ENDIF}
end;

destructor TCodexClient.Destroy;
begin
  Stop;
  FLock.Free;
  inherited;
end;

class function TCodexClient.Supported: Boolean;
begin
  {$IF Defined(MSWINDOWS)}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TCodexClient.Stop;
begin
  TInterlocked.Exchange(FStopRequested, 1);
  FLock.Acquire;
  try
    {$IF Defined(MSWINDOWS)}
    StopServer;
    {$ENDIF}
  finally
    FLock.Release;
  end;
end;

{$IF Defined(MSWINDOWS)}

function WinErrorText(const APrefix: string): string;
begin
  Result := APrefix + ' (Windows-Fehler ' + IntToStr(GetLastError) + ')';
end;

function QuoteCommandLineArgument(const AValue: string): string;
var
  I, SlashCount: Integer;
  C: Char;
begin
  { Windows command-line quoting as specified for CommandLineToArgvW. }
  Result := '"';
  SlashCount := 0;
  for I := 1 to Length(AValue) do
  begin
    C := AValue[I];
    if C = '\' then
      Inc(SlashCount)
    else
    begin
      if C = '"' then
      begin
        Result := Result + StringOfChar('\', SlashCount * 2 + 1) + '"';
        SlashCount := 0;
      end
      else
      begin
        if SlashCount > 0 then
        begin
          Result := Result + StringOfChar('\', SlashCount);
          SlashCount := 0;
        end;
        Result := Result + C;
      end;
    end;
  end;
  if SlashCount > 0 then
    Result := Result + StringOfChar('\', SlashCount * 2);
  Result := Result + '"';
end;

function IsUsableLauncher(const APath: string): Boolean;
var
  FullPath: string;
begin
  Result := False;
  if APath = '' then
    Exit;
  try
    FullPath := TPath.GetFullPath(APath);
  except
    Exit;
  end;
  if not FileExists(FullPath) then
    Exit;
  { Store-package executables cannot be launched directly from here. }
  if ContainsText(FullPath,
    '\Program Files\WindowsApps\OpenAI.Codex_') then
    Exit;
  Result := SameText(ExtractFileExt(FullPath), '.exe') or
    SameText(ExtractFileExt(FullPath), '.cmd');
end;

function BuildChildEnvironment: UnicodeString;
var
  Environment, Cursor: PWideChar;
  Entries: TStringList;
  Entry, UserProfile: string;
  I: Integer;
  HasHome, HasCodexHome: Boolean;
begin
  Result := '';
  HasHome := False;
  HasCodexHome := False;
  Entries := TStringList.Create;
  try
    Entries.CaseSensitive := False;
    Entries.Sorted := True;
    Entries.Duplicates := dupIgnore;
    Environment := GetEnvironmentStringsW;
    if Environment = nil then
      raise Exception.Create(WinErrorText(
        'Die Prozessumgebung konnte nicht gelesen werden'));
    try
      Cursor := Environment;
      while Cursor^ <> #0 do
      begin
        Entry := string(Cursor);
        Entries.Add(Entry);
        if StartsText('HOME=', Entry) then
          HasHome := True;
        if StartsText('CODEX_HOME=', Entry) then
          HasCodexHome := True;
        Inc(Cursor, Length(Entry) + 1);
      end;
    finally
      FreeEnvironmentStringsW(Environment);
    end;

    { Current Codex CLI builds need HOME for app-server even on Windows. }
    if not HasHome then
    begin
      UserProfile := GetEnvironmentVariable('USERPROFILE');
      if UserProfile <> '' then
        Entries.Add('HOME=' + UserProfile);
    end;
    if not HasCodexHome then
    begin
      if UserProfile = '' then
        UserProfile := GetEnvironmentVariable('USERPROFILE');
      if UserProfile <> '' then
        Entries.Add('CODEX_HOME=' + TPath.Combine(UserProfile, '.codex'));
    end;

    for I := 0 to Entries.Count - 1 do
      Result := Result + Entries[I] + #0;
    Result := Result + #0;
  finally
    Entries.Free;
  end;
end;

function TCodexClient.FindLauncher(out APath: string): Boolean;
var
  Candidates: TStringList;
  SearchDirs: TStringList;
  AppData, LocalData, PathValue, Dir, Candidate: string;
  I, J: Integer;
  VersionDirs: TArray<string>;
  TempDir: string;

  procedure AddCandidate(const AValue: string);
  begin
    if (AValue <> '') and (Candidates.IndexOf(AValue) < 0) then
      Candidates.Add(AValue);
  end;

begin
  Result := False;
  APath := '';
  Candidates := TStringList.Create;
  SearchDirs := TStringList.Create;
  try
    Candidates.CaseSensitive := False;
    Candidates.Duplicates := dupIgnore;
    AddCandidate(TPath.Combine(ExtractFilePath(ParamStr(0)), 'codex.exe'));
    AddCandidate(TPath.Combine(ExtractFilePath(ParamStr(0)), 'codex.cmd'));

    AppData := GetEnvironmentVariable('APPDATA');
    LocalData := GetEnvironmentVariable('LOCALAPPDATA');
    if LocalData <> '' then
    begin
      { Desktop installations put their current CLI in a versioned directory.
        Explorer-launched dashboards do not inherit the desktop app's PATH.
        Prefer this CLI to an older, separately installed npm launcher. }
      Dir := TPath.Combine(LocalData, 'OpenAI\Codex\bin');
      AddCandidate(TPath.Combine(Dir, 'codex.exe'));
      if TDirectory.Exists(Dir) then
      begin
        try
          VersionDirs := TDirectory.GetDirectories(Dir);
          for I := 0 to High(VersionDirs) - 1 do
            for J := I + 1 to High(VersionDirs) do
              if TDirectory.GetLastWriteTimeUtc(VersionDirs[J]) >
                 TDirectory.GetLastWriteTimeUtc(VersionDirs[I]) then
              begin
                TempDir := VersionDirs[I];
                VersionDirs[I] := VersionDirs[J];
                VersionDirs[J] := TempDir;
              end;
          for Dir in VersionDirs do
            AddCandidate(TPath.Combine(Dir, 'codex.exe'));
        except
          { Continue with the other installation locations if a version
            directory is removed or inaccessible during a desktop update. }
        end;
      end;
      AddCandidate(TPath.Combine(LocalData,
        'Programs\OpenAI\Codex\bin\codex.exe'));
    end;
    if AppData <> '' then
      AddCandidate(TPath.Combine(AppData, 'npm\codex.cmd'));

    PathValue := GetEnvironmentVariable('PATH');
    SearchDirs.StrictDelimiter := True;
    SearchDirs.Delimiter := ';';
    SearchDirs.DelimitedText := PathValue;
    for I := 0 to SearchDirs.Count - 1 do
    begin
      Dir := Trim(SearchDirs[I]);
      if (Length(Dir) >= 2) and (Dir[1] = '"') and
         (Dir[Length(Dir)] = '"') then
        Dir := Copy(Dir, 2, Length(Dir) - 2);
      if Dir = '' then
        Continue;
      AddCandidate(TPath.Combine(Dir, 'codex.exe'));
      AddCandidate(TPath.Combine(Dir, 'codex.cmd'));
    end;

    for J := 0 to Candidates.Count - 1 do
    begin
      Candidate := Candidates[J];
      if IsUsableLauncher(Candidate) then
      begin
        APath := TPath.GetFullPath(Candidate);
        Exit(True);
      end;
    end;
  finally
    SearchDirs.Free;
    Candidates.Free;
  end;
end;

function TCodexClient.ProcessIsRunning: Boolean;
var
  ExitCode: DWORD;
begin
  Result := (FProcessHandle <> 0) and
    GetExitCodeProcess(FProcessHandle, ExitCode) and
    (ExitCode = STILL_ACTIVE);
end;

procedure TCodexClient.StartServer;
var
  Security: TSecurityAttributes;
  Startup: TStartupInfoW;
  ProcessInfo: TProcessInformation;
  ChildInputRead, ChildOutputWrite, ChildErrorWrite: THandle;
  LauncherPath, ApplicationName, CommandLine, WorkDir: string;
  EnvironmentBlock: UnicodeString;
  Flags: DWORD;
begin
  if not FindLauncher(LauncherPath) then
    raise Exception.Create(
      'Codex CLI nicht gefunden. Bitte die Codex CLI separat installieren und einmal anmelden.');

  ChildInputRead := 0;
  ChildOutputWrite := 0;
  ChildErrorWrite := 0;
  FillChar(Security, SizeOf(Security), 0);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;

  try
    if not CreatePipe(ChildInputRead, FInputWrite, @Security, 0) then
      raise Exception.Create(WinErrorText('Eingabepipe konnte nicht erstellt werden'));
    if not SetHandleInformation(FInputWrite, HANDLE_FLAG_INHERIT, 0) then
      raise Exception.Create(WinErrorText('Eingabepipe konnte nicht vorbereitet werden'));

    if not CreatePipe(FOutputRead, ChildOutputWrite, @Security, 0) then
      raise Exception.Create(WinErrorText('Ausgabepipe konnte nicht erstellt werden'));
    if not SetHandleInformation(FOutputRead, HANDLE_FLAG_INHERIT, 0) then
      raise Exception.Create(WinErrorText('Ausgabepipe konnte nicht vorbereitet werden'));

    if not CreatePipe(FErrorRead, ChildErrorWrite, @Security, 0) then
      raise Exception.Create(WinErrorText('Fehlerpipe konnte nicht erstellt werden'));
    if not SetHandleInformation(FErrorRead, HANDLE_FLAG_INHERIT, 0) then
      raise Exception.Create(WinErrorText('Fehlerpipe konnte nicht vorbereitet werden'));

    if SameText(ExtractFileExt(LauncherPath), '.cmd') then
    begin
      ApplicationName := GetEnvironmentVariable('COMSPEC');
      if ApplicationName = '' then
        ApplicationName := TPath.Combine(GetEnvironmentVariable('SystemRoot'),
          'System32\cmd.exe');
      CommandLine := QuoteCommandLineArgument(ApplicationName) +
        ' /D /S /C "' + QuoteCommandLineArgument(LauncherPath) +
        ' app-server"';
    end
    else
    begin
      ApplicationName := LauncherPath;
      CommandLine := QuoteCommandLineArgument(LauncherPath) + ' app-server';
    end;
    WorkDir := ExtractFileDir(LauncherPath);
    EnvironmentBlock := BuildChildEnvironment;

    FillChar(Startup, SizeOf(Startup), 0);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    Startup.hStdInput := ChildInputRead;
    Startup.hStdOutput := ChildOutputWrite;
    Startup.hStdError := ChildErrorWrite;
    FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
    Flags := CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT;
    UniqueString(CommandLine);
    if not CreateProcessW(PWideChar(ApplicationName), PWideChar(CommandLine),
      nil, nil, True, Flags, PWideChar(EnvironmentBlock), PWideChar(WorkDir),
      Startup, ProcessInfo) then
      raise Exception.Create(WinErrorText('Codex App Server konnte nicht gestartet werden'));

    FProcessHandle := ProcessInfo.hProcess;
    CloseHandle(ProcessInfo.hThread);
    CloseHandle(ChildInputRead);
    ChildInputRead := 0;
    CloseHandle(ChildOutputWrite);
    ChildOutputWrite := 0;
    CloseHandle(ChildErrorWrite);
    ChildErrorWrite := 0;
    FReadBuffer := nil;
    FRpcId := 1;

    SendLine('{"method":"initialize","id":1,"params":{' +
      '"clientInfo":{"name":"openai_usage_display",' +
      '"title":"OpenAI Nutzungsanzeige","version":"3.0.0"},' +
      '"capabilities":{"experimentalApi":true}}}');
    ReadResponse(1);
    SendLine('{"method":"initialized","params":{}}');
  except
    if ChildInputRead <> 0 then
      CloseHandle(ChildInputRead);
    if ChildOutputWrite <> 0 then
      CloseHandle(ChildOutputWrite);
    if ChildErrorWrite <> 0 then
      CloseHandle(ChildErrorWrite);
    StopServer;
    raise;
  end;
end;

procedure TCodexClient.StopServer;
begin
  if FInputWrite <> 0 then
  begin
    CloseHandle(FInputWrite);
    FInputWrite := 0;
  end;
  if FOutputRead <> 0 then
  begin
    CloseHandle(FOutputRead);
    FOutputRead := 0;
  end;
  if FErrorRead <> 0 then
  begin
    CloseHandle(FErrorRead);
    FErrorRead := 0;
  end;
  if FProcessHandle <> 0 then
  begin
    if WaitForSingleObject(FProcessHandle, 300) = WAIT_TIMEOUT then
    begin
      TerminateProcess(FProcessHandle, 0);
      WaitForSingleObject(FProcessHandle, 1000);
    end;
    CloseHandle(FProcessHandle);
    FProcessHandle := 0;
  end;
  FReadBuffer := nil;
  FRpcId := 1;
end;

procedure TCodexClient.EnsureServer;
begin
  if not ProcessIsRunning then
  begin
    StopServer;
    StartServer;
  end;
end;

procedure TCodexClient.SendLine(const AJson: string);
var
  Bytes: TBytes;
  Offset: Integer;
  Written: DWORD;
begin
  if not ProcessIsRunning then
    raise Exception.Create('Der Codex App Server wurde beendet.');
  Bytes := TEncoding.UTF8.GetBytes(AJson + #10);
  Offset := 0;
  while Offset < Length(Bytes) do
  begin
    Written := 0;
    if not WriteFile(FInputWrite, Bytes[Offset], Length(Bytes) - Offset,
      Written, nil) then
      raise Exception.Create(WinErrorText(
        'Nachricht an den Codex App Server konnte nicht gesendet werden'));
    if Written = 0 then
      raise Exception.Create('Der Codex App Server hat die Eingabepipe geschlossen.');
    Inc(Offset, Written);
  end;
end;

function TCodexClient.ExtractBufferedLine(out ALine: string): Boolean;
var
  I, Remaining: Integer;
begin
  Result := False;
  ALine := '';
  for I := 0 to High(FReadBuffer) do
    if FReadBuffer[I] = 10 then
    begin
      ALine := TEncoding.UTF8.GetString(FReadBuffer, 0, I);
      if EndsText(#13, ALine) then
        Delete(ALine, Length(ALine), 1);
      Remaining := Length(FReadBuffer) - I - 1;
      if Remaining > 0 then
        Move(FReadBuffer[I + 1], FReadBuffer[0], Remaining);
      SetLength(FReadBuffer, Remaining);
      Exit(True);
    end;
end;

function TCodexClient.ReadErrorOutput: string;
const
  ReadChunkSize = 4096;
var
  Available, ReadCount: DWORD;
  Chunk: array[0..ReadChunkSize - 1] of Byte;
  Bytes: TBytes;
  OldLength: Integer;
begin
  Result := '';
  if FErrorRead = 0 then
    Exit;
  while True do
  begin
    Available := 0;
    if not PeekNamedPipe(FErrorRead, nil, 0, nil, @Available, nil) or
       (Available = 0) then
      Break;
    ReadCount := 0;
    if not ReadFile(FErrorRead, Chunk[0], Min(Available,
      DWORD(ReadChunkSize)), ReadCount, nil) or (ReadCount = 0) then
      Break;
    OldLength := Length(Bytes);
    SetLength(Bytes, OldLength + Integer(ReadCount));
    Move(Chunk[0], Bytes[OldLength], ReadCount);
  end;
  if Length(Bytes) > 0 then
    Result := Trim(TEncoding.UTF8.GetString(Bytes));
end;

function TCodexClient.ReadResponse(const ARequestId: Int64;
  const ATimeoutMilliseconds: Cardinal): string;
const
  ReadChunkSize = 8192;
var
  Deadline: UInt64;
  Available, ReadCount: DWORD;
  Chunk: array[0..ReadChunkSize - 1] of Byte;
  OldLength: Integer;
  Line, ErrorMessage, DiagnosticChunk, DiagnosticText: string;
  Parsed, IdValue, ErrorValue, MessageValue, ResultValue: TJSONValue;
  Root, ErrorObject: TJSONObject;
  ResponseId: Int64;
begin
  DiagnosticText := '';
  Deadline := GetTickCount64 + ATimeoutMilliseconds;
  while GetTickCount64 < Deadline do
  begin
    if TInterlocked.CompareExchange(FStopRequested, 0, 0) <> 0 then
      raise EAbort.Create('Codex-Abfrage wurde beendet.');
    while ExtractBufferedLine(Line) do
    begin
      Parsed := TJSONObject.ParseJSONValue(Line);
      try
        if not (Parsed is TJSONObject) then
          Continue;
        Root := TJSONObject(Parsed);
        IdValue := Root.GetValue('id');
        if (IdValue = nil) or
           not TryStrToInt64(IdValue.Value, ResponseId) or
           (ResponseId <> ARequestId) then
          Continue;

        ErrorValue := Root.GetValue('error');
        if (ErrorValue <> nil) and not (ErrorValue is TJSONNull) then
        begin
          ErrorMessage := '';
          if ErrorValue is TJSONObject then
          begin
            ErrorObject := TJSONObject(ErrorValue);
            MessageValue := ErrorObject.GetValue('message');
            if MessageValue <> nil then
              ErrorMessage := MessageValue.Value;
          end;
          if ErrorMessage = '' then
            ErrorMessage := 'Unbekannter Codex-Fehler';
          raise Exception.Create('Codex App Server: ' + ErrorMessage);
        end;

        ResultValue := Root.GetValue('result');
        if ResultValue = nil then
          Exit('{}');
        Exit(ResultValue.ToJSON);
      finally
        Parsed.Free;
      end;
    end;

    { Keep stderr flowing so a verbose app-server cannot fill its pipe and
      block the JSON-RPC stream.  Retain only a short diagnostic tail. }
    DiagnosticChunk := ReadErrorOutput;
    if DiagnosticChunk <> '' then
    begin
      if DiagnosticText <> '' then
        DiagnosticText := DiagnosticText + sLineBreak;
      DiagnosticText := DiagnosticText + DiagnosticChunk;
      if Length(DiagnosticText) > 4096 then
        Delete(DiagnosticText, 1, Length(DiagnosticText) - 4096);
    end;

    if not ProcessIsRunning then
    begin
      ErrorMessage := DiagnosticText;
      DiagnosticChunk := ReadErrorOutput;
      if DiagnosticChunk <> '' then
      begin
        if ErrorMessage <> '' then
          ErrorMessage := ErrorMessage + sLineBreak;
        ErrorMessage := ErrorMessage + DiagnosticChunk;
      end;
      if ErrorMessage <> '' then
        raise Exception.Create('Der Codex App Server wurde beendet: ' +
          ErrorMessage)
      else
        raise Exception.Create('Der Codex App Server wurde unerwartet beendet.');
    end;

    Available := 0;
    if not PeekNamedPipe(FOutputRead, nil, 0, nil, @Available, nil) then
      raise Exception.Create(WinErrorText(
        'Die Codex-Ausgabepipe konnte nicht gelesen werden'));
    if Available = 0 then
    begin
      TThread.Sleep(10);
      Continue;
    end;

    ReadCount := 0;
    if not ReadFile(FOutputRead, Chunk[0], Min(Available,
      DWORD(ReadChunkSize)), ReadCount, nil) then
      raise Exception.Create(WinErrorText(
        'Die Codex-Antwort konnte nicht gelesen werden'));
    if ReadCount = 0 then
      raise Exception.Create('Der Codex App Server hat die Ausgabepipe geschlossen.');
    OldLength := Length(FReadBuffer);
    SetLength(FReadBuffer, OldLength + Integer(ReadCount));
    Move(Chunk[0], FReadBuffer[OldLength], ReadCount);
  end;
  ErrorMessage := DiagnosticText;
  DiagnosticChunk := ReadErrorOutput;
  if DiagnosticChunk <> '' then
  begin
    if ErrorMessage <> '' then
      ErrorMessage := ErrorMessage + sLineBreak;
    ErrorMessage := ErrorMessage + DiagnosticChunk;
  end;
  if ErrorMessage <> '' then
    raise Exception.Create('Zeitüberschreitung bei der Codex-Abfrage: ' +
      ErrorMessage)
  else
    raise Exception.Create('Zeitüberschreitung bei der Codex-Abfrage.');
end;

function TCodexClient.InvokeRequest(const AMethod: string): string;
var
  RequestId: Int64;
begin
  Inc(FRpcId);
  RequestId := FRpcId;
  SendLine('{"method":"' + AMethod + '","id":' +
    IntToStr(RequestId) + ',"params":{}}');
  Result := ReadResponse(RequestId);
end;

function JsonObjectValue(const AObject: TJSONObject;
  const AName: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
    Result := TJSONObject(Value);
end;

function LimitRank(const ALimit: TRateLimitWindow): Integer;
var
  Key: string;
begin
  Key := LowerCase(ALimit.Id + ' ' + ALimit.Name);
  if ContainsText(Key, 'spark') then
    Result := 1
  else if ContainsText(Key, 'codex') then
    Result := 0
  else
    Result := 2;
end;

function CompareLimits(const ALeft, ARight: TRateLimitWindow): Integer;
begin
  Result := LimitRank(ALeft) - LimitRank(ARight);
  if Result = 0 then
    Result := CompareText(ALeft.Name, ARight.Name);
  if Result = 0 then
    Result := CompareText(ALeft.Id, ARight.Id);
end;

procedure SortLimits(var ALimits: TArray<TRateLimitWindow>);
var
  I, J: Integer;
  Temp: TRateLimitWindow;
begin
  for I := 0 to High(ALimits) - 1 do
    for J := I + 1 to High(ALimits) do
      if CompareLimits(ALimits[I], ALimits[J]) > 0 then
      begin
        Temp := ALimits[I];
        ALimits[I] := ALimits[J];
        ALimits[J] := Temp;
      end;
end;

procedure AddRateLimitWindow(var ALimits: TArray<TRateLimitWindow>;
  const ALimit: TJSONObject; const APropertyName, ADisplayName: string);
var
  Window: TJSONObject;
  Used: Double;
  LimitId, LimitName: string;
  ResetSeconds: Int64;
  N: Integer;
begin
  Window := JsonObjectValue(ALimit, APropertyName);
  if (Window = nil) or
     not (Window.GetValue('usedPercent') is TJSONNumber) then
    Exit;

  Used := EnsureRange(JsonFloat(Window, 'usedPercent'), 0.0, 100.0);
  LimitId := JsonString(ALimit, 'limitId', 'codex');
  LimitName := JsonString(ALimit, 'limitName', '');
  if LimitName = '' then
    LimitName := LimitId;
  if LimitName = '' then
    LimitName := 'Codex';

  N := Length(ALimits);
  SetLength(ALimits, N + 1);
  ALimits[N].Id := 'codex:' + LimitId + ':' + APropertyName;
  ALimits[N].Name := LimitName;
  ALimits[N].WindowName := ADisplayName;
  ALimits[N].UsedPercent := Used;
  ALimits[N].WindowMinutes := JsonInt64(Window, 'windowDurationMins');
  ResetSeconds := JsonInt64(Window, 'resetsAt');
  if ResetSeconds > 0 then
    ALimits[N].ResetsAt := UnixToDateTime(ResetSeconds, False)
  else
    ALimits[N].ResetsAt := 0;
  ALimits[N].Available := True;
end;

procedure ParseLimitObject(var ALimits: TArray<TRateLimitWindow>;
  const AValue: TJSONValue);
var
  LimitObject: TJSONObject;
begin
  if not (AValue is TJSONObject) then
    Exit;
  LimitObject := TJSONObject(AValue);
  AddRateLimitWindow(ALimits, LimitObject, 'primary', 'Primär');
  AddRateLimitWindow(ALimits, LimitObject, 'secondary', 'Sekundär');
end;

procedure MergeCodexLimits(ASnapshot: TUsageSnapshot;
  const ACodexLimits: TArray<TRateLimitWindow>);
var
  Merged: TArray<TRateLimitWindow>;
  I, N: Integer;
begin
  SetLength(Merged, 0);
  for I := 0 to High(ASnapshot.RateLimits) do
    if not StartsText('codex:', ASnapshot.RateLimits[I].Id) then
    begin
      N := Length(Merged);
      SetLength(Merged, N + 1);
      Merged[N] := ASnapshot.RateLimits[I];
    end;
  for I := 0 to High(ACodexLimits) do
  begin
    N := Length(Merged);
    SetLength(Merged, N + 1);
    Merged[N] := ACodexLimits[I];
  end;
  ASnapshot.RateLimits := Merged;
end;

procedure TCodexClient.ApplyRateLimits(ASnapshot: TUsageSnapshot;
  const AJson: string);
var
  Parsed, Value: TJSONValue;
  Root, MapObject, SingleObject, Credits: TJSONObject;
  ArrayValue: TJSONArray;
  Limits: TArray<TRateLimitWindow>;
  I: Integer;
  CreditCount: Int64;
begin
  ASnapshot.CodexRateLimitsAvailable := False;
  Parsed := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Parsed is TJSONObject) then
      raise EConvertError.Create('Ungültige Codex-Limitantwort');
    Root := TJSONObject(Parsed);
    SetLength(Limits, 0);

    Value := Root.GetValue('rateLimitsByLimitId');
    if Value is TJSONObject then
    begin
      MapObject := TJSONObject(Value);
      for I := 0 to MapObject.Count - 1 do
        ParseLimitObject(Limits, MapObject.Pairs[I].JsonValue);
    end;
    { Some servers return an empty or incomplete multi-bucket view alongside
      a usable legacy window. Do not discard that backward-compatible value. }
    if Length(Limits) = 0 then
    begin
      Value := Root.GetValue('rateLimits');
      if Value is TJSONArray then
      begin
        ArrayValue := TJSONArray(Value);
        for I := 0 to ArrayValue.Count - 1 do
          ParseLimitObject(Limits, ArrayValue.Items[I]);
      end
      else if Value is TJSONObject then
      begin
        SingleObject := TJSONObject(Value);
        if (SingleObject.GetValue('primary') <> nil) or
           (SingleObject.GetValue('limitId') <> nil) then
          ParseLimitObject(Limits, SingleObject)
        else
          for I := 0 to SingleObject.Count - 1 do
            ParseLimitObject(Limits, SingleObject.Pairs[I].JsonValue);
      end;
    end;

    SortLimits(Limits);
    MergeCodexLimits(ASnapshot, Limits);
    ASnapshot.CodexRateLimitsAvailable := Length(Limits) > 0;
    if not ASnapshot.CodexRateLimitsAvailable then
      raise EConvertError.Create('Codex liefert derzeit keine verfügbaren Limitwerte.');

    Credits := JsonObjectValue(Root, 'rateLimitResetCredits');
    if Credits <> nil then
    begin
      CreditCount := JsonInt64(Credits, 'availableCount');
      ASnapshot.CodexResetCredits := Integer(EnsureRange(CreditCount,
        Int64(0), Int64(MaxInt)));
    end;
  finally
    Parsed.Free;
  end;
end;

function TryParseUsageDay(const AText: string; out ADay: TDateTime): Boolean;
var
  YearValue, MonthValue, DayValue: Integer;
begin
  Result := (Length(AText) >= 10) and (AText[5] = '-') and
    (AText[8] = '-') and TryStrToInt(Copy(AText, 1, 4), YearValue) and
    TryStrToInt(Copy(AText, 6, 2), MonthValue) and
    TryStrToInt(Copy(AText, 9, 2), DayValue) and
    TryEncodeDate(YearValue, MonthValue, DayValue, ADay);
end;

procedure TCodexClient.ApplyUsage(ASnapshot: TUsageSnapshot;
  const AJson: string);
var
  Parsed, BucketsValue: TJSONValue;
  Root, Summary, Bucket: TJSONObject;
  Buckets: TJSONArray;
  I: Integer;
  BucketDay, TodayValue, SevenDayStart, MonthStart: TDateTime;
  Tokens, TodayTokens, SevenDayTokens, MonthTokens: Int64;
  LifetimeAvailable, DailyAvailable, TodayAvailable: Boolean;
begin
  ASnapshot.CodexUsageAvailable := False;
  ASnapshot.CodexLifetimeAvailable := False;
  ASnapshot.CodexDailyUsageAvailable := False;
  ASnapshot.CodexTodayUsageAvailable := False;
  Parsed := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Parsed is TJSONObject) then
      raise EConvertError.Create('Ungültige Codex-Nutzungsantwort');
    Root := TJSONObject(Parsed);
    Summary := JsonObjectValue(Root, 'summary');
    LifetimeAvailable := (Summary <> nil) and
      (Summary.GetValue('lifetimeTokens') is TJSONNumber);
    if LifetimeAvailable then
      ASnapshot.CodexLifetimeTokens := JsonInt64(Summary, 'lifetimeTokens');

    TodayValue := Date;
    SevenDayStart := IncDay(TodayValue, -6);
    MonthStart := StartOfTheMonth(TodayValue);
    TodayTokens := 0;
    SevenDayTokens := 0;
    MonthTokens := 0;
    TodayAvailable := False;

    BucketsValue := Root.GetValue('dailyUsageBuckets');
    DailyAvailable := BucketsValue is TJSONArray;
    if BucketsValue is TJSONArray then
    begin
      Buckets := TJSONArray(BucketsValue);
      for I := 0 to Buckets.Count - 1 do
      begin
        if not (Buckets.Items[I] is TJSONObject) then
          raise EConvertError.Create('Ungültiger Codex-Tageswert');
        Bucket := TJSONObject(Buckets.Items[I]);
        if not TryParseUsageDay(JsonString(Bucket, 'startDate', ''),
          BucketDay) or not (Bucket.GetValue('tokens') is TJSONNumber) then
          raise EConvertError.Create('Unvollständiger Codex-Tageswert');
        Tokens := Max(Int64(0), JsonInt64(Bucket, 'tokens'));
        if SameDate(BucketDay, TodayValue) then
        begin
          TodayTokens := TodayTokens + Tokens;
          TodayAvailable := True;
        end;
        if (BucketDay >= SevenDayStart) and (BucketDay <= TodayValue) then
          SevenDayTokens := SevenDayTokens + Tokens;
        if (BucketDay >= MonthStart) and (BucketDay <= TodayValue) then
          MonthTokens := MonthTokens + Tokens;
      end;
    end;
    ASnapshot.CodexTodayTokens := TodayTokens;
    ASnapshot.CodexSevenDayTokens := SevenDayTokens;
    ASnapshot.CodexMonthTokens := MonthTokens;
    ASnapshot.CodexLifetimeAvailable := LifetimeAvailable;
    ASnapshot.CodexDailyUsageAvailable := DailyAvailable;
    ASnapshot.CodexTodayUsageAvailable := TodayAvailable;
    ASnapshot.CodexUsageAvailable := ASnapshot.CodexLifetimeAvailable or
      ASnapshot.CodexDailyUsageAvailable;
    if not ASnapshot.CodexUsageAvailable then
      raise EConvertError.Create('Codex liefert derzeit keine verfügbaren Tokenstatistiken.');
  finally
    Parsed.Free;
  end;
end;

{$ENDIF}

function TCodexClient.Enrich(ASnapshot: TUsageSnapshot;
  out AError: string): Boolean;
{$IF Defined(MSWINDOWS)}
var
  RateJson, UsageJson, RateError, UsageError: string;
  RateOK, UsageOK: Boolean;
{$ENDIF}
begin
  Result := False;
  AError := '';
  if ASnapshot = nil then
  begin
    AError := 'Kein Nutzungs-Snapshot übergeben.';
    Exit;
  end;

  {$IF Defined(MSWINDOWS)}
  FLock.Acquire;
  try
    ASnapshot.CodexUsageAvailable := False;
    ASnapshot.CodexLifetimeAvailable := False;
    ASnapshot.CodexDailyUsageAvailable := False;
    ASnapshot.CodexTodayUsageAvailable := False;
    ASnapshot.CodexRateLimitsAvailable := False;
    ASnapshot.CodexError := '';
    MergeCodexLimits(ASnapshot, nil);
    TInterlocked.Exchange(FStopRequested, 0);
    try
      EnsureServer;
    except
      on E: Exception do
      begin
        AError := E.Message;
        StopServer;
        Exit(False);
      end;
    end;

    RateOK := False;
    UsageOK := False;
    RateError := '';
    UsageError := '';
    try
      RateJson := InvokeRequest('account/rateLimits/read');
      ApplyRateLimits(ASnapshot, RateJson);
      RateOK := True;
    except
      on E: Exception do
        RateError := 'Codex-Limits: ' + E.Message;
    end;
    try
      UsageJson := InvokeRequest('account/usage/read');
      ApplyUsage(ASnapshot, UsageJson);
      UsageOK := True;
      if not ASnapshot.CodexLifetimeAvailable then
        UsageError := 'Codex-Nutzung: Gesamttokens derzeit nicht verfügbar.'
      else if not ASnapshot.CodexDailyUsageAvailable then
        UsageError := 'Codex-Nutzung: Tagesstatistiken derzeit nicht verfügbar.';
    except
      on E: Exception do
        UsageError := 'Codex-Nutzung: ' + E.Message;
    end;

    Result := RateOK or UsageOK;
    if (RateError <> '') and (UsageError <> '') then
      AError := RateError + ' ' + UsageError
    else if RateError <> '' then
      AError := RateError
    else
      AError := UsageError;

    if not Result then
      StopServer
    else if not ContainsText(ASnapshot.SourceText, 'Codex App Server') then
    begin
      if ASnapshot.SourceText <> '' then
        ASnapshot.SourceText := ASnapshot.SourceText + ' · ';
      ASnapshot.SourceText := ASnapshot.SourceText + 'lokaler Codex App Server';
    end;
  finally
    ASnapshot.CodexError := AError;
    FLock.Release;
  end;
  {$ELSE}
  { Android is a display client. It receives already enriched, sanitized
    snapshots from the Windows collector and never starts a local CLI. }
  Result := False;
  AError := '';
  {$ENDIF}
end;

end.
