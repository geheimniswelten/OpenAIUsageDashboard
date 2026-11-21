unit Dashboard.ModelMetadata;

interface

uses System.SysUtils, Dashboard.ModelReference;

procedure EnrichModelCatalog(var ACatalog: TModelPriceCatalog; const ARefresh: Boolean;
  const AModelListLoader: TFunc<string> = nil; const ACacheFile: string = '');
procedure ApplyModelListJson(var ACatalog: TModelPriceCatalog; const Data: string; const NowUTC: TDateTime);
function ParseModelCard(const Id, Markdown: string; var M: TModelMetadata): Boolean;
procedure ApplyDeprecations(var ACatalog: TModelPriceCatalog; const Markdown: string; const NowUTC: TDateTime);

implementation

uses System.Classes, System.IOUtils, System.DateUtils, System.JSON,
  System.RegularExpressions, System.Net.HttpClient, System.Diagnostics, Dashboard.Pricing
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const BaseURL = 'https://developers.openai.com/api/docs/';

function DateString(const S: string): TDateTime;
var Y, M, D, I: Integer; T: string; R: TMatch;
const Months: array[1..12] of string = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
begin
  Result := 0; T := Trim(S);
  R := TRegEx.Match(T, '^(\d{4})-(\d{2})-(\d{2})$');
  if R.Success then begin Y := StrToIntDef(R.Groups[1].Value, 0); M := StrToIntDef(R.Groups[2].Value, 0); D := StrToIntDef(R.Groups[3].Value, 0) end
  else begin
    R := TRegEx.Match(T, '^([A-Za-z]{3}) (\d{1,2}), (\d{4})$'); if not R.Success then Exit;
    M := 0; for I := 1 to 12 do if SameText(R.Groups[1].Value, Months[I]) then M := I;
    D := StrToIntDef(R.Groups[2].Value, 0); Y := StrToIntDef(R.Groups[3].Value, 0);
  end;
  if (Y < 2000) or (Y > 2200) or not TryEncodeDate(Y, M, D, Result) then Result := 0;
end;

procedure Seed(var C: TModelPriceCatalog);
var I: Integer; M: TModelMetadata;
begin
  for I := 0 to High(C.Models) do begin
    M := Default(TModelMetadata);
    if C.Models[I].ModelId = 'gpt-6.2-astra' then begin
      M.PublishedAt := EncodeDate(2026, 11, 17); M.KnowledgeCutoff := EncodeDate(2026, 5, 18);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-6.2-sol' then begin
      M.PublishedAt := EncodeDate(2026, 11, 17); M.KnowledgeCutoff := EncodeDate(2026, 6, 1);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-6-astra' then begin
      M.PublishedAt := EncodeDate(2026, 9, 3); M.KnowledgeCutoff := EncodeDate(2026, 4, 30);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-6.1-sol' then begin
      M.PublishedAt := EncodeDate(2026, 9, 29); M.KnowledgeCutoff := EncodeDate(2026, 4, 30);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-6.1-terra' then begin
      M.PublishedAt := EncodeDate(2026, 10, 26); M.KnowledgeCutoff := EncodeDate(2026, 6, 1);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-6-luna' then begin
      M.PublishedAt := EncodeDate(2026, 9, 22); M.KnowledgeCutoff := EncodeDate(2026, 5, 18);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-5.6-sol' then begin
      M.PublishedAt := EncodeDate(2026, 7, 9); M.KnowledgeCutoff := EncodeDate(2026, 2, 16);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-5.6-terra' then begin
      M.PublishedAt := EncodeDate(2026, 7, 9); M.KnowledgeCutoff := EncodeDate(2026, 2, 16);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-5.4-mini' then begin
      M.PublishedAt := EncodeDate(2026, 3, 17); M.KnowledgeCutoff := EncodeDate(2025, 8, 31);
      M.ContextTokens := 400000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-5.3-codex' then begin
      M.PublishedAt := EncodeDate(2026, 2, 24); M.KnowledgeCutoff := EncodeDate(2025, 8, 31);
      M.ContextTokens := 400000; M.MaxOutputTokens := 128000;
      M.Status := 'deprecated'; M.ShutdownAt := EncodeDate(2027, 4, 1); M.ShutdownKnown := True;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    else if C.Models[I].ModelId = 'gpt-5.4' then begin
      M.PublishedAt := EncodeDate(2026, 3, 5); M.KnowledgeCutoff := EncodeDate(2025, 8, 31);
      M.ContextTokens := 1050000; M.MaxOutputTokens := 128000;
      M.ModalitiesKnown := True; M.InputModalities := [mmText, mmImage]; M.OutputModalities := [mmText];
      M.SourceURL := BaseURL + 'models/' + C.Models[I].ModelId; M.RetrievedAt := EncodeDate(2026, 11, 21);
    end
    ;
    if M.PublishedAt > 0 then begin
      if C.Models[I].Metadata.PublishedAt = 0 then C.Models[I].Metadata.PublishedAt := M.PublishedAt;
      if C.Models[I].Metadata.KnowledgeCutoff = 0 then C.Models[I].Metadata.KnowledgeCutoff := M.KnowledgeCutoff;
      if C.Models[I].Metadata.ContextTokens = 0 then C.Models[I].Metadata.ContextTokens := M.ContextTokens;
      if C.Models[I].Metadata.MaxOutputTokens = 0 then C.Models[I].Metadata.MaxOutputTokens := M.MaxOutputTokens;
      if not C.Models[I].Metadata.ModalitiesKnown then begin C.Models[I].Metadata.ModalitiesKnown := M.ModalitiesKnown; C.Models[I].Metadata.InputModalities := M.InputModalities; C.Models[I].Metadata.OutputModalities := M.OutputModalities end;
      if C.Models[I].Metadata.Status = '' then C.Models[I].Metadata.Status := M.Status;
      if not C.Models[I].Metadata.ShutdownKnown then begin C.Models[I].Metadata.ShutdownKnown := M.ShutdownKnown; C.Models[I].Metadata.ShutdownAt := M.ShutdownAt end;
      if C.Models[I].Metadata.SourceURL = '' then C.Models[I].Metadata.SourceURL := M.SourceURL;
      if C.Models[I].Metadata.RetrievedAt = 0 then C.Models[I].Metadata.RetrievedAt := M.RetrievedAt;
    end;
  end;
