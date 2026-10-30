unit Dashboard.ModelReference;

interface

type
  TModelReference = record
    Name: string;
    InputPerMillion: Double;
    OutputPerMillion: Double;
    Intelligence: Integer; // -1: no comparable AA v5.0 result; never a zero score
  end;

const
  ModelReferenceDate = '30.10.2026';
  ModelReferenceIndex = 'AA v5.0 / max';

function GetModelReferences: TArray<TModelReference>;

implementation

function GetModelReferences: TArray<TModelReference>;
const
  // Verified public reference snapshot; see docs/ModelReference.md for sources.
  // Standard API text prices, short context, no cache/tool/fast-mode surcharges.
  // Scores are exclusively AA Intelligence Index v5.0 at max reasoning effort.
  // Older v4 scores must not be mixed into this comparison.
  Models: array[0..8] of TModelReference = (
    (Name: 'GPT-6 Astra'; InputPerMillion: 10; OutputPerMillion: 50; Intelligence: 57),
    (Name: 'GPT-6.1 Sol'; InputPerMillion: 2; OutputPerMillion: 10; Intelligence: 55),
    (Name: 'GPT-6.1 Terra'; InputPerMillion: 1; OutputPerMillion: 5; Intelligence: 51),
    (Name: 'GPT-6 Luna'; InputPerMillion: 0.1; OutputPerMillion: 0.5; Intelligence: 28),
    (Name: 'GPT-5.6 Sol'; InputPerMillion: 4; OutputPerMillion: 20; Intelligence: -1),
    (Name: 'GPT-5.6 Terra'; InputPerMillion: 2; OutputPerMillion: 12; Intelligence: -1),
    (Name: 'GPT-5.4 mini'; InputPerMillion: 0.75; OutputPerMillion: 4.5; Intelligence: -1),
    (Name: 'GPT-5.3 Codex'; InputPerMillion: 1.75; OutputPerMillion: 14; Intelligence: -1),
    (Name: 'GPT-5.4'; InputPerMillion: 2.5; OutputPerMillion: 15; Intelligence: -1)
  );
var
  I: Integer;
begin
  SetLength(Result, Length(Models));
  for I := 0 to High(Models) do
    Result[I] := Models[I];
end;

end.
