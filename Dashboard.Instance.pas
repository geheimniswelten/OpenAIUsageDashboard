unit Dashboard.Instance;

interface

uses
  System.SysUtils
{$IF Defined(MSWINDOWS)}
  , Winapi.Windows
{$ENDIF}
  ;

type
  // Construct before Application.Initialize/CreateForm on the GUI thread and
  // keep the object alive until the form and its collectors have shut down.
  // On Windows the mutex owner is the constructing thread. The Local namespace
  // separates interactive sessions; the user SID separates users in a session.
  TDashboardInstance = class
  private
    FIsPrimary: Boolean;
{$IF Defined(MSWINDOWS)}
    FMutex: THandle;
    FActivationEvent: THandle;
    FOwnerThreadId: DWORD;
{$ENDIF}
  public
    constructor Create(const AObjectPrefix: string =
      'OpenAIUsageDashboard.Instance.v1');
    destructor Destroy; override;
    // A normal secondary launch requests that the running dashboard be shown.
    // Collector-only launches simply leave without calling this method.
    procedure RequestActivation;
    // The primary GUI timer polls this after its form is ready. Repeated
    // requests coalesce into one restore action; startup requests stay queued.
    function ConsumeActivationRequest: Boolean;
    property IsPrimary: Boolean read FIsPrimary;
  end;

implementation

{$IF Defined(MSWINDOWS)}
const
  CSddlRevision = 1;

function ConvertStringSecurityDescriptorToSecurityDescriptorW(
  StringSecurityDescriptor: PWideChar; StringSDRevision: DWORD;
  out SecurityDescriptor: Pointer; SecurityDescriptorSize: PDWORD): BOOL;
  stdcall; external 'advapi32.dll'
  name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';

procedure RaiseInstanceError(const AOperation: string; const ACode: DWORD);
begin
  raise EOSError.CreateFmt('%s: %s (%d)',
    [AOperation, SysErrorMessage(ACode), ACode]);
end;

function CurrentUserSid: string;
var
  Token: THandle;
  RequiredBytes: DWORD;
  ErrorCode: DWORD;
  TokenBuffer: TBytes;
  SidText: PWideChar;
begin
  Token := 0;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    RaiseInstanceError('OpenProcessToken for instance guard', GetLastError);
  try
    RequiredBytes := 0;
    if not GetTokenInformation(Token, TokenUser, nil, 0, RequiredBytes) then
    begin
      ErrorCode := GetLastError;
      if ErrorCode <> ERROR_INSUFFICIENT_BUFFER then
        RaiseInstanceError('GetTokenInformation size for instance guard',
          ErrorCode);
    end;
    if RequiredBytes = 0 then
      raise EOSError.Create('Windows returned an empty user token');
    SetLength(TokenBuffer, RequiredBytes);
    if not GetTokenInformation(Token, TokenUser, @TokenBuffer[0],
      RequiredBytes, RequiredBytes) then
      RaiseInstanceError('GetTokenInformation for instance guard', GetLastError);
    SidText := nil;
    if not ConvertSidToStringSidW(PTokenUser(@TokenBuffer[0]).User.Sid,
      SidText) then
      RaiseInstanceError('ConvertSidToStringSid for instance guard', GetLastError);
    try
      Result := SidText;
    finally
      LocalFree(HLOCAL(SidText));
    end;
  finally
    CloseHandle(Token);
  end;
end;
{$ENDIF}