end;

function ParseModelCard(const Id, Markdown: string; var M: TModelMetadata): Boolean;
var R: TMatch; S: string; N: Int64; Input, Output: TModelModalities;
  function Modalities(const V: string): TModelModalities;
  var P, Item: string;
  begin
    Result := [];
    for P in LowerCase(V).Split([',']) do begin
      Item := Trim(P);
      if Item = 'text' then Include(Result, mmText)
      else if Item = 'image' then Include(Result, mmImage)
      else if Item = 'audio' then Include(Result, mmAudio)
      else if Item = 'video' then Include(Result, mmVideo);
    end;
  end;
  function Number(const Pattern: string): Int64;
  begin
    Result := 0; R := TRegEx.Match(Markdown, Pattern, [roIgnoreCase, roMultiLine]);
    if R.Success then begin S := R.Groups[1].Value.Replace(',', '');
      if not TryStrToInt64(S, Result) or (Result < 1) or (Result > 10000000000) then Result := 0;
    end;
  end;
begin
  Result := False;
  R := TRegEx.Match(Markdown, '(?m)^Model ID:\s*`([^`]+)`\s*$');
  if not R.Success or (R.Groups[1].Value <> Id) then Exit;
  N := Number('(?m)^-\s*([0-9,]+) context window'); if N > 0 then M.ContextTokens := N;
  N := Number('(?m)^-\s*([0-9,]+) max output tokens'); if N > 0 then M.MaxOutputTokens := N;
  R := TRegEx.Match(Markdown, '(?m)^-\s*([A-Za-z]{3} [0-9]{1,2}, [0-9]{4}) knowledge cutoff', [roIgnoreCase]);
  if R.Success then begin N := Trunc(DateString(R.Groups[1].Value)); if N > 0 then M.KnowledgeCutoff := N end;
  R := TRegEx.Match(Markdown, '(?m)^-\s*Input modalities:\s*([^\r\n]+)', [roIgnoreCase]);
  if R.Success then begin
    Input := Modalities(R.Groups[1].Value);
    R := TRegEx.Match(Markdown, '(?m)^-\s*Output modalities:\s*([^\r\n]+)', [roIgnoreCase]);
    if R.Success then begin Output := Modalities(R.Groups[1].Value);
      if (Input <> []) and (Output <> []) then begin M.InputModalities := Input; M.OutputModalities := Output; M.ModalitiesKnown := True end;
    end;
  end;
  M.SourceURL := BaseURL + 'models/' + Id + '.md'; Result := True;
end;

