unit Dashboard.DetailLayout;

interface

uses System.Types;

type
  TDashboardDetailKind = (dkNone, dkModels, dkServices, dkPrices);
  TDashboardDetailRects = record
    Models, Services, Prices: TRectF;
  end;

function DashboardDetailRects(const AViewport: TRectF): TDashboardDetailRects;
function DashboardDetailAt(const AViewport: TRectF;
  const APoint: TPointF): TDashboardDetailKind;

implementation

uses System.Math;

function DashboardDetailRects(const AViewport: TRectF): TDashboardDetailRects;
var
  Scale, Margin, Gap, ContentTop, ContentBottom, LeftWidth,
    SideLeft, SideWidth, ModelHeight, ServicesWidth: Single;
begin
  Result := Default(TDashboardDetailRects);
  if (AViewport.Width <= 0) or (AViewport.Height <= 0) then
    Exit;
  Scale := EnsureRange(Min(AViewport.Width / 1920, AViewport.Height / 1080), 0.62, 1.35);
  Margin := EnsureRange(AViewport.Width * 0.019, 12.0, 36.0);
  Gap := 12 * Scale;
  ContentTop := AViewport.Top + (15 + 78 + 112) * Scale + 2 * Gap;
  ContentBottom := AViewport.Bottom - Margin - 18 * Scale;
  LeftWidth := (AViewport.Width - 2 * Margin - Gap) * 0.61;
  SideLeft := AViewport.Left + Margin + LeftWidth + Gap;
  SideWidth := AViewport.Width - 2 * Margin - Gap - LeftWidth;
  ModelHeight := (ContentBottom - ContentTop) * 0.36;
  ServicesWidth := (SideWidth - Gap) * 2 / 3;
  Result.Models := TRectF.Create(SideLeft, ContentTop,
    SideLeft + SideWidth, ContentTop + ModelHeight);
  Result.Services := TRectF.Create(SideLeft, ContentTop + ModelHeight + Gap,
    SideLeft + ServicesWidth, ContentBottom);
  Result.Prices := TRectF.Create(SideLeft + ServicesWidth + Gap,
    ContentTop + ModelHeight + Gap, SideLeft + SideWidth, ContentBottom);
end;

function DashboardDetailAt(const AViewport: TRectF;
  const APoint: TPointF): TDashboardDetailKind;
var
  Rects: TDashboardDetailRects;
begin
  Result := dkNone;
  if (AViewport.Width <= 0) or (AViewport.Height <= 0) then
    Exit;
  Rects := DashboardDetailRects(AViewport);
  if Rects.Models.Contains(APoint) then
    Result := dkModels
  else if Rects.Services.Contains(APoint) then
    Result := dkServices
  else if Rects.Prices.Contains(APoint) then
    Result := dkPrices;
end;

end.
