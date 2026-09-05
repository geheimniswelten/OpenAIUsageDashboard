unit Dashboard.Transport;

interface

uses
  Dashboard.Model
{$IF Defined(MSWINDOWS)}
  , System.SyncObjs,
  IdContext,
  IdCustomHTTPServer,
  IdHTTPServer
{$ENDIF}
  ;

type
  TSnapshotPublisher = class
  private
{$IF Defined(MSWINDOWS)}
    FServer: TIdHTTPServer;
    FLock: TCriticalSection;
    FJson: string;
    FToken: string;
    FPort: Integer;
    procedure CommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
{$ENDIF}
  public
    constructor Create(const APort: Integer; const AToken: string);
    destructor Destroy; override;
    function Start(out AError: string): Boolean;
    procedure Stop;
    procedure Publish(const ASnapshot: TUsageSnapshot);
    function IsActive: Boolean;
  end;

function FetchRemoteSnapshot(const AUrl, AToken: string;
  const ASnapshot: TUsageSnapshot; out AError: string): Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.StrUtils,
  System.Net.URLClient,
  System.Net.HttpClient
{$IF Defined(MSWINDOWS)}
  , IdSocketHandle
{$ENDIF}
  ;

function SecureEquals(const A, B: string): Boolean;
var
  I, Difference: Integer;
begin
  Difference := Length(A) xor Length(B);
  for I := 1 to Min(Length(A), Length(B)) do
    Difference := Difference or (Ord(A[I]) xor Ord(B[I]));
  Result := Difference = 0;
end;

{ TSnapshotPublisher }

constructor TSnapshotPublisher.Create(const APort: Integer; const AToken: string);
begin
  inherited Create;
{$IF Defined(MSWINDOWS)}
  FPort := APort;
  FToken := AToken;
  FLock := TCriticalSection.Create;
  FServer := TIdHTTPServer.Create(nil);
  FServer.OnCommandGet := CommandGet;
{$ENDIF}
end;

destructor TSnapshotPublisher.Destroy;
begin
  Stop;
{$IF Defined(MSWINDOWS)}
  FServer.Free;
  FLock.Free;
{$ENDIF}
  inherited;
end;

function TSnapshotPublisher.Start(out AError: string): Boolean;
{$IF Defined(MSWINDOWS)}
var
  Binding: TIdSocketHandle;
{$ENDIF}
begin
  AError := '';
{$IF Defined(MSWINDOWS)}
  try
    if FServer.Active then
      Exit(True);
    FServer.Bindings.Clear;
    Binding := FServer.Bindings.Add;
    if FToken = '' then
      Binding.IP := '127.0.0.1'
    else
      Binding.IP := '0.0.0.0';
    Binding.Port := FPort;
    FServer.Active := True;
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
{$ELSE}
  Result := False;
  AError := 'Der Snapshot-Server steht nur unter Windows zur Verfügung.';
{$ENDIF}
end;

procedure TSnapshotPublisher.Stop;
begin
{$IF Defined(MSWINDOWS)}
  if FServer.Active then
    FServer.Active := False;
{$ENDIF}
end;

procedure TSnapshotPublisher.Publish(const ASnapshot: TUsageSnapshot);
begin
{$IF Defined(MSWINDOWS)}
  if ASnapshot = nil then
    Exit;
  FLock.Acquire;
  try
    FJson := ASnapshot.ToJson;
  finally
    FLock.Release;
  end;
{$ENDIF}
end;

function TSnapshotPublisher.IsActive: Boolean;
begin
{$IF Defined(MSWINDOWS)}
  Result := FServer.Active;
{$ELSE}
  Result := False;
{$ENDIF}
end;

{$IF Defined(MSWINDOWS)}
procedure TSnapshotPublisher.CommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Authorization, SuppliedToken, Body: string;
begin
  if not SameText(ARequestInfo.Document, '/snapshot') then
  begin
    AResponseInfo.ResponseNo := 404;
    AResponseInfo.ContentText := '{"error":"not found"}';
    Exit;
  end;
  SuppliedToken := ARequestInfo.RawHeaders.Values['X-Viewer-Token'];
  Authorization := ARequestInfo.RawHeaders.Values['Authorization'];
  if StartsText('Bearer ', Authorization) then
    SuppliedToken := Copy(Authorization, 8, MaxInt);
  if (FToken <> '') and not SecureEquals(FToken, SuppliedToken) then
  begin
    AResponseInfo.ResponseNo := 401;
    AResponseInfo.ContentType := 'application/json';
    AResponseInfo.CharSet := 'utf-8';
    AResponseInfo.ContentText := '{"error":"unauthorized"}';
    Exit;
  end;
  FLock.Acquire;
  try
    Body := FJson;
  finally
    FLock.Release;
  end;
  if Body = '' then
  begin
    AResponseInfo.ResponseNo := 503;
    AResponseInfo.ContentText := '{"error":"snapshot not ready"}';
  end
  else
  begin
    AResponseInfo.ResponseNo := 200;
    AResponseInfo.ContentText := Body;
  end;
  AResponseInfo.ContentType := 'application/json';
  AResponseInfo.CharSet := 'utf-8';
  AResponseInfo.CacheControl := 'no-store';
end;
{$ENDIF}

function FetchRemoteSnapshot(const AUrl, AToken: string;
  const ASnapshot: TUsageSnapshot; out AError: string): Boolean;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
begin
  Result := False;
  AError := '';
  if Trim(AUrl) = '' then
  begin
    AError := 'Keine Sammler-Adresse konfiguriert.';
    Exit;
  end;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 10000;
    Client.ResponseTimeout := 30000;
    if AToken <> '' then
    begin
      SetLength(Headers, 1);
      Headers[0] := TNetHeader.Create('X-Viewer-Token', AToken);
    end;
    Response := Client.Get(AUrl, nil, Headers);
    Body := Response.ContentAsString(TEncoding.UTF8);
    if (Response.StatusCode < 200) or (Response.StatusCode > 299) then
      raise Exception.CreateFmt('Sammler antwortet mit HTTP %d: %s',
        [Response.StatusCode, Response.StatusText]);
    ASnapshot.FromJson(Body);
    ASnapshot.SourceText := 'Windows-Sammler · schreibgeschützt';
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
  Client.Free;
end;

end.
