unit Dashboard.Pricing;

interface

uses System.JSON, Dashboard.ModelReference;

function GetModelPriceCatalog(const ARefresh: Boolean = False;
  const ACacheFile: string = ''): TModelPriceCatalog;
function ModelPriceCatalogToJson(const ACatalog: TModelPriceCatalog): TJSONObject;
function ModelPriceCatalogFromJson(const AObject: TJSONObject): TModelPriceCatalog;
function ParseStandardPricing(const Markdown: string): TModelPriceCatalog;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils, System.Math,
  System.Net.HttpClient, System.Generics.Collections, System.Generics.Defaults,
  System.Types{$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const
  PricingURL = 'https://developers.openai.com/api/docs/pricing.md';
  MaxPricingBytes = 2 * 1024 * 1024;

type
  TLimitedStream = class(TMemoryStream)
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

function TLimitedStream.Write(const Buffer; Count: Longint): Longint;
begin
  if (Count < 0) or (Position + Count > MaxPricingBytes) then
    raise EStreamError.Create('Pricing response too large');
  Result := inherited Write(Buffer, Count);
end;

function CanonicalId(const S: string): string;
var I: Integer;
begin
  Result := LowerCase(Trim(S));
  I := Pos(' ', Result);
  if I > 0 then Result := Copy(Result, 1, I - 1);
  if Result = '' then raise EConvertError.Create('Empty model ID');
  for I := 1 to Length(Result) do
    if not CharInSet(Result[I], ['a'..'z', '0'..'9', '-', '.']) then
      raise EConvertError.Create('Invalid model ID');
end;

function DisplayName(const Id: string): string;
var Parts: TArray<string>; I: Integer; P: string;
begin
  Parts := Id.Split(['-']);
  Result := '';
  for I := 0 to High(Parts) do begin
    P := Parts[I];
    if P = 'gpt' then P := 'GPT'
    else if P = 'codex' then P := 'Codex'
    else if (P = 'astra') or (P = 'sol') or (P = 'terra') or (P = 'luna') then
      P := UpperCase(P[1]) + Copy(P, 2, MaxInt);
    if Result <> '' then begin
      if (I = 1) and (Parts[0] = 'gpt') then Result := Result + '-'
      else Result := Result + ' ';
    end;
    Result := Result + P;
  end;
end;

function Price(const S: string): Double;
var V: string; F: TFormatSettings; I: Integer; Dots: Integer;
begin
  V := Trim(S);
  if (Length(V) < 2) or (V[1] <> '$') then raise EConvertError.Create('Invalid price');
  Delete(V, 1, 1); Dots := 0;
  for I := 1 to Length(V) do begin
    if V[I] = '.' then Inc(Dots)
    else if not CharInSet(V[I], ['0'..'9']) then raise EConvertError.Create('Invalid price');
  end;
  if Dots > 1 then raise EConvertError.Create('Invalid price');
  F := TFormatSettings.Invariant;
  if not TryStrToFloat(V, Result, F) or IsNan(Result) or IsInfinite(Result) or (Result < 0) then
    raise EConvertError.Create('Invalid price');
end;

function Family(const Id: string): Integer;
begin
  if Id.EndsWith('-astra') then Exit(1);
  if Id.EndsWith('-sol') then Exit(2);
  if Id.EndsWith('-terra') then Exit(3);
  if Id.EndsWith('-luna') then Exit(4);
  Result := 0;
end;

function Version(const Id: string): Double;
var P, V: TArray<string>; Major, Minor: Integer;
begin
  Result := -1; P := Id.Split(['-']);
  if (Length(P) < 2) or (P[0] <> 'gpt') then Exit;
  V := P[1].Split(['.']);
  if (Length(V) < 1) or (Length(V) > 2) or not TryStrToInt(V[0], Major) or
    (Major < 0) or (Major > 10000) then Exit;
  Minor := 0;
  if Length(V) = 2 then
    if not TryStrToInt(V[1], Minor) or (Minor < 0) or (Minor > 999999) then Exit;
  Result := Major * 1000000.0 + Minor;
end;
procedure SortModels(var Models: TArray<TModelReference>);
var Heads: array[1..4] of Double; M: TModelReference; F, I: Integer;
begin
  for I := 1 to 4 do Heads[I] := -1;
  for M in Models do begin
    F := Family(M.ModelId);
    if (F > 0) and (Version(M.ModelId) > Heads[F]) then Heads[F] := Version(M.ModelId);
  end;
  TArray.Sort<TModelReference>(Models, TComparer<TModelReference>.Construct(
    function(const L, R: TModelReference): Integer
    var LF, RF: Integer; LH, RH: Boolean; LV, RV: Double;
    begin
      LF := Family(L.ModelId); RF := Family(R.ModelId);
      LV := Version(L.ModelId); RV := Version(R.ModelId);
      LH := (LF > 0) and (LV >= 0); RH := (RF > 0) and (RV >= 0);
      if LH then LH := LV = Heads[LF];
      if RH then RH := RV = Heads[RF];
      if LH <> RH then begin if LH then Exit(-1) else Exit(1) end;
      if LH and RH then begin
        if LV > RV then Exit(-1); if LV < RV then Exit(1);
        Exit(LF - RF);
      end;
      if LV > RV then Exit(-1); if LV < RV then Exit(1);
      Result := CompareText(L.ModelId, R.ModelId);
    end));
end;

function ParseStandardPricing(const Markdown: string): TModelPriceCatalog;
var Lines, Cells: TArray<string>; Line, RawLine, Id: string; InSection, Header, Seen: Boolean;
    List: TList<TModelReference>; Ids: TDictionary<string, Boolean>;
    M, B: TModelReference; Built: TArray<TModelReference>;
begin
  Result := Default(TModelPriceCatalog);
  Lines := Markdown.Replace(#13, '').Split([#10]);
  List := TList<TModelReference>.Create; Ids := TDictionary<string, Boolean>.Create;
  try
    InSection := False; Header := False; Seen := False;
    Built := GetModelReferences;
    for RawLine in Lines do begin
      Line := Trim(RawLine);
      if Line.StartsWith('### ') then begin
        if InSection then Break;
        if SameText(Line, '### Standard pricing data') then begin
          if Seen then raise EConvertError.Create('Duplicate standard section');
          InSection := True; Seen := True;
        end;
        Continue;
      end;
      if not InSection or not Line.StartsWith('|') then Continue;
      Cells := Line.Split(['|']);
      if Length(Cells) < 5 then raise EConvertError.Create('Malformed table');
      if SameText(Trim(Cells[1]), 'Model') then begin
        Header := ((SameText(Trim(Cells[2]), 'Short context input') and SameText(Trim(Cells[3]), 'Short context output')) or
          (SameText(Trim(Cells[2]), 'Input') and SameText(Trim(Cells[3]), 'Output')));
        if not Header then raise EConvertError.Create('Unexpected pricing columns');
        Continue;
      end;
      if Trim(Cells[1]).StartsWith('---') then Continue;
      if not Header then raise EConvertError.Create('Missing pricing header');
      Id := CanonicalId(Cells[1]);
      if Ids.ContainsKey(Id) then raise EConvertError.Create('Duplicate model');
      M := Default(TModelReference); M.ModelId := Id; M.Name := DisplayName(Id);
      M.PriceAvailable := True; M.InputPerMillion := Price(Cells[2]);
      M.OutputPerMillion := Price(Cells[3]); M.Intelligence := -1;
      for B in Built do if SameText(B.ModelId, Id) then begin M.Intelligence := B.Intelligence; Break end;
      Ids.Add(Id, True); List.Add(M);
    end;
    if not Seen or (List.Count = 0) then raise EConvertError.Create('Missing standard pricing');
    for B in Built do if not Ids.ContainsKey(B.ModelId) then begin
      M := B; M.PriceAvailable := False; List.Add(M);
    end;
    Result.Models := List.ToArray; SortModels(Result.Models);
    Result.UpdatedAt := TTimeZone.Local.ToUniversalTime(Now);
    Result.StatusText := 'OpenAI Standardpreise';
  finally Ids.Free; List.Free end;
end;

function ModelPriceCatalogToJson(const ACatalog: TModelPriceCatalog): TJSONObject;
var Arr: TJSONArray; O: TJSONObject; M: TModelReference;
begin
  Result := TJSONObject.Create;
  Result.AddPair('updatedAt', TJSONNumber.Create(Double(ACatalog.UpdatedAt)));
  Result.AddPair('statusText', ACatalog.StatusText);
  Arr := TJSONArray.Create; Result.AddPair('models', Arr);
  for M in ACatalog.Models do begin
    O := TJSONObject.Create; Arr.AddElement(O);
    O.AddPair('modelId', M.ModelId); O.AddPair('name', M.Name);
    O.AddPair('priceAvailable', TJSONBool.Create(M.PriceAvailable));
    O.AddPair('inputPerMillion', TJSONNumber.Create(M.InputPerMillion));
    O.AddPair('outputPerMillion', TJSONNumber.Create(M.OutputPerMillion));
    O.AddPair('intelligence', TJSONNumber.Create(M.Intelligence));
  end;
end;

function ModelPriceCatalogFromJson(const AObject: TJSONObject): TModelPriceCatalog;
var Arr: TJSONArray; V: TJSONValue; O: TJSONObject; M: TModelReference; L: TList<TModelReference>;
    IDs: TDictionary<string, Boolean>; D: Double; S: string;
begin
  if AObject = nil then Exit(GetBuiltInPriceCatalog);
  L := TList<TModelReference>.Create; IDs := TDictionary<string, Boolean>.Create;
  try
    if not (AObject.GetValue('models') is TJSONArray) then raise EConvertError.Create('Missing models');
    Arr := TJSONArray(AObject.GetValue('models'));
    if not (AObject.GetValue('updatedAt') is TJSONNumber) then raise EConvertError.Create('Missing date');
    D := TJSONNumber(AObject.GetValue('updatedAt')).AsDouble;
    if IsNan(D) or IsInfinite(D) or (D < 0) or (D > 2958465) then raise EConvertError.Create('Invalid date');
    Result.UpdatedAt := D;
    if not (AObject.GetValue('statusText') is TJSONString) then raise EConvertError.Create('Missing status');
    Result.StatusText := AObject.GetValue('statusText').Value;
    for V in Arr do begin
      if not (V is TJSONObject) then raise EConvertError.Create('Invalid model');
      O := TJSONObject(V); M := Default(TModelReference);
      if not (O.GetValue('modelId') is TJSONString) or not (O.GetValue('name') is TJSONString) or
        not (O.GetValue('priceAvailable') is TJSONBool) or
        not (O.GetValue('inputPerMillion') is TJSONNumber) or not (O.GetValue('outputPerMillion') is TJSONNumber) or
        not (O.GetValue('intelligence') is TJSONNumber) then raise EConvertError.Create('Invalid model fields');
      S := O.GetValue('modelId').Value; M.ModelId := CanonicalId(S);
      if M.ModelId <> S then raise EConvertError.Create('Invalid canonical ID');
      M.Name := O.GetValue('name').Value; if Trim(M.Name) = '' then raise EConvertError.Create('Empty name');
      M.PriceAvailable := TJSONBool(O.GetValue('priceAvailable')).AsBoolean;
      M.InputPerMillion := TJSONNumber(O.GetValue('inputPerMillion')).AsDouble;
      M.OutputPerMillion := TJSONNumber(O.GetValue('outputPerMillion')).AsDouble;
      D := TJSONNumber(O.GetValue('intelligence')).AsDouble;
      if IsNan(M.InputPerMillion) or IsInfinite(M.InputPerMillion) or (M.InputPerMillion < 0) or
         IsNan(M.OutputPerMillion) or IsInfinite(M.OutputPerMillion) or (M.OutputPerMillion < 0) or
         IsNan(D) or IsInfinite(D) or (D < -1) or (D > 1000) or (Frac(D) <> 0) then raise EConvertError.Create('Invalid values');
      M.Intelligence := Trunc(D);
      if IDs.ContainsKey(M.ModelId) then raise EConvertError.Create('Duplicate model');
      IDs.Add(M.ModelId, True); L.Add(M);
    end;
    if L.Count = 0 then raise EConvertError.Create('Empty catalog');
    Result.Models := L.ToArray;
  finally IDs.Free; L.Free end;
end;

function CachePath(const Override: string): string;
begin
  Result := Override;
  if Result = '' then
    {$IFDEF MSWINDOWS}
    Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'OpenAIUsageDashboard'), 'openai-pricing.json');
    {$ELSE}
    Result := TPath.Combine(TPath.GetDocumentsPath, 'openai-pricing.json');
    {$ENDIF}
