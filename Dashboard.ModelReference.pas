unit Dashboard.ModelReference;

interface

type
  TModelReference = record
    ModelId: string;
    PriceAvailable: Boolean;
    Name: string;
    InputPerMillion: Double;
    OutputPerMillion: Double;
    Intelligence: Integer; // -1: no comparable AA v5.0.1 result; never a zero score
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
const
  // Verified public reference snapshot; see docs/ModelReference.md for sources.
  // Standard API text prices, short context, no cache/tool/fast-mode surcharges.
  // Scores are exclusively AA Intelligence Index v5.0.1 at max reasoning effort.
  // Older v4 scores must not be mixed into this comparison.
  Models: array[0..10] of TModelReference = (
    (ModelId: 'gpt-6.2-astra'; PriceAvailable: True; Name: 'GPT-6.2 Astra'; InputPerMillion: 8; OutputPerMillion: 40; Intelligence: 62),
    (ModelId: 'gpt-6.2-sol'; PriceAvailable: True; Name: 'GPT-6.2 Sol'; InputPerMillion: 2; OutputPerMillion: 10; Intelligence: 57),
    (ModelId: 'gpt-6-astra'; PriceAvailable: True; Name: 'GPT-6 Astra'; InputPerMillion: 10; OutputPerMillion: 50; Intelligence: 57),
    (ModelId: 'gpt-6.1-sol'; PriceAvailable: True; Name: 'GPT-6.1 Sol'; InputPerMillion: 2; OutputPerMillion: 10; Intelligence: 55),
    (ModelId: 'gpt-6.1-terra'; PriceAvailable: True; Name: 'GPT-6.1 Terra'; InputPerMillion: 1; OutputPerMillion: 5; Intelligence: 51),
    (ModelId: 'gpt-6-luna'; PriceAvailable: True; Name: 'GPT-6 Luna'; InputPerMillion: 0.1; OutputPerMillion: 0.5; Intelligence: 28),
    (ModelId: 'gpt-5.6-sol'; PriceAvailable: True; Name: 'GPT-5.6 Sol'; InputPerMillion: 4; OutputPerMillion: 20; Intelligence: -1),
    (ModelId: 'gpt-5.6-terra'; PriceAvailable: True; Name: 'GPT-5.6 Terra'; InputPerMillion: 2; OutputPerMillion: 12; Intelligence: -1),
    (ModelId: 'gpt-5.4-mini'; PriceAvailable: True; Name: 'GPT-5.4 mini'; InputPerMillion: 0.75; OutputPerMillion: 4.5; Intelligence: -1),
    (ModelId: 'gpt-5.3-codex'; PriceAvailable: True; Name: 'GPT-5.3 Codex'; InputPerMillion: 1.75; OutputPerMillion: 14; Intelligence: -1),
    (ModelId: 'gpt-5.4'; PriceAvailable: True; Name: 'GPT-5.4'; InputPerMillion: 2.5; OutputPerMillion: 15; Intelligence: -1)
  );
var
  I: Integer;
begin
  SetLength(Result, Length(Models));
  for I := 0 to High(Models) do
    Result[I] := Models[I];
end;

function GetBuiltInPriceCatalog: TModelPriceCatalog;
begin
  Result.Models := GetModelReferences;
  Result.UpdatedAt := EncodeDate(2026, 11, 20);
  Result.StatusText := 'Integrierte Referenzpreise (20.11.2026)';
end;

end.
