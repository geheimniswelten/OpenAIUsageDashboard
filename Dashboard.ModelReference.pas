unit Dashboard.ModelReference;

interface

type
  TModelModality = (mmText, mmImage, mmAudio, mmVideo);
  TModelModalities = set of TModelModality;
  TModelMetadata = record
    PublishedAt, ModelUpdatedAt, KnowledgeCutoff: TDateTime;
    ContextTokens, MaxOutputTokens: Int64;
    Status: string;
    ShutdownAt: TDateTime;
    ShutdownKnown: Boolean;
    InputModalities, OutputModalities: TModelModalities;
    ModalitiesKnown: Boolean;
    SourceURL: string;
    RetrievedAt: TDateTime;
  end;
  TModelReference = record
    ModelId: string;
    PriceAvailable: Boolean;
    Name: string;
    InputPerMillion: Double;
    OutputPerMillion: Double;
    Intelligence: Integer; // -1: no comparable AA v5.0.1 result; never a zero score
    Metadata: TModelMetadata;
  end;

  TModelPriceCatalog = record
    Models: TArray<TModelReference>;
    UpdatedAt: TDateTime;
    StatusText: string;
  end;

const
  ModelReferenceDate = '20.11.2026';
  ModelReferenceIndex = 'AA v5.0.1 / max';

function GetModelReferences: TArray<TModelReference>;
function GetBuiltInPriceCatalog: TModelPriceCatalog;

implementation

uses System.SysUtils;

function GetModelReferences: TArray<TModelReference>;
begin
  SetLength(Result, 11);
  Result[0].ModelId := 'gpt-6.2-astra'; Result[0].Name := 'GPT-6.2 Astra'; Result[0].PriceAvailable := True; Result[0].InputPerMillion := 8; Result[0].OutputPerMillion := 40; Result[0].Intelligence := 62;
  Result[1].ModelId := 'gpt-6.2-sol'; Result[1].Name := 'GPT-6.2 Sol'; Result[1].PriceAvailable := True; Result[1].InputPerMillion := 2; Result[1].OutputPerMillion := 10; Result[1].Intelligence := 57;
  Result[2].ModelId := 'gpt-6-astra'; Result[2].Name := 'GPT-6 Astra'; Result[2].PriceAvailable := True; Result[2].InputPerMillion := 10; Result[2].OutputPerMillion := 50; Result[2].Intelligence := 57;
  Result[3].ModelId := 'gpt-6.1-sol'; Result[3].Name := 'GPT-6.1 Sol'; Result[3].PriceAvailable := True; Result[3].InputPerMillion := 2; Result[3].OutputPerMillion := 10; Result[3].Intelligence := 55;
  Result[4].ModelId := 'gpt-6.1-terra'; Result[4].Name := 'GPT-6.1 Terra'; Result[4].PriceAvailable := True; Result[4].InputPerMillion := 1; Result[4].OutputPerMillion := 5; Result[4].Intelligence := 51;
  Result[5].ModelId := 'gpt-6-luna'; Result[5].Name := 'GPT-6 Luna'; Result[5].PriceAvailable := True; Result[5].InputPerMillion := 0.1; Result[5].OutputPerMillion := 0.5; Result[5].Intelligence := 28;
  Result[6].ModelId := 'gpt-5.6-sol'; Result[6].Name := 'GPT-5.6 Sol'; Result[6].PriceAvailable := True; Result[6].InputPerMillion := 4; Result[6].OutputPerMillion := 20; Result[6].Intelligence := -1;
  Result[7].ModelId := 'gpt-5.6-terra'; Result[7].Name := 'GPT-5.6 Terra'; Result[7].PriceAvailable := True; Result[7].InputPerMillion := 2; Result[7].OutputPerMillion := 12; Result[7].Intelligence := -1;
  Result[8].ModelId := 'gpt-5.4-mini'; Result[8].Name := 'GPT-5.4 mini'; Result[8].PriceAvailable := True; Result[8].InputPerMillion := 0.75; Result[8].OutputPerMillion := 4.5; Result[8].Intelligence := -1;
  Result[9].ModelId := 'gpt-5.3-codex'; Result[9].Name := 'GPT-5.3 Codex'; Result[9].PriceAvailable := True; Result[9].InputPerMillion := 1.75; Result[9].OutputPerMillion := 14; Result[9].Intelligence := -1;
  Result[10].ModelId := 'gpt-5.4'; Result[10].Name := 'GPT-5.4'; Result[10].PriceAvailable := True; Result[10].InputPerMillion := 2.5; Result[10].OutputPerMillion := 15; Result[10].Intelligence := -1;
end;

function GetBuiltInPriceCatalog: TModelPriceCatalog;
begin
  Result.Models := GetModelReferences;
  Result.UpdatedAt := EncodeDate(2026, 11, 20);
  Result.StatusText := 'Integrierte Referenzpreise (20.11.2026)';
end;

end.