end;

procedure AtomicWrite(const Path, Data: string);
var Temp: string;
begin
  ForceDirectories(ExtractFileDir(Path));
  Temp := Path + '.' + TGUID.NewGuid.ToString + '.tmp';
  try
    TFile.WriteAllText(Temp, Data, TEncoding.UTF8);
    {$IFDEF MSWINDOWS}
    if not MoveFileEx(PChar(Temp), PChar(Path), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    {$ELSE}
    if not RenameFile(Temp, Path) then raise EInOutError.Create('Could not replace pricing cache');
    {$ENDIF}
  finally if TFile.Exists(Temp) then TFile.Delete(Temp) end;
end;

function GetModelPriceCatalog(const ARefresh: Boolean; const ACacheFile: string): TModelPriceCatalog;
var Path, Attempt, Data: string; V: TJSONValue; O: TJSONObject; Client: THTTPClient;
    NowUTC: TDateTime; LastAttempt: Double; NewCatalog: TModelPriceCatalog; Resp: IHTTPResponse;
    HaveGoodCache: Boolean; Stream: TLimitedStream; Bytes: TBytes;
begin
  Result := GetBuiltInPriceCatalog; HaveGoodCache := False; Path := CachePath(ACacheFile); Attempt := Path + '.attempt';
  try
    if TFile.Exists(Path) then begin
      V := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
      try
        if not (V is TJSONObject) then raise EConvertError.Create('Invalid cache');
        Result := ModelPriceCatalogFromJson(TJSONObject(V)); HaveGoodCache := True;
      finally V.Free end;
    end;
  except Result := GetBuiltInPriceCatalog end;
  if not ARefresh then Exit;
  NowUTC := TTimeZone.Local.ToUniversalTime(Now);
  if HaveGoodCache and (Result.UpdatedAt > 0) and (NowUTC >= Result.UpdatedAt) and (NowUTC - Result.UpdatedAt < 1) then Exit;
  try
    if TFile.Exists(Attempt) then begin
      Data := Trim(TFile.ReadAllText(Attempt, TEncoding.UTF8));
      if TryStrToFloat(Data, LastAttempt, TFormatSettings.Invariant) and
        (NowUTC >= LastAttempt) and (NowUTC - LastAttempt < 1/24) then Exit;
    end;
  except end;
  try AtomicWrite(Attempt, FloatToStr(Double(NowUTC), TFormatSettings.Invariant)) except end;
  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := 5000; Client.ResponseTimeout := 10000;
      Stream := TLimitedStream.Create;
      try
        Resp := Client.Get(PricingURL, Stream);
        if Resp.StatusCode <> 200 then raise EConvertError.Create('HTTP error');
        SetLength(Bytes, Stream.Size);
        Stream.Position := 0;
        if Length(Bytes) > 0 then Stream.ReadBuffer(Bytes[0], Length(Bytes));
        NewCatalog := ParseStandardPricing(TEncoding.UTF8.GetString(Bytes));
      finally Stream.Free end;
      O := ModelPriceCatalogToJson(NewCatalog);
      try try AtomicWrite(Path, O.ToJSON) except end finally O.Free end;
      Result := NewCatalog;
    finally Client.Free end;
  except
    Result.StatusText := Result.StatusText + ' (Aktualisierung fehlgeschlagen)';
  end;
end;

end.
