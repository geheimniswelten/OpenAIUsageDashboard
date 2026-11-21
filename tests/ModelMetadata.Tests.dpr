program ModelMetadataTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.JSON, Dashboard.ModelReference, Dashboard.Pricing, Dashboard.ModelMetadata;
procedure Check(B: Boolean; const S: string); begin if not B then raise Exception.Create(S) end;
var C, D: TModelPriceCatalog; M: TModelMetadata; J: TJSONObject;
begin
  try
    C := GetBuiltInPriceCatalog; EnrichModelCatalog(C, False, nil, 'no-such-cache.json');
    Check(C.Models[0].Metadata.PublishedAt = EncodeDate(2026,11,17), 'seed release');
    M := Default(TModelMetadata);
    Check(not ParseModelCard('gpt-a', 'Model ID: `gpt-ab`', M), 'exact id');
    Check(ParseModelCard('gpt-a', 'Model ID: `gpt-a`'#10'- Input modalities: text, image'#10'- Output modalities: text'#10'- Unsupported modalities: audio, video'#10'- 1,050,000 context window'#10'- 128,000 max output tokens'#10'- Jun 01, 2026 knowledge cutoff'#10'Tools: image_generation', M), 'card');
    Check((M.OutputModalities = [mmText]) and (M.InputModalities = [mmText, mmImage]), 'tool not modality');
    Check((M.ContextTokens = 1050000) and (M.KnowledgeCutoff = EncodeDate(2026,6,1)), 'card values');
    C.Models[0].Metadata := Default(TModelMetadata);
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra","created":1700000000}]}', EncodeDate(2026,11,21));
    Check((C.Models[0].Metadata.PublishedAt = 0) and not C.Models[0].Metadata.ShutdownKnown, 'created and missing');
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra","shutdown_date":null}]}', EncodeDate(2026,11,21));
    Check(C.Models[0].Metadata.ShutdownKnown and (C.Models[0].Metadata.Status = ''), 'null shutdown');
    ApplyDeprecations(C, '| **Dec 11, 2026** | `gpt-6.2-astra` | Deprecated | `gpt-6.2-sol` | Jun 11, 2026 |', EncodeDate(2026,11,21));
    Check(C.Models[0].Metadata.Status = 'deprecated', 'deprecation');
    ApplyDeprecations(C, '| **Dec 11, 2026** | `gpt-6.2-astra` | Deprecated | `gpt-6.2-sol` | Jun 11, 2026 |', EncodeDate(2027,1,1));
    Check(C.Models[0].Metadata.Status = 'shutdown', 'past shutdown');
    J := ModelPriceCatalogToJson(C); try D := ModelPriceCatalogFromJson(J) finally J.Free end;
    Check(D.Models[0].Metadata.Status = 'shutdown', 'metadata roundtrip');
    J := TJSONObject.ParseJSONValue('{"updatedAt":1,"statusText":"old","models":[{"modelId":"gpt-a","name":"A","priceAvailable":true,"inputPerMillion":1,"outputPerMillion":2,"intelligence":-1}]}') as TJSONObject;
    try D := ModelPriceCatalogFromJson(J) finally J.Free end;
    Check((Length(D.Models) = 1) and (D.Models[0].InputPerMillion = 1) and (D.Models[0].Metadata.PublishedAt = 0), 'old catalog compatibility');
    C.Models[0].Metadata := Default(TModelMetadata);
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra-extra","shutdown_date":"2027-04-01"}]}', EncodeDate(2026,11,21));
    Check(not C.Models[0].Metadata.ShutdownKnown, 'exact API id');
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra","shutdown_date":"2027-04-01"}]}', EncodeDate(2026,11,21));
    Check(C.Models[0].Metadata.ShutdownKnown and (C.Models[0].Metadata.ShutdownAt = EncodeDate(2027,4,1)) and (C.Models[0].Metadata.Status = 'deprecated'), 'future ISO shutdown');
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra","shutdown_date":null}]}', EncodeDate(2026,11,21));
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra"}]}', EncodeDate(2026,11,21));
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra","shutdown_date":"2027-02-30"}]}', EncodeDate(2026,11,21));
    Check(C.Models[0].Metadata.ShutdownKnown and (C.Models[0].Metadata.ShutdownAt = EncodeDate(2027,4,1)) and (C.Models[0].Metadata.Status = 'deprecated'), 'null missing invalid preserve');
    ApplyModelListJson(C, '{"data":[{"id":"gpt-6.2-astra","shutdown_date":"2026-04-01"}]}', EncodeDate(2026,11,21));
    Check((C.Models[0].Metadata.ShutdownAt = EncodeDate(2026,4,1)) and (C.Models[0].Metadata.Status = 'shutdown'), 'past ISO shutdown');
    Writeln('Model metadata tests passed');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1) end end;
end.
