unit Dashboard.Secrets;

interface

type
  TSecretStore = class sealed
  public
    class function SaveAdminKey(const AKey: string; out AError: string): Boolean; static;
    class function LoadAdminKey(out AKey, AError: string): Boolean; static;
    class function DeleteAdminKey(out AError: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils
{$IF Defined(MSWINDOWS)}
  , Winapi.Windows,
  Winapi.WinRT,
  Winapi.WinCred,
  Winapi.CommonTypes,
  Winapi.Security.Cryptography
{$ENDIF}
  ;

{$IF Defined(MSWINDOWS)}
const
  CredentialTarget = 'OpenAIUsageDashboard/AdminKey/v1';
  CredentialErrorNotFound = 1168;
  CryptProtectUiForbidden = $00000001;
  EnvelopeVersion = 1;
  NonceSize = 12;
  TagSize = 16;

  { This application-specific key is deliberately embedded.  It is an extra
    separation layer, not the Windows account boundary; DPAPI provides that. }
  ApplicationKey: array[0..31] of Byte = (
    $6E, $39, $A7, $14, $C2, $5B, $80, $DD,
    $43, $F1, $09, $92, $77, $BE, $24, $68,
    $15, $D4, $EA, $31, $9C, $02, $B8, $5F,
    $A1, $73, $46, $CB, $0D, $E7, $98, $2A);

function CryptProtectData(pDataIn: PDATA_BLOB; szDataDescr: LPCWSTR;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer; pPromptStruct: Pointer;
  dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptProtectData';

function CryptUnprotectData(pDataIn: PDATA_BLOB; ppszDataDescr: PPWideChar;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer; pPromptStruct: Pointer;
  dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptUnprotectData';

procedure SecureWipe(var ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    FillChar(ABytes[0], Length(ABytes), 0);
  ABytes := nil;
end;

function BytesToBuffer(const ABytes: TBytes): IBuffer;
begin
  if Length(ABytes) = 0 then
    Result := TCryptographicBuffer.CreateFromByteArray(0, nil)
  else
    Result := TCryptographicBuffer.CreateFromByteArray(Length(ABytes), @ABytes[0]);
end;

function BufferToBytes(const ABuffer: IBuffer): TBytes;
begin
  if ABuffer = nil then
    Exit(nil);
  SetLength(Result, ABuffer.Length);
  if Length(Result) > 0 then
    TCryptographicBuffer.CopyToByteArray(ABuffer, Length(Result), @Result[0]);
end;

function StaticKeyBytes: TBytes;
begin
  SetLength(Result, Length(ApplicationKey));
  Move(ApplicationKey[0], Result[0], Length(Result));
end;

function AuthenticatedData: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('OpenAIUsageDashboard/AdminKey/v1');
end;

function EncryptApplicationLayer(const APlain: TBytes): TBytes;
var
  Provider: Core_ISymmetricKeyAlgorithmProvider;
  Key: Core_ICryptographicKey;
  Encrypted: Core_IEncryptedAndAuthenticatedData;
  KeyBytes, Aad, Nonce, Cipher, Tag: TBytes;
  Offset: Integer;
begin
  KeyBytes := StaticKeyBytes;
  Aad := AuthenticatedData;
  try
    Provider := TCore_SymmetricKeyAlgorithmProvider.OpenAlgorithm(
      TCore_SymmetricAlgorithmNames.AesGcm);
    Key := Provider.CreateSymmetricKey(BytesToBuffer(KeyBytes));
    Nonce := BufferToBytes(TCryptographicBuffer.GenerateRandom(NonceSize));
    Encrypted := TCore_CryptographicEngine.EncryptAndAuthenticate(Key,
      BytesToBuffer(APlain), BytesToBuffer(Nonce), BytesToBuffer(Aad));
    Cipher := BufferToBytes(Encrypted.EncryptedData);
    Tag := BufferToBytes(Encrypted.AuthenticationTag);
    if Length(Tag) <> TagSize then
      raise EInvalidOpException.Create('Unerwartete AES-GCM-Tag-Länge');
    SetLength(Result, 3 + Length(Nonce) + Length(Tag) + Length(Cipher));
    Result[0] := EnvelopeVersion;
    Result[1] := Length(Nonce);
    Result[2] := Length(Tag);
    Offset := 3;
    Move(Nonce[0], Result[Offset], Length(Nonce));
    Inc(Offset, Length(Nonce));
    Move(Tag[0], Result[Offset], Length(Tag));
    Inc(Offset, Length(Tag));
    if Length(Cipher) > 0 then
      Move(Cipher[0], Result[Offset], Length(Cipher));
  finally
    SecureWipe(KeyBytes);
    SecureWipe(Aad);
    SecureWipe(Nonce);
    SecureWipe(Cipher);
    SecureWipe(Tag);
  end;
end;

function DecryptApplicationLayer(const AEnvelope: TBytes): TBytes;
var
  Provider: Core_ISymmetricKeyAlgorithmProvider;
  Key: Core_ICryptographicKey;
  PlainBuffer: IBuffer;
  KeyBytes, Aad, Nonce, Cipher, Tag: TBytes;
  NonceLength, TagLength, Offset: Integer;
begin
  if (Length(AEnvelope) < 3) or (AEnvelope[0] <> EnvelopeVersion) then
    raise EConvertError.Create('Unbekanntes Schlüssel-Format');
  NonceLength := AEnvelope[1];
  TagLength := AEnvelope[2];
  if (NonceLength < 8) or (TagLength < 12) or
     (3 + NonceLength + TagLength > Length(AEnvelope)) then
    raise EConvertError.Create('Beschädigtes Schlüssel-Format');
  SetLength(Nonce, NonceLength);
  SetLength(Tag, TagLength);
  SetLength(Cipher, Length(AEnvelope) - 3 - NonceLength - TagLength);
  Offset := 3;
  Move(AEnvelope[Offset], Nonce[0], NonceLength);
  Inc(Offset, NonceLength);
  Move(AEnvelope[Offset], Tag[0], TagLength);
  Inc(Offset, TagLength);
  if Length(Cipher) > 0 then
    Move(AEnvelope[Offset], Cipher[0], Length(Cipher));
  KeyBytes := StaticKeyBytes;
  Aad := AuthenticatedData;
  try
    Provider := TCore_SymmetricKeyAlgorithmProvider.OpenAlgorithm(
      TCore_SymmetricAlgorithmNames.AesGcm);
    Key := Provider.CreateSymmetricKey(BytesToBuffer(KeyBytes));
    PlainBuffer := TCore_CryptographicEngine.DecryptAndAuthenticate(Key,
      BytesToBuffer(Cipher), BytesToBuffer(Nonce), BytesToBuffer(Tag),
      BytesToBuffer(Aad));
    Result := BufferToBytes(PlainBuffer);
  finally
    SecureWipe(KeyBytes);
    SecureWipe(Aad);
    SecureWipe(Nonce);
    SecureWipe(Cipher);
    SecureWipe(Tag);
  end;
end;

function DpapiProtect(const AInput: TBytes): TBytes;
var
  InBlob, OutBlob: DATA_BLOB;
begin
  Result := nil;
  FillChar(InBlob, SizeOf(InBlob), 0);
  FillChar(OutBlob, SizeOf(OutBlob), 0);
  InBlob.cbData := Length(AInput);
  if Length(AInput) > 0 then
    InBlob.pbData := @AInput[0];
  if not CryptProtectData(@InBlob, 'OpenAI Usage Dashboard', nil, nil, nil,
    CryptProtectUiForbidden, @OutBlob) then
    RaiseLastOSError;
  try
    SetLength(Result, OutBlob.cbData);
    if OutBlob.cbData > 0 then
      Move(OutBlob.pbData^, Result[0], OutBlob.cbData);
  finally
    if OutBlob.pbData <> nil then
      LocalFree(OutBlob.pbData);
  end;
end;

function DpapiUnprotect(const AInput: TBytes): TBytes;
var
  InBlob, OutBlob: DATA_BLOB;
  Description: PWideChar;
begin
  Result := nil;
  Description := nil;
  FillChar(InBlob, SizeOf(InBlob), 0);
  FillChar(OutBlob, SizeOf(OutBlob), 0);
  InBlob.cbData := Length(AInput);
  if Length(AInput) > 0 then
    InBlob.pbData := @AInput[0];
  if not CryptUnprotectData(@InBlob, @Description, nil, nil, nil,
    CryptProtectUiForbidden, @OutBlob) then
    RaiseLastOSError;
  try
    SetLength(Result, OutBlob.cbData);
    if OutBlob.cbData > 0 then
      Move(OutBlob.pbData^, Result[0], OutBlob.cbData);
  finally
    if Description <> nil then
      LocalFree(Description);
    if OutBlob.pbData <> nil then
      LocalFree(OutBlob.pbData);
  end;
end;
{$ENDIF}

class function TSecretStore.SaveAdminKey(const AKey: string; out AError: string): Boolean;
{$IF Defined(MSWINDOWS)}
var
  Plain, Envelope, ProtectedBytes: TBytes;
  Credential: CREDENTIALW;
  Target, UserName: string;
{$ENDIF}
begin
  Result := False;
  AError := '';
{$IF Defined(MSWINDOWS)}
  Plain := TEncoding.UTF8.GetBytes(Trim(AKey));
  try
    if Length(Plain) = 0 then
      raise EArgumentException.Create('Der API-Key ist leer.');
    Envelope := EncryptApplicationLayer(Plain);
    try
      ProtectedBytes := DpapiProtect(Envelope);
      try
        if Length(ProtectedBytes) > CRED_MAX_CREDENTIAL_BLOB_SIZE then
          raise ERangeError.Create('Der geschützte Schlüssel ist zu groß.');
        FillChar(Credential, SizeOf(Credential), 0);
        Target := CredentialTarget;
        UserName := 'OpenAI Organization Admin';
        Credential.&Type := CRED_TYPE_GENERIC;
        Credential.TargetName := PWideChar(Target);
        Credential.CredentialBlobSize := Length(ProtectedBytes);
        Credential.CredentialBlob := @ProtectedBytes[0];
        Credential.Persist := CRED_PERSIST_LOCAL_MACHINE;
        Credential.UserName := PWideChar(UserName);
        if not CredWriteW(@Credential, 0) then
          RaiseLastOSError;
        Result := True;
      finally
        SecureWipe(ProtectedBytes);
      end;
    finally
      SecureWipe(Envelope);
    end;
  except
    on E: Exception do
      AError := E.Message;
  end;
  SecureWipe(Plain);
{$ELSE}
  AError := 'Der OpenAI-Admin-Key wird nur auf dem Windows-Sammler gespeichert.';
{$ENDIF}
end;

class function TSecretStore.LoadAdminKey(out AKey, AError: string): Boolean;
{$IF Defined(MSWINDOWS)}
var
  Credential: PCREDENTIALW;
  ProtectedBytes, Envelope, Plain: TBytes;
{$ENDIF}
begin
  Result := False;
  AKey := '';
  AError := '';
{$IF Defined(MSWINDOWS)}
  Credential := nil;
  try
    if not CredReadW(PWideChar(CredentialTarget), CRED_TYPE_GENERIC, 0, Credential) then
    begin
      if GetLastError = CredentialErrorNotFound then
        AError := 'Noch kein OpenAI-Admin-Key gespeichert.'
      else
        AError := SysErrorMessage(GetLastError);
      Exit;
    end;
    SetLength(ProtectedBytes, Credential.CredentialBlobSize);
    if Length(ProtectedBytes) > 0 then
      Move(Credential.CredentialBlob^, ProtectedBytes[0], Length(ProtectedBytes));
    Envelope := DpapiUnprotect(ProtectedBytes);
    try
      Plain := DecryptApplicationLayer(Envelope);
      try
        AKey := TEncoding.UTF8.GetString(Plain);
        Result := AKey <> '';
      finally
        SecureWipe(Plain);
      end;
    finally
      SecureWipe(Envelope);
      SecureWipe(ProtectedBytes);
    end;
  except
    on E: Exception do
      AError := E.Message;
  end;
  if Credential <> nil then
    CredFree(Credential);
{$ELSE}
  AError := 'Android verwendet ausschließlich den schreibgeschützten Sammler-Endpunkt.';
{$ENDIF}
end;

class function TSecretStore.DeleteAdminKey(out AError: string): Boolean;
begin
  AError := '';
{$IF Defined(MSWINDOWS)}
  Result := CredDeleteW(PWideChar(CredentialTarget), CRED_TYPE_GENERIC, 0);
  if not Result then
  begin
    if GetLastError = CredentialErrorNotFound then
      Result := True
    else
      AError := SysErrorMessage(GetLastError);
  end;
{$ELSE}
  Result := True;
{$ENDIF}
end;

end.