procedure ApplyModelListJson(var ACatalog: TModelPriceCatalog; const Data: string; const NowUTC: TDateTime);
var Root, V, D: TJSONValue; O: TJSONObject; A: TJSONArray; I: Integer; Id: string; Seconds: Int64; Dt: TDateTime;
begin
  Root := TJSONObject.ParseJSONValue(Data);
  try
    if not (Root is TJSONObject) then Exit;
    V := TJSONObject(Root).GetValue('data'); if not (V is TJSONArray) then Exit; A := TJSONArray(V);
    for V in A do begin
      if not (V is TJSONObject) then Continue; O := TJSONObject(V);
      D := O.GetValue('id'); if not (D is TJSONString) then Continue; Id := D.Value;
      D := O.GetValue('shutdown_date'); if D = nil then Continue;
      for I := 0 to High(ACatalog.Models) do if ACatalog.Models[I].ModelId = Id then begin
        if D is TJSONNull then begin
          if ACatalog.Models[I].Metadata.ShutdownAt = 0 then ACatalog.Models[I].Metadata.ShutdownKnown := True;
        end
        else begin
          Dt := 0;
          if D is TJSONString then Dt := DateString(D.Value)
          else if (D is TJSONNumber) and TryStrToInt64(D.Value, Seconds) and
            (Seconds > 946684800) and (Seconds < 7289654400) then Dt := UnixToDateTime(Seconds, True);
          if Dt > 0 then begin
            ACatalog.Models[I].Metadata.ShutdownKnown := True;
            ACatalog.Models[I].Metadata.ShutdownAt := Dt;
            if Trunc(Dt) < Trunc(NowUTC) then ACatalog.Models[I].Metadata.Status := 'shutdown'
            else ACatalog.Models[I].Metadata.Status := 'deprecated';
          end;
        end;
        Break;
      end;
    end;
  finally Root.Free end;
end;

procedure ApplyDeprecations(var ACatalog: TModelPriceCatalog; const Markdown: string; const NowUTC: TDateTime);
var Cells: TArray<string>; Line, IDs, Id: string; R: TMatch; Dt: TDateTime; I: Integer;
begin
  for Line in Markdown.Replace(#13, '').Split([#10]) do begin
    Cells := Line.Split(['|']); if Length(Cells) < 5 then Continue;
    R := TRegEx.Match(Cells[1], '([A-Za-z]{3} [0-9]{1,2}, [0-9]{4})'); if not R.Success then Continue;
    Dt := DateString(R.Groups[1].Value); if Dt = 0 then Continue;
    if not SameText(Trim(Cells[3]), 'Deprecated') and not SameText(Trim(Cells[3]), 'Shut down') then Continue;
    IDs := Cells[2]; R := TRegEx.Match(IDs, '`([^`]+)`');
    while R.Success do begin
      Id := R.Groups[1].Value;
      for I := 0 to High(ACatalog.Models) do if ACatalog.Models[I].ModelId = Id then begin
        ACatalog.Models[I].Metadata.ShutdownKnown := True; ACatalog.Models[I].Metadata.ShutdownAt := Dt;
        if (Trunc(Dt) < Trunc(NowUTC)) or SameText(Trim(Cells[3]), 'Shut down') then ACatalog.Models[I].Metadata.Status := 'shutdown'
        else ACatalog.Models[I].Metadata.Status := 'deprecated'; Break;
      end;
      R := R.NextMatch;
    end;
  end;
end;

procedure ApplyModelListing(var C: TModelPriceCatalog; const Data: string);
var Line, Id, Description: string; R: TMatch; DeprecatedSection: Boolean; I: Integer;
begin
  DeprecatedSection := False;
  for Line in Data.Replace(#13, '').Split([#10]) do begin
    if Line.StartsWith('## ') then begin DeprecatedSection := SameText(Trim(Line), '## Deprecated models'); Continue end;
    R := TRegEx.Match(Line, '^- \[[^\]]+\]\(/api/docs/models/([a-z0-9.-]+)\.md\):\s*(.*)$');
    if not R.Success then Continue;
    Id := R.Groups[1].Value; Description := R.Groups[2].Value;
    for I := 0 to High(C.Models) do if C.Models[I].ModelId = Id then begin
      if DeprecatedSection then begin
        if Description.StartsWith('Shut down.') then C.Models[I].Metadata.Status := 'shutdown'
        else if Description.StartsWith('Deprecated.') and (C.Models[I].Metadata.Status <> 'shutdown') then C.Models[I].Metadata.Status := 'deprecated';
      end else if (C.Models[I].Metadata.Status = '') then C.Models[I].Metadata.Status := 'active';
      Break;
    end;
  end;
end;

function CachePath(const Override: string): string;
begin
  Result := Override; if Result <> '' then Exit;
  {$IFDEF MSWINDOWS}
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'OpenAIUsageDashboard'), 'model-metadata.json');
  {$ELSE}
  Result := TPath.Combine(TPath.GetDocumentsPath, 'model-metadata.json');
  {$ENDIF}
