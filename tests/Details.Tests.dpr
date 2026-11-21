program DetailsTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Types, System.JSON,
  Dashboard.DetailLayout in '..\Dashboard.DetailLayout.pas',
  Dashboard.ModelReference in '..\Dashboard.ModelReference.pas',
  Dashboard.Pricing in '..\Dashboard.Pricing.pas',
  Dashboard.Model in '..\Dashboard.Model.pas';

procedure Check(AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure TestRegions;
var R: TRectF; Sections: TDashboardDetailRects; Width: Integer;
begin
  for Width in [480, 1280, 1920] do
  begin
    R := TRectF.Create(37, 29, 37 + Width, 829);
    Sections := DashboardDetailRects(R);
    Check(DashboardDetailAt(R, Sections.Models.CenterPoint) = dkModels, 'Model hit region');
    Check(DashboardDetailAt(R, Sections.Services.CenterPoint) = dkServices, 'Service hit region');
    Check(DashboardDetailAt(R, Sections.Prices.CenterPoint) = dkPrices, 'Price hit region');
    Check(DashboardDetailAt(R, R.TopLeft) = dkNone, 'Header must not open a list');
    Check(DashboardDetailAt(R, TPointF.Create((Sections.Services.Right + Sections.Prices.Left) / 2,
      Sections.Prices.CenterPoint.Y)) = dkNone, 'Gap must not open a list');
  end;
  Check(DashboardDetailAt(TRectF.Empty, TPointF.Zero) = dkNone, 'Empty viewport');
end;

procedure TestPriceTransport;
var A, B: TUsageSnapshot; M: TModelReference;
begin
  A := TUsageSnapshot.Create;
  B := TUsageSnapshot.Create;
  try
    M := Default(TModelReference);
    M.ModelId := 'gpt-7-sol';
    M.Name := 'GPT-7 Sol';
    M.PriceAvailable := True;
    M.InputPerMillion := 2.25;
    M.OutputPerMillion := 11.5;
    M.Intelligence := -1;
    SetLength(A.PriceCatalog.Models, 1);
    A.PriceCatalog.Models[0] := M;
    A.PriceCatalog.UpdatedAt := EncodeDate(2026, 11, 21);
    A.PriceCatalog.StatusText := 'OpenAI Standardpreise';
    B.FromJson(A.ToJson);
    Check(Length(B.PriceCatalog.Models) = 1, 'Future model must be transported');
    Check(B.PriceCatalog.Models[0].ModelId = M.ModelId, 'Model ID roundtrip');
    Check(B.PriceCatalog.Models[0].Intelligence = -1, 'Unknown index is not zero');
    Check(B.PriceCatalog.Models[0].OutputPerMillion = 11.5, 'Price roundtrip');
    B.Assign(A);
    B.PriceCatalog.Models[0].Name := 'Changed';
    Check(A.PriceCatalog.Models[0].Name = 'GPT-7 Sol', 'Snapshot price array must be independent');
    A.PriceCatalog.Models[0].PriceAvailable := False;
    B.FromJson(A.ToJson);
    Check(not B.PriceCatalog.Models[0].PriceAvailable, 'Missing price must remain missing');
    B.FromJson('{}');
    Check(Length(B.PriceCatalog.Models) > 0, 'Old collector fallback');
    Check(B.PriceCatalog.UpdatedAt > 0, 'Fallback must have a real date');
  finally
    A.Free;
    B.Free;
  end;
end;

var Catalog: TModelPriceCatalog;
begin
  try
    TestRegions;
    TestPriceTransport;
    if SameText(ParamStr(1), '--live-prices') then
    begin
      Catalog := GetModelPriceCatalog(True, ParamStr(2));
      Check(Catalog.UpdatedAt >= EncodeDate(2026, 11, 21), 'Live price refresh failed: ' + Catalog.StatusText);
      Check(Length(Catalog.Models) >= 11, 'Live catalog is incomplete');
      Writeln('LIVE_PRICES_OK: ', Length(Catalog.Models));
    end;
    Writeln('DETAILS_TESTS_OK');
  except
    on E: Exception do
    begin
      Writeln('DETAILS_TESTS_FAILED: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
