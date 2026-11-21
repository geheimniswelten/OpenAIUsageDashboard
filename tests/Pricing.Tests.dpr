program PricingTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.JSON, System.IOUtils, Dashboard.ModelReference, Dashboard.Pricing;
procedure Check(B: Boolean; const S: string); begin if not B then raise Exception.Create(S) end;
var C, D: TModelPriceCatalog; J: TJSONObject; M: TModelReference; Found: Boolean; P: string;
begin
  try
    C := ParseStandardPricing('### Standard pricing data'#10 +
      '| Model | Short context input | Short context output |'#10 +
      '| --- | --- | --- |'#10 + '| gpt-7.10-astra | $9.00 | $45.00 |'#10 + '| gpt-7.2-astra | $7.00 | $35.00 |'#10 +
      '| gpt-6.2-sol | $2.00 | $10.00 |'#10 +
      '| Model | Input | Output | Cached input |'#10 + '| --- | --- | --- | --- |'#10 +
      '| gpt-5.4-mini | $0.75 | $4.50 | $0.075 |'#10 +
      '### Batch pricing data'#10 + '| gpt-7-astra | $1.00 | $2.00 |');
    Check(C.Models[0].ModelId = 'gpt-7.10-astra', 'new head ordering');
    Check((C.Models[0].Intelligence = -1) and (C.Models[0].InputPerMillion = 9), 'unknown score or tier');
    Found := False;
    for M in C.Models do if M.ModelId = 'gpt-6.2-sol' then begin Found := True; Check(M.Intelligence = 57, 'known score') end;
    Check(Found, 'known model');
    J := ModelPriceCatalogToJson(C); try D := ModelPriceCatalogFromJson(J) finally J.Free end;
    Check((Length(C.Models) = Length(D.Models)) and (Abs(D.UpdatedAt - C.UpdatedAt) < 0.000001), 'json round trip');
    Found := False;
    try ParseStandardPricing('### Standard pricing data'#10'| Model | Input | Output |'#10'| gpt-1 | $1 | $2 |'#10'| gpt-1 | $2 | $3 |') except Found := True end;
    Check(Found, 'duplicate accepted');
    Found := False;
    try ParseStandardPricing('### Batch pricing data'#10'| Model | Input | Output |'#10'| gpt-1 | $1 | $2 |') except Found := True end;
    Check(Found, 'missing standard accepted');
    Found := False;
    try ParseStandardPricing('### Standard pricing data'#10'| Model | Input | Output |'#10'| gpt-1 | $NaN | $2 |') except Found := True end;
    Check(Found, 'invalid price accepted');
    P := TPath.Combine(TPath.GetTempPath, 'pricing-test-' + TGUID.NewGuid.ToString + '.json');
    TFile.WriteAllText(P, '{broken'); try D := GetModelPriceCatalog(False, P); Check(Length(D.Models) = Length(GetModelReferences), 'corrupt cache fallback') finally TFile.Delete(P) end;
    Writeln('Pricing tests passed');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1) end end;
end.