constructor TDashboardInstance.Create(const AObjectPrefix: string);
{$IF Defined(MSWINDOWS)}
var
  UserSid: string;
  ObjectBase: string;
  SecuritySddl: string;
  SecurityDescriptor: Pointer;
  SecurityAttributes: TSecurityAttributes;
  WaitResult: DWORD;
{$ENDIF}
begin
  inherited Create;
{$IF Defined(MSWINDOWS)}
  if (AObjectPrefix = '') or (Pos('\', AObjectPrefix) <> 0) or
    (Pos('/', AObjectPrefix) <> 0) or (Pos(#0, AObjectPrefix) <> 0) then
    raise EArgumentException.Create('Invalid instance object prefix');
  UserSid := CurrentUserSid;
  ObjectBase := 'Local\' + AObjectPrefix + '.' + UserSid;
  if Length(ObjectBase + '.Activate') >= MAX_PATH then
    raise EArgumentException.Create('Instance object prefix is too long');

  // Do not depend on the creator token's default DACL: an elevated launch must
  // also accept a normal launch by the same user. Only that SID has access;
  // the explicit medium integrity label permits both normal and elevated
  // processes to set the activation event. Low integrity processes are denied.
  SecuritySddl := 'D:P(A;;GA;;;' + UserSid + ')S:(ML;;NW;;;ME)';
  SecurityDescriptor := nil;
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(
    PWideChar(SecuritySddl), CSddlRevision, SecurityDescriptor, nil) then
    RaiseInstanceError('Create instance security descriptor', GetLastError);
  try
    SecurityAttributes.nLength := SizeOf(SecurityAttributes);
    SecurityAttributes.lpSecurityDescriptor := SecurityDescriptor;
    SecurityAttributes.bInheritHandle := False;

    // Create the event first, including in secondary launches. A secondary
    // can win this creation race and signal it before the primary form exists.
    // Opening an existing event does not change its signaled state.
    FActivationEvent := CreateEventW(@SecurityAttributes, True, False,
      PWideChar(ObjectBase + '.Activate'));
    if FActivationEvent = 0 then
      RaiseInstanceError('Create dashboard activation event', GetLastError);
    FMutex := CreateMutexW(@SecurityAttributes, False,
      PWideChar(ObjectBase + '.Mutex'));
    if FMutex = 0 then
      RaiseInstanceError('Create dashboard instance mutex', GetLastError);
    WaitResult := WaitForSingleObject(FMutex, 0);
    case WaitResult of
      WAIT_OBJECT_0, WAIT_ABANDONED:
        begin
          // Unlike an existence-only check, ownership recovers after a crashed
          // primary even if another process still holds an open mutex handle.
          FOwnerThreadId := GetCurrentThreadId;
          FIsPrimary := True;
        end;
      WAIT_TIMEOUT:
        FIsPrimary := False;
      WAIT_FAILED:
        RaiseInstanceError('Wait for dashboard instance mutex', GetLastError);
    else
      raise EOSError.CreateFmt('Unexpected instance mutex wait result: %d',
        [WaitResult]);
    end;
  finally
    LocalFree(HLOCAL(SecurityDescriptor));
  end;
{$ELSE}
  FIsPrimary := True;
{$ENDIF}
end;

destructor TDashboardInstance.Destroy;
begin
{$IF Defined(MSWINDOWS)}
  // Constructor exceptions call Destroy too, so every handle is independent.
  // Release only on the owning GUI thread; Windows releases ownership when an
  // owning thread terminates. Cleanup never hides an active constructor error.
  if FMutex <> 0 then
  begin
    if FIsPrimary and (FOwnerThreadId = GetCurrentThreadId) then
      ReleaseMutex(FMutex);
    CloseHandle(FMutex);
    FMutex := 0;
  end;
  if FActivationEvent <> 0 then
  begin
    CloseHandle(FActivationEvent);
    FActivationEvent := 0;
  end;
{$ENDIF}
  inherited;
end;

procedure TDashboardInstance.RequestActivation;
begin
{$IF Defined(MSWINDOWS)}
  if not SetEvent(FActivationEvent) then
    RaiseInstanceError('Request dashboard activation', GetLastError);
{$ENDIF}
end;

function TDashboardInstance.ConsumeActivationRequest: Boolean;
{$IF Defined(MSWINDOWS)}
var
  WaitResult: DWORD;
{$ENDIF}
begin
  Result := False;
{$IF Defined(MSWINDOWS)}
  if not FIsPrimary then
    Exit;
  WaitResult := WaitForSingleObject(FActivationEvent, 0);
  case WaitResult of
    WAIT_OBJECT_0:
      begin
        // Reset before the caller restores the form. Concurrent requests up
        // to this point are covered by the same forthcoming restore action.
        if not ResetEvent(FActivationEvent) then
          RaiseInstanceError('Reset dashboard activation event', GetLastError);
        Result := True;
      end;
    WAIT_TIMEOUT:
      ;
    WAIT_FAILED:
      RaiseInstanceError('Poll dashboard activation event', GetLastError);
  else
    raise EOSError.CreateFmt('Unexpected activation event wait result: %d',
      [WaitResult]);
  end;
{$ENDIF}
end;

end.