end;

procedure AtomicWrite(const Path, Data: string);
var Temp: string;
begin
  ForceDirectories(ExtractFileDir(Path)); Temp := Path + '.' + TGUID.NewGuid.ToString + '.tmp';
  try
    TFile.WriteAllText(Temp, Data, TEncoding.UTF8);
    {$IFDEF MSWINDOWS}
    if not MoveFileEx(PChar(Temp), PChar(Path), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    {$ELSE}
    if not RenameFile(Temp, Path) then raise EInOutError.Create('Cache replacement failed');
    {$ENDIF}
  finally if TFile.Exists(Temp) then TFile.Delete(Temp) end;
end;

type
  TBoundedStream = class(TMemoryStream)
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

function TBoundedStream.Write(const Buffer; Count: Longint): Longint;
begin
  if (Count < 0) or (Position + Count > 2097152) then raise EStreamError.Create('Response too large');
  Result := inherited Write(Buffer, Count);
end;

function Download(const URL: string): string;
var C: THTTPClient; S: TBoundedStream; R: IHTTPResponse; B: TBytes;
begin
  C := THTTPClient.Create; S := TBoundedStream.Create;
  try
    C.ConnectionTimeout := 1500; C.ResponseTimeout := 2000; R := C.Get(URL, S);
    if (R.StatusCode <> 200) or (S.Size > 2097152) then raise EConvertError.Create('Invalid HTTP response');
    SetLength(B, S.Size); S.Position := 0; if Length(B) > 0 then S.ReadBuffer(B[0], Length(B));
    Result := TEncoding.UTF8.GetString(B);
  finally S.Free; C.Free end;
end;

procedure EnrichModelCatalog(var ACatalog: TModelPriceCatalog; const ARefresh: Boolean;
  const AModelListLoader: TFunc<string>; const ACacheFile: string);
var Path, Data: string; V: TJSONValue; Old: TModelPriceCatalog; I, J: Integer;
  NowUTC: TDateTime; Attempt: Double; O: TJSONObject; Watch: TStopwatch; M: TModelMetadata; Any: Boolean;
begin
  Seed(ACatalog); Path := CachePath(ACacheFile); NowUTC := TTimeZone.Local.ToUniversalTime(Now);
  try
    if TFile.Exists(Path) and (TFile.GetSize(Path) <= 2097152) then begin
      V := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
      try
        if V is TJSONObject then begin
          Old := ModelPriceCatalogFromJson(TJSONObject(V));
          for I := 0 to High(ACatalog.Models) do for J := 0 to High(Old.Models) do
            if ACatalog.Models[I].ModelId = Old.Models[J].ModelId then begin
              M := Old.Models[J].Metadata;
              if M.PublishedAt = 0 then M.PublishedAt := ACatalog.Models[I].Metadata.PublishedAt;
              if M.KnowledgeCutoff = 0 then M.KnowledgeCutoff := ACatalog.Models[I].Metadata.KnowledgeCutoff;
              if M.ContextTokens = 0 then M.ContextTokens := ACatalog.Models[I].Metadata.ContextTokens;
              if M.MaxOutputTokens = 0 then M.MaxOutputTokens := ACatalog.Models[I].Metadata.MaxOutputTokens;
              if not M.ModalitiesKnown then begin M.ModalitiesKnown := ACatalog.Models[I].Metadata.ModalitiesKnown; M.InputModalities := ACatalog.Models[I].Metadata.InputModalities; M.OutputModalities := ACatalog.Models[I].Metadata.OutputModalities end;
              if M.Status = '' then M.Status := ACatalog.Models[I].Metadata.Status;
              if not M.ShutdownKnown then begin M.ShutdownKnown := ACatalog.Models[I].Metadata.ShutdownKnown; M.ShutdownAt := ACatalog.Models[I].Metadata.ShutdownAt end;
              ACatalog.Models[I].Metadata := M; Break;
            end;
        end;
      finally V.Free end;
    end;
  except end;
  for I := 0 to High(ACatalog.Models) do
    if ACatalog.Models[I].Metadata.ShutdownKnown and (ACatalog.Models[I].Metadata.ShutdownAt > 0) and (Trunc(ACatalog.Models[I].Metadata.ShutdownAt) < Trunc(NowUTC)) then ACatalog.Models[I].Metadata.Status := 'shutdown';
  if not ARefresh then Exit;
  Watch := TStopwatch.StartNew; Any := False;
  if Watch.ElapsedMilliseconds < 6500 then try
    Attempt := 0;
    if TFile.Exists(Path + '.listing') then TryStrToFloat(TFile.ReadAllText(Path + '.listing', TEncoding.UTF8), Attempt, TFormatSettings.Invariant);
    if (Attempt = 0) or (NowUTC - Attempt >= 1/24) then begin
      try AtomicWrite(Path + '.listing', FloatToStr(Double(NowUTC), TFormatSettings.Invariant)) except end;
      Data := Download(BaseURL + 'models/all.md'); ApplyModelListing(ACatalog, Data); Any := True;
      try AtomicWrite(Path + '.listing', FloatToStr(Double(NowUTC + 23/24), TFormatSettings.Invariant)) except end;
    end;
  except end;
  if Watch.ElapsedMilliseconds < 8500 then try
    Attempt := 0;
    if TFile.Exists(Path + '.deprecations') then TryStrToFloat(TFile.ReadAllText(Path + '.deprecations', TEncoding.UTF8), Attempt, TFormatSettings.Invariant);
    if (Attempt = 0) or (NowUTC - Attempt >= 1/24) then begin
      try AtomicWrite(Path + '.deprecations', FloatToStr(Double(NowUTC), TFormatSettings.Invariant)) except end;
      Data := Download(BaseURL + 'deprecations.md'); ApplyDeprecations(ACatalog, Data, NowUTC); Any := True;
      try AtomicWrite(Path + '.deprecations', FloatToStr(Double(NowUTC + 23/24), TFormatSettings.Invariant)) except end;
    end;
  except end;
  if Assigned(AModelListLoader) and (Watch.ElapsedMilliseconds < 10000) then try
    Attempt := 0;
    if TFile.Exists(Path + '.api') then TryStrToFloat(TFile.ReadAllText(Path + '.api', TEncoding.UTF8), Attempt, TFormatSettings.Invariant);
    if (Attempt = 0) or (NowUTC < Attempt) or (NowUTC - Attempt >= 1) then begin
      try AtomicWrite(Path + '.api', FloatToStr(Double(NowUTC), TFormatSettings.Invariant)) except end;
      Data := AModelListLoader(); ApplyModelListJson(ACatalog, Data, NowUTC); Any := True;
    end;
  except end;
  for I := 0 to High(ACatalog.Models) do begin
    if Watch.ElapsedMilliseconds > 8500 then Break;
    if not TRegEx.IsMatch(ACatalog.Models[I].ModelId, '^[a-z0-9.-]+$') then Continue;
    M := ACatalog.Models[I].Metadata;
    if (M.RetrievedAt > 0) and (NowUTC >= M.RetrievedAt) and (NowUTC - M.RetrievedAt < 1) then Continue;
    Attempt := 0;
    try
      if TFile.Exists(Path + '.attempt.' + ACatalog.Models[I].ModelId) then
        TryStrToFloat(TFile.ReadAllText(Path + '.attempt.' + ACatalog.Models[I].ModelId, TEncoding.UTF8), Attempt, TFormatSettings.Invariant);
    except Attempt := 0 end;
    if (Attempt > 0) and (NowUTC >= Attempt) and (NowUTC - Attempt < 1/24) then Continue;
    try AtomicWrite(Path + '.attempt.' + ACatalog.Models[I].ModelId, FloatToStr(Double(NowUTC), TFormatSettings.Invariant)) except end;
    try
      Data := Download(BaseURL + 'models/' + ACatalog.Models[I].ModelId + '.md');
      if ParseModelCard(ACatalog.Models[I].ModelId, Data, M) then begin
        M.RetrievedAt := NowUTC; ACatalog.Models[I].Metadata := M; Any := True;
        try O := ModelPriceCatalogToJson(ACatalog); try AtomicWrite(Path, O.ToJSON) finally O.Free end except end;
      end;
    except end;
  end;
  if Any then try O := ModelPriceCatalogToJson(ACatalog); try AtomicWrite(Path, O.ToJSON) finally O.Free end except end;
end;

end.
