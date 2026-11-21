program MetadataTransportTests;
{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.JSON,
  Dashboard.Model, Dashboard.ModelReference, Dashboard.Pricing,
  Dashboard.ModelMetadata, Dashboard.OpenAI;

type
  TModelListFixture = class(TOpenAIUsageClient)
  protected
    function RequestJson(const APath, AQuery: string): string; override;
  end;

function TModelListFixture.RequestJson(const APath, AQuery: string): string;
begin
  if (APath <> '/models') or (AQuery <> '') then
    raise Exception.Create('Unexpected model-list request');
  Result := '{"data":[{"id":"gpt-6.2-sol","shutdown_date":"2027-04-01"}]}';
end;

procedure Check(AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

var
  A, B: TUsageSnapshot;
  Client: TModelListFixture;
  Metadata: TModelMetadata;
begin
  A := TUsageSnapshot.Create;
  B := TUsageSnapshot.Create;
  Client := TModelListFixture.Create('fixture-only', 0, 1);
  try
    try
      EnrichModelCatalog(A.PriceCatalog, False, nil, 'missing-metadata-cache.fixture');
      Metadata := A.PriceCatalog.Models[0].Metadata;
      Check(Metadata.PublishedAt = EncodeDate(2026, 11, 17), 'Verified public release date');
      Check(Metadata.ModelUpdatedAt = 0, 'Update date must remain unknown');
      B.FromJson(A.ToJson);
      Check(B.PriceCatalog.Models[0].Metadata.PublishedAt = Metadata.PublishedAt, 'Release date transport');
      Check(B.PriceCatalog.Models[0].Metadata.ContextTokens = Metadata.ContextTokens, 'Context transport');
      Check(B.PriceCatalog.Models[0].Metadata.InputModalities = [mmText, mmImage], 'Input modality transport');
      Check(B.PriceCatalog.Models[0].Metadata.OutputModalities = [mmText], 'Output modality transport');
      ApplyModelListJson(A.PriceCatalog, Client.ReadModelListJson, EncodeDate(2026, 11, 21));
      B.FromJson(A.ToJson);
      Check(B.PriceCatalog.Models[1].Metadata.ShutdownAt = EncodeDate(2027, 4, 1), 'ISO shutdown transported');
      Check(B.PriceCatalog.Models[1].Metadata.Status = 'deprecated', 'Shutdown status transport');
      B.FromJson('{}');
      Check(Length(B.PriceCatalog.Models) > 0, 'Legacy snapshot compatibility');
      Writeln('METADATA_TRANSPORT_OK');
    except
      on E: Exception do begin Writeln('METADATA_TRANSPORT_FAILED: ', E.Message); ExitCode := 1 end;
    end;
  finally
    Client.Free;
    B.Free;
    A.Free;
  end;
end.
