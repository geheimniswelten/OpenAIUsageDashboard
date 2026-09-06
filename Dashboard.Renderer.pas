unit Dashboard.Renderer;

interface

uses
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Graphics,
  Dashboard.Model;

type
  TDashboardRenderer = class
  private
    FSnapshot: TUsageSnapshot;
    FScale: Single;
    procedure SetFont(const ACanvas: TCanvas; const ASize: Single;
      const ABold: Boolean = False);
    procedure Text(const ACanvas: TCanvas; const ARect: TRectF;
      const AText: string; const ASize: Single; const AColor: TAlphaColor;
      const ABold: Boolean = False; const AAlign: TTextAlign = TTextAlign.Leading;
      const AVertical: TTextAlign = TTextAlign.Center);
    procedure Box(const ACanvas: TCanvas; const ARect: TRectF;
      const AFill, AStroke: TAlphaColor; const ARadius: Single = 14);
    procedure DrawHeader(const ACanvas: TCanvas; const ARect: TRectF);
    procedure DrawKpi(const ACanvas: TCanvas; const ARect: TRectF;
      const ACaption, AValue, ADetail: string; const AAccent: Boolean = False);
    procedure DrawChart(const ACanvas: TCanvas; const ARect: TRectF);
    procedure DrawModels(const ACanvas: TCanvas; const ARect: TRectF);
    procedure DrawServices(const ACanvas: TCanvas; const ARect: TRectF);
    procedure DrawLimits(const ACanvas: TCanvas; const ARect: TRectF);
    procedure DrawCodex(const ACanvas: TCanvas; const ARect: TRectF);
  public
    constructor Create(const ASnapshot: TUsageSnapshot);
    function SettingsHitRect(const ARect: TRectF): TRectF;
    procedure Render(const ACanvas: TCanvas; const ARect: TRectF);
    procedure RenderCompanion(const ACanvas: TCanvas; const ARect: TRectF;
      const ARevealed: Boolean; const ASecondsRemaining: Integer);
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  System.Generics.Collections;

const
  CBackground = TAlphaColor($FF06140F);
  CPanel = TAlphaColor($FF0B2018);
  CPanelAlt = TAlphaColor($FF0D261D);
  CBorder = TAlphaColor($FF214D3B);
  CText = TAlphaColor($FFF4FFF9);
  CMuted = TAlphaColor($FF83CDB1);
  CFaint = TAlphaColor($FF477C69);
  CGreen = TAlphaColor($FF70EDAF);
  CLime = TAlphaColor($FFB1F56B);
  CBluePanel = TAlphaColor($FF0A2330);
  CBlueBorder = TAlphaColor($FF245C76);
  CBlue = TAlphaColor($FF67C9F4);
  CWarning = TAlphaColor($FFFFD166);
  CWeekend = TAlphaColor($FF10251D);
  CForecast = TAlphaColor($FF17342A);

function Clamp(const V, AMin, AMax: Single): Single;
begin
  Result := Max(AMin, Min(AMax, V));
end;

function RectInset(const R: TRectF; const X, Y: Single): TRectF;
begin
  Result := TRectF.Create(R.Left + X, R.Top + Y, R.Right - X, R.Bottom - Y);
end;

function GermanFormatSettings: TFormatSettings;
begin
  Result := TFormatSettings.Create;
  Result.DecimalSeparator := ',';
  Result.ThousandSeparator := '.';
end;

function FormatMoney(const V: Double; const Currency: string): string;
begin
  if SameText(Currency, 'EUR') then
    Result := FormatFloat('#,##0.00', V, GermanFormatSettings) + ' €'
  else
    Result := FormatFloat('#,##0.00', V, GermanFormatSettings) + ' $';
end;

function CompactNumber(const V: Int64): string;
begin
  if Abs(V) >= 1000000000 then
    Result := FormatFloat('0.0', V / 1000000000, GermanFormatSettings) + ' Mrd.'
  else if Abs(V) >= 1000000 then
    Result := FormatFloat('0.0', V / 1000000, GermanFormatSettings) + ' Mio.'
  else if Abs(V) >= 1000 then
    Result := FormatFloat('0.0', V / 1000, GermanFormatSettings) + ' Tsd.'
  else
    Result := FormatFloat('0', V, GermanFormatSettings);
end;

function CompactValue(const V: Double; const UnitText: string): string;
begin
  if SameText(UnitText, 'B') then
  begin
    if V >= 1024 * 1024 * 1024 then
      Result := FormatFloat('0.0', V / (1024 * 1024 * 1024),
        GermanFormatSettings) + ' GiB'
    else if V >= 1024 * 1024 then
      Result := FormatFloat('0.0', V / (1024 * 1024),
        GermanFormatSettings) + ' MiB'
    else if V >= 1024 then
      Result := FormatFloat('0.0', V / 1024, GermanFormatSettings) + ' KiB'
    else
      Result := FormatFloat('0', V, GermanFormatSettings) + ' B';
  end
  else
  begin
    Result := CompactNumber(Trunc(V));
    if UnitText <> '' then
      Result := Result + ' ' + UnitText;
  end;
end;

function LimitColor(const Used: Double): TAlphaColor;
begin
  if Used >= 90 then
    Result := TAlphaColor($FFFF7B72)
  else if Used >= 75 then
    Result := CWarning
  else
    Result := CGreen;
end;

{ TDashboardRenderer }

constructor TDashboardRenderer.Create(const ASnapshot: TUsageSnapshot);
begin
  inherited Create;
  FSnapshot := ASnapshot;
  FScale := 1;
end;

function TDashboardRenderer.SettingsHitRect(const ARect: TRectF): TRectF;
var
  Scale, Margin: Single;
begin
  Scale := Clamp(Min(ARect.Width / 1920, ARect.Height / 1080), 0.62, 1.35);
  Margin := Clamp(ARect.Width * 0.019, 12, 36);
  Result := TRectF.Create(ARect.Right - Margin - 440 * Scale,
    ARect.Top + 7 * Scale, ARect.Right - Margin,
    ARect.Top + 83 * Scale);
end;

procedure TDashboardRenderer.SetFont(const ACanvas: TCanvas; const ASize: Single;
  const ABold: Boolean);
var
  ReadableSize: Single;
begin
  ReadableSize := ASize;
  if ASize <= 8 then
    ReadableSize := ASize + 3
  else if ASize <= 10 then
    ReadableSize := ASize + 2.5
  else if ASize <= 12 then
    ReadableSize := ASize + 2
  else if ASize <= 15 then
    ReadableSize := ASize + 1;
  ACanvas.Font.Family := 'Segoe UI';
  ACanvas.Font.Size := Max(9, ReadableSize * FScale);
  if ABold then
    ACanvas.Font.Style := [TFontStyle.fsBold]
  else
    ACanvas.Font.Style := [];
end;

procedure TDashboardRenderer.Text(const ACanvas: TCanvas; const ARect: TRectF;
  const AText: string; const ASize: Single; const AColor: TAlphaColor;
  const ABold: Boolean; const AAlign, AVertical: TTextAlign);
begin
  SetFont(ACanvas, ASize, ABold);
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AColor;
  ACanvas.FillText(ARect, AText, False, 1, [], AAlign, AVertical);
end;

procedure TDashboardRenderer.Box(const ACanvas: TCanvas; const ARect: TRectF;
  const AFill, AStroke: TAlphaColor; const ARadius: Single);
begin
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AFill;
  ACanvas.FillRect(ARect, ARadius * FScale, ARadius * FScale, AllCorners, 1);
  if AStroke <> 0 then
  begin
    ACanvas.Stroke.Kind := TBrushKind.Solid;
    ACanvas.Stroke.Color := AStroke;
    ACanvas.Stroke.Thickness := Max(1, FScale);
    ACanvas.Stroke.Dash := TStrokeDash.Solid;
    ACanvas.DrawRect(ARect, ARadius * FScale, ARadius * FScale, AllCorners, 1);
  end;
end;

procedure TDashboardRenderer.DrawHeader(const ACanvas: TCanvas;
  const ARect: TRectF);
var
  Status, Stamp: string;
  Dot, StatusPanel: TRectF;
begin
  StatusPanel := TRectF.Create(ARect.Right - 440 * FScale,
    ARect.Top - 5 * FScale, ARect.Right, ARect.Top + 68 * FScale);
  Box(ACanvas, StatusPanel, CPanel, CBorder, 10);
  Text(ACanvas, TRectF.Create(ARect.Left, ARect.Top, ARect.Right,
    ARect.Top + 22 * FScale), 'LIVE · API PLATFORM', 12, CGreen, True);
  Text(ACanvas, TRectF.Create(ARect.Left, ARect.Top + 18 * FScale,
    ARect.Right, ARect.Bottom), 'OpenAI Nutzung', 38, CText, True,
    TTextAlign.Leading, TTextAlign.Leading);
  Status := FSnapshot.StatusText;
  if Status = '' then
    Status := 'Warte auf Daten';
  Dot := TRectF.Create(ARect.Right - 420 * FScale, ARect.Top + 5 * FScale,
    ARect.Right - 410 * FScale, ARect.Top + 15 * FScale);
  ACanvas.Fill.Color := LimitColor(IfThen(SameText(Status, 'Aktuell'), 0, 80));
  ACanvas.FillEllipse(Dot, 1);
  Text(ACanvas, TRectF.Create(Dot.Right + 5 * FScale, ARect.Top,
    ARect.Right, ARect.Top + 22 * FScale), Status, 12, CText, True,
    TTextAlign.Leading);
  if FSnapshot.LastUpdated > 0 then
    Stamp := 'Stand ' + FormatDateTime('dd.mm.yyyy, hh:nn:ss', FSnapshot.LastUpdated)
  else
    Stamp := 'Noch nicht aktualisiert';
  Text(ACanvas, TRectF.Create(ARect.Right - 360 * FScale,
    ARect.Top + 22 * FScale, ARect.Right, ARect.Top + 44 * FScale),
    Stamp, 10, CMuted, False, TTextAlign.Trailing);
  Text(ACanvas, TRectF.Create(ARect.Right - 420 * FScale,
    ARect.Top + 43 * FScale, ARect.Right, ARect.Top + 64 * FScale),
    FSnapshot.OrganizationId, 10, CMuted, False, TTextAlign.Trailing);
end;

procedure TDashboardRenderer.DrawKpi(const ACanvas: TCanvas; const ARect: TRectF;
  const ACaption, AValue, ADetail: string; const AAccent: Boolean);
var
  FillColor, BorderColor: TAlphaColor;
begin
  if AAccent then
  begin
    FillColor := TAlphaColor($FF0C2A20);
    BorderColor := TAlphaColor($FF2A7E5A);
  end
  else
  begin
    FillColor := CPanel;
    BorderColor := CBorder;
  end;
  Box(ACanvas, ARect, FillColor, BorderColor);
  Text(ACanvas, TRectF.Create(ARect.Left + 18 * FScale, ARect.Top + 10 * FScale,
    ARect.Right - 12 * FScale, ARect.Top + 36 * FScale), ACaption, 12, CMuted);
  Text(ACanvas, TRectF.Create(ARect.Left + 18 * FScale, ARect.Top + 35 * FScale,
    ARect.Right - 12 * FScale, ARect.Bottom - 23 * FScale), AValue, 31, CText, True,
    TTextAlign.Leading, TTextAlign.Center);
  Text(ACanvas, TRectF.Create(ARect.Left + 18 * FScale, ARect.Bottom - 27 * FScale,
    ARect.Right - 12 * FScale, ARect.Bottom - 7 * FScale), ADetail, 9, CMuted);
end;

procedure TDashboardRenderer.DrawChart(const ACanvas: TCanvas; const ARect: TRectF);
var
  Plot, HeaderRect, Cell, BarRect, LabelRect: TRectF;
  Actual: TList<TDailyCost>;
  ActualStart, I, J, N, TrendIndex: Integer;
  ActualWidth, ForecastWidth, CellWidth, X, Y, BarMax, LineMax, Running,
    LimitY, UsedPct, TrendStart, TrendEnd: Double;
  DayValue, PointPeriodStart, PreviousPeriodStart: TDateTime;
  PreviousPoint, Point: TPointF;
  HasPrevious, FirstForecast, NewPeriodSeen: Boolean;
  LimitText: string;
begin
  Box(ACanvas, ARect, CPanel, CBorder);
  HeaderRect := TRectF.Create(ARect.Left + 16 * FScale, ARect.Top + 8 * FScale,
    ARect.Right - 16 * FScale, ARect.Top + 43 * FScale);
  Text(ACanvas, HeaderRect, 'Tägliche Kosten · 14 Tage + 4-Wochen-Prognose',
    15, CText, True);
  Plot := TRectF.Create(ARect.Left + 18 * FScale, ARect.Top + 52 * FScale,
    ARect.Right - 18 * FScale, ARect.Bottom - 22 * FScale);
  if (Plot.Width < 100) or (Plot.Height < 80) then
    Exit;

  Actual := TList<TDailyCost>.Create;
  try
    ActualStart := Max(0, Length(FSnapshot.DailyCosts) - 14);
    for I := ActualStart to High(FSnapshot.DailyCosts) do
      Actual.Add(FSnapshot.DailyCosts[I]);
    N := Actual.Count;
    if N = 0 then
    begin
      Text(ACanvas, Plot, 'Noch keine Kostendaten', 13, CMuted, False,
        TTextAlign.Center);
      Exit;
    end;
    ActualWidth := Plot.Width * 0.81;
    ForecastWidth := Plot.Width - ActualWidth;
    CellWidth := ActualWidth / N;
    BarMax := 0.01;
    for I := 0 to N - 1 do
      BarMax := Max(BarMax, Actual[I].Amount);
    LineMax := Max(FSnapshot.SpendingLimit, FSnapshot.PeriodCost);
    for I := 0 to High(FSnapshot.Forecast) do
      LineMax := Max(LineMax, FSnapshot.Forecast[I].Cumulative);
    { Include the preceding billing period when it is still visible. }
    Running := 0;
    PreviousPeriodStart := 0;
    for I := 0 to High(FSnapshot.DailyCosts) do
    begin
      PointPeriodStart := FSnapshot.PeriodStart;
      while FSnapshot.DailyCosts[I].Day < PointPeriodStart do
        PointPeriodStart := IncMonth(PointPeriodStart, -1);
      while FSnapshot.DailyCosts[I].Day >= IncMonth(PointPeriodStart, 1) do
        PointPeriodStart := IncMonth(PointPeriodStart, 1);
      if (PreviousPeriodStart = 0) or
         not SameDate(PointPeriodStart, PreviousPeriodStart) then
        Running := 0;
      Running := Running + FSnapshot.DailyCosts[I].Amount;
      LineMax := Max(LineMax, Running);
      PreviousPeriodStart := PointPeriodStart;
    end;
    LineMax := Max(1, LineMax * 1.12);

    { Background bands: weekends only, as requested. }
    for I := 0 to N - 1 do
    begin
      Cell := TRectF.Create(Plot.Left + I * CellWidth, Plot.Top,
        Plot.Left + (I + 1) * CellWidth - 2 * FScale, Plot.Bottom);
      if DayOfTheWeek(Actual[I].Day) >= 6 then
      begin
        ACanvas.Fill.Color := CWeekend;
        ACanvas.FillRect(Cell, 1);
      end;
    end;
    ACanvas.Fill.Color := CForecast;
    ACanvas.FillRect(TRectF.Create(Plot.Left + ActualWidth, Plot.Top,
      Plot.Right, Plot.Bottom), 0.55);
    ACanvas.Stroke.Color := CBorder;
    ACanvas.Stroke.Thickness := Max(1, FScale);
    ACanvas.Stroke.Dash := TStrokeDash.Dot;
    ACanvas.DrawLine(TPointF.Create(Plot.Left + ActualWidth, Plot.Top),
      TPointF.Create(Plot.Left + ActualWidth, Plot.Bottom), 1);

    { Daily bars. }
    for I := 0 to N - 1 do
    begin
      X := Plot.Left + I * CellWidth;
      Y := Plot.Bottom - 25 * FScale -
        (Plot.Height - 48 * FScale) * (Actual[I].Amount / BarMax);
      BarRect := TRectF.Create(X + CellWidth * 0.24, Y,
        X + CellWidth * 0.76, Plot.Bottom - 25 * FScale);
      ACanvas.Fill.Color := IfThen(SameDate(Actual[I].Day,
        DateOf(TTimeZone.Local.ToUniversalTime(FSnapshot.LastUpdated))), CLime, CGreen);
      ACanvas.FillRect(BarRect, 5 * FScale, 5 * FScale, [TCorner.TopLeft,
        TCorner.TopRight], 0.88);
      if Actual[I].HasCostData or (Actual[I].Amount <> 0) then
        Text(ACanvas, TRectF.Create(X, Plot.Top, X + CellWidth, Plot.Top + 20 * FScale),
          FormatFloat('0.00', Actual[I].Amount, GermanFormatSettings), 8,
          CMuted, False, TTextAlign.Center)
      else
        Text(ACanvas, TRectF.Create(X, Plot.Top, X + CellWidth, Plot.Top + 20 * FScale),
          '–', 8, CMuted, False, TTextAlign.Center);
      LabelRect := TRectF.Create(X, Plot.Bottom - 22 * FScale,
        X + CellWidth, Plot.Bottom);
      Text(ACanvas, LabelRect, FormatDateTime('dd.mm.', Actual[I].Day),
        8, CMuted, False, TTextAlign.Center);
    end;

    { Spending limit. }
    if FSnapshot.SpendingLimit > 0 then
    begin
      LimitY := Plot.Bottom - 27 * FScale -
        (Plot.Height - 52 * FScale) * (FSnapshot.SpendingLimit / LineMax);
      ACanvas.Stroke.Color := CWarning;
      ACanvas.Stroke.Thickness := Max(1, 1.4 * FScale);
      ACanvas.Stroke.Dash := TStrokeDash.Dash;
      ACanvas.DrawLine(TPointF.Create(Plot.Left, LimitY),
        TPointF.Create(Plot.Right, LimitY), 0.82);
      UsedPct := 100 * FSnapshot.PeriodCost / FSnapshot.SpendingLimit;
      LimitText := Format('Limit %s · %.0f%%',
        [FormatMoney(FSnapshot.SpendingLimit, FSnapshot.Currency), UsedPct]);
      Text(ACanvas, TRectF.Create(Plot.Right - 250 * FScale,
        LimitY - 21 * FScale, Plot.Right, LimitY - 2 * FScale), LimitText,
        9, CWarning, True, TTextAlign.Trailing);
    end;

    { Cumulative actual line, resetting at the configured billing boundary. }
    TrendIndex := -1;
    PreviousPeriodStart := 0;
    HasPrevious := False;
    ACanvas.Stroke.Color := CText;
    ACanvas.Stroke.Thickness := Max(1.5, 2.2 * FScale);
    ACanvas.Stroke.Dash := TStrokeDash.Solid;
    for I := 0 to N - 1 do
    begin
      DayValue := Actual[I].Day;
      PointPeriodStart := FSnapshot.PeriodStart;
      while DayValue < PointPeriodStart do
        PointPeriodStart := IncMonth(PointPeriodStart, -1);
      while DayValue >= IncMonth(PointPeriodStart, 1) do
        PointPeriodStart := IncMonth(PointPeriodStart, 1);
      Running := 0;
      for J := 0 to High(FSnapshot.DailyCosts) do
        if (FSnapshot.DailyCosts[J].Day >= PointPeriodStart) and
           (FSnapshot.DailyCosts[J].Day <= DayValue) and
           (FSnapshot.DailyCosts[J].Day < IncMonth(PointPeriodStart, 1)) then
          Running := Running + FSnapshot.DailyCosts[J].Amount;
      if (PreviousPeriodStart <> 0) and
         not SameDate(PointPeriodStart, PreviousPeriodStart) then
        HasPrevious := False;
      Point.X := Plot.Left + (I + 0.5) * CellWidth;
      Point.Y := Plot.Bottom - 27 * FScale -
        (Plot.Height - 52 * FScale) * (Running / LineMax);
      if HasPrevious then
        ACanvas.DrawLine(PreviousPoint, Point, 1);
      ACanvas.Fill.Color := CText;
      ACanvas.FillEllipse(TRectF.Create(Point.X - 2.5 * FScale,
        Point.Y - 2.5 * FScale, Point.X + 2.5 * FScale,
        Point.Y + 2.5 * FScale), 1);
      PreviousPoint := Point;
      HasPrevious := True;
      PreviousPeriodStart := PointPeriodStart;
      if (TrendIndex < 0) and (DayValue >= FSnapshot.PeriodStart) then
        TrendIndex := I;
    end;

    { Least-squares trend in the background. }
    if TrendIndex >= 0 then
    begin
      TrendStart := FSnapshot.ForecastDailyRate * Max(0,
        DaysBetween(Actual[TrendIndex].Day, FSnapshot.PeriodStart));
      TrendEnd := FSnapshot.ForecastDailyRate * Max(0,
        DaysBetween(Actual[N - 1].Day, FSnapshot.PeriodStart));
      ACanvas.Stroke.Color := CGreen;
      ACanvas.Stroke.Thickness := Max(1, 1.3 * FScale);
      ACanvas.Stroke.Dash := TStrokeDash.Dash;
      ACanvas.DrawLine(TPointF.Create(Plot.Left + (TrendIndex + 0.5) * CellWidth,
        Plot.Bottom - 27 * FScale - (Plot.Height - 52 * FScale) * TrendStart / LineMax),
        TPointF.Create(Plot.Left + ActualWidth - CellWidth * 0.5,
        Plot.Bottom - 27 * FScale - (Plot.Height - 52 * FScale) * TrendEnd / LineMax),
        0.48);
    end;

    { Four compact future slots, each representing one week. }
    FirstForecast := True;
    NewPeriodSeen := False;
    ACanvas.Stroke.Color := CLime;
    ACanvas.Stroke.Thickness := Max(1.5, 2 * FScale);
    ACanvas.Stroke.Dash := TStrokeDash.Dot;
    for I := 0 to High(FSnapshot.Forecast) do
    begin
      X := Plot.Left + ActualWidth + ForecastWidth * (I + 0.5) /
        Max(1, Length(FSnapshot.Forecast));
      Y := Plot.Bottom - 27 * FScale - (Plot.Height - 52 * FScale) *
        (FSnapshot.Forecast[I].Cumulative / LineMax);
      Point := TPointF.Create(X, Y);
      if FSnapshot.Forecast[I].StartsNewPeriod and not NewPeriodSeen then
      begin
        NewPeriodSeen := True;
        ACanvas.Stroke.Color := CFaint;
        ACanvas.DrawLine(TPointF.Create(X - ForecastWidth * 0.08, Plot.Top),
          TPointF.Create(X - ForecastWidth * 0.08, Plot.Bottom - 25 * FScale), 0.8);
        Text(ACanvas, TRectF.Create(X - 80 * FScale, Plot.Top + 22 * FScale,
          X + 80 * FScale, Plot.Top + 42 * FScale), 'Abrechnung → 0', 8,
          CMuted, False, TTextAlign.Center);
        ACanvas.Stroke.Color := CLime;
        FirstForecast := True;
      end;
      if FirstForecast then
      begin
        if not FSnapshot.Forecast[I].StartsNewPeriod and HasPrevious then
          ACanvas.DrawLine(PreviousPoint, Point, 1);
        FirstForecast := False;
      end
      else
        ACanvas.DrawLine(PreviousPoint, Point, 1);
      ACanvas.Fill.Color := CLime;
      ACanvas.FillEllipse(TRectF.Create(X - 4 * FScale, Y - 4 * FScale,
        X + 4 * FScale, Y + 4 * FScale), 1);
      Text(ACanvas, TRectF.Create(X - ForecastWidth * 0.12,
        Plot.Top + 3 * FScale, X + ForecastWidth * 0.12,
        Plot.Top + 21 * FScale), FormatMoney(FSnapshot.Forecast[I].Cumulative,
        FSnapshot.Currency), 8, CLime, True, TTextAlign.Center);
      Text(ACanvas, TRectF.Create(X - ForecastWidth * 0.12,
        Plot.Bottom - 22 * FScale, X + ForecastWidth * 0.12, Plot.Bottom),
        '+' + IntToStr((I + 1) * 7) + ' T', 8, CMuted, False,
        TTextAlign.Center);
      PreviousPoint := Point;
    end;
  finally
    Actual.Free;
  end;
end;

procedure TDashboardRenderer.DrawModels(const ACanvas: TCanvas;
  const ARect: TRectF);
var
  I, ModelIndex, Count, Col, RowIndex: Integer;
  Gap, CellW, CellH, X, Y, ModelFontSize: Single;
  Card, NameRect, RequestRect, TokenRect: TRectF;

  function FitModelName(const AValue: string; const AWidth,
    AFontSize: Single): string;
  var
    LeftCount, RightCount: Integer;
  begin
    Result := AValue;
    SetFont(ACanvas, AFontSize, True);
    if ACanvas.TextWidth(Result) <= AWidth then
      Exit;
    LeftCount := (Length(AValue) + 1) div 2;
    RightCount := Length(AValue) - LeftCount;
    while LeftCount + RightCount > 5 do
    begin
      Result := Copy(AValue, 1, LeftCount) + '…' +
        Copy(AValue, Length(AValue) - RightCount + 1, RightCount);
      if ACanvas.TextWidth(Result) <= AWidth then
        Exit;
      if LeftCount > RightCount then
        Dec(LeftCount)
      else
        Dec(RightCount);
    end;
    Result := Copy(AValue, 1, LeftCount) + '…' +
      Copy(AValue, Length(AValue) - RightCount + 1, RightCount);
  end;

begin
  Box(ACanvas, ARect, CPanel, CBorder);
  Text(ACanvas, TRectF.Create(ARect.Left + 15 * FScale, ARect.Top + 7 * FScale,
    ARect.Right - 12 * FScale, ARect.Top + 36 * FScale),
    'Top API-Modelle · letzte 7 Tage', 15, CText, True);
  Count := Min(5, Length(FSnapshot.Models));
  Gap := 7 * FScale;
  CellW := (ARect.Width - 30 * FScale - 2 * Gap) / 3;
  CellH := (ARect.Height - 51 * FScale - Gap) / 2;
  if (CellW <= 20) or (CellH <= 20) then
    Exit;

  { Stable 2x3 grid: one legend card followed by up to five model cards. }
  for I := 0 to 5 do
  begin
    Col := I mod 3;
    RowIndex := I div 3;
    X := ARect.Left + 15 * FScale + Col * (CellW + Gap);
    Y := ARect.Top + 41 * FScale + RowIndex * (CellH + Gap);
    Card := TRectF.Create(X, Y, X + CellW, Y + CellH);
    if I = 0 then
      Box(ACanvas, Card, CBluePanel, CBlueBorder, 9)
    else
      Box(ACanvas, Card, TAlphaColor($FF081B14), CBorder, 9);

    NameRect := TRectF.Create(Card.Left + 8 * FScale,
      Card.Top + 4 * FScale, Card.Right - 8 * FScale,
      Card.Top + CellH * 0.36);
    RequestRect := TRectF.Create(Card.Left + 8 * FScale,
      Card.Top + CellH * 0.36, Card.Right - 8 * FScale,
      Card.Top + CellH * 0.68);
    TokenRect := TRectF.Create(Card.Left + 8 * FScale,
      Card.Top + CellH * 0.68, Card.Right - 8 * FScale,
      Card.Bottom - 3 * FScale);

    if I = 0 then
    begin
      Text(ACanvas, NameRect, 'Modell', 9, CMuted, True,
        TTextAlign.Center);
      Text(ACanvas, RequestRect, 'Anfragen', 9, CMuted, False,
        TTextAlign.Center);
      Text(ACanvas, TokenRect, 'Tokens', 9, CMuted, False,
        TTextAlign.Center);
      Continue;
    end;

    ModelIndex := I - 1;
    if ModelIndex < Count then
    begin
      if Length(FSnapshot.Models[ModelIndex].Model) > 24 then
        ModelFontSize := 12
      else
        ModelFontSize := 13.5;
      Text(ACanvas, NameRect, FitModelName(FSnapshot.Models[ModelIndex].Model,
        NameRect.Width, ModelFontSize), ModelFontSize, CText, True,
        TTextAlign.Center);
      Text(ACanvas, RequestRect,
        CompactNumber(FSnapshot.Models[ModelIndex].Requests), 25.2, CBlue,
        True, TTextAlign.Center);
      Text(ACanvas, TokenRect,
        CompactNumber(FSnapshot.Models[ModelIndex].Tokens), 21, CLime,
        True, TTextAlign.Center);
    end
    else
      Text(ACanvas, Card, '–', 13, CFaint, False, TTextAlign.Center);
  end;
end;

procedure TDashboardRenderer.DrawServices(const ACanvas: TCanvas;
  const ARect: TRectF);
var
  I, Count, Col, RowIndex, Cols, Rows: Integer;
  Gap, CellW, CellH, X, Y, ValueFontSize, MeasuredWidth: Single;
  R, NameRect, ValueRect, DetailRect: TRectF;
  ValueText, Detail: string;
begin
  Box(ACanvas, ARect, CPanel, CBorder);
  Text(ACanvas, TRectF.Create(ARect.Left + 15 * FScale, ARect.Top + 7 * FScale,
    ARect.Right - 12 * FScale, ARect.Top + 38 * FScale),
    'Weitere API-Dienste', 15, CText, True);
  Count := Length(FSnapshot.Services);
  if Count = 0 then
  begin
    Text(ACanvas, RectInset(ARect, 15 * FScale, 45 * FScale),
      'Noch keine Zusatzdaten', 11, CMuted, False, TTextAlign.Center);
    Exit;
  end;
  Cols := 3;
  Rows := Ceil(Count / Cols);
  Gap := 7 * FScale;
  CellW := (ARect.Width - 30 * FScale - Gap * (Cols - 1)) / Cols;
  CellH := (ARect.Height - 49 * FScale - Gap * (Rows - 1)) / Rows;
  for I := 0 to Count - 1 do
  begin
    Col := I mod Cols;
    RowIndex := I div Cols;
    X := ARect.Left + 15 * FScale + Col * (CellW + Gap);
    Y := ARect.Top + 41 * FScale + RowIndex * (CellH + Gap);
    R := TRectF.Create(X, Y, X + CellW, Y + CellH);
    Box(ACanvas, R, TAlphaColor($FF081B14), CBorder, 9);
    NameRect := TRectF.Create(R.Left + 10 * FScale, R.Top + 8 * FScale,
      R.Right - 10 * FScale, R.Top + 36 * FScale);
    ValueRect := TRectF.Create(R.Left + 10 * FScale, R.Top + 34 * FScale,
      R.Right - 10 * FScale, R.Bottom - 28 * FScale);
    DetailRect := TRectF.Create(R.Left + 10 * FScale, R.Bottom - 28 * FScale,
      R.Right - 10 * FScale, R.Bottom - 6 * FScale);
    Text(ACanvas, NameRect, FSnapshot.Services[I].Name, 12, CMuted);
    if FSnapshot.Services[I].Available then
      ValueText := CompactValue(FSnapshot.Services[I].Value,
        FSnapshot.Services[I].UnitText)
    else
      ValueText := '–';
    ValueFontSize := 31;
    SetFont(ACanvas, ValueFontSize, True);
    MeasuredWidth := ACanvas.TextWidth(ValueText);
    if (MeasuredWidth > 0) and (MeasuredWidth > ValueRect.Width) then
      ValueFontSize := Max(20, ValueFontSize * ValueRect.Width / MeasuredWidth);
    Text(ACanvas, ValueRect, ValueText, ValueFontSize, CText, True);
    if FSnapshot.Services[I].Available then
      Detail := CompactNumber(FSnapshot.Services[I].Requests) + ' Anfragen'
    else
      Detail := 'nicht verfügbar';
    Text(ACanvas, DetailRect, Detail, 9, CMuted);
  end;
end;

procedure TDashboardRenderer.DrawLimits(const ACanvas: TCanvas;
  const ARect: TRectF);
var
  Count, I, Cards: Integer;
  Gap, CardW, X, Pct: Single;
  R, Track, Fill: TRectF;
  ResetText, NameText: string;
begin
  Box(ACanvas, ARect, CBluePanel, CBlueBorder);
  Text(ACanvas, TRectF.Create(ARect.Left + 15 * FScale, ARect.Top + 5 * FScale,
    ARect.Right - 12 * FScale, ARect.Top + 34 * FScale),
    'Limits · Prozentverbrauch', 15, CText, True);
  Count := Min(4, Length(FSnapshot.RateLimits));
  Cards := Max(1, Count + Ord(FSnapshot.SpendingLimit > 0));
  Cards := Min(4, Cards);
  Gap := 8 * FScale;
  CardW := (ARect.Width - 30 * FScale - Gap * (Cards - 1)) / Cards;
  I := 0;
  if (FSnapshot.SpendingLimit > 0) and (I < Cards) then
  begin
    X := ARect.Left + 15 * FScale;
    R := TRectF.Create(X, ARect.Top + 38 * FScale, X + CardW,
      ARect.Bottom - 10 * FScale);
    Box(ACanvas, R, TAlphaColor($FF091D25), CBlueBorder, 10);
    Pct := Clamp(100 * FSnapshot.PeriodCost / FSnapshot.SpendingLimit, 0, 100);
    Text(ACanvas, TRectF.Create(R.Left + 10 * FScale, R.Top + 5 * FScale,
      R.Right - 55 * FScale, R.Top + 27 * FScale), 'API-Ausgaben', 9, CText, True);
    Text(ACanvas, TRectF.Create(R.Right - 55 * FScale, R.Top + 5 * FScale,
      R.Right - 9 * FScale, R.Top + 27 * FScale), FormatFloat('0', Pct) + '%',
      15, LimitColor(Pct), True, TTextAlign.Trailing);
    Track := TRectF.Create(R.Left + 10 * FScale, R.Top + 34 * FScale,
      R.Right - 10 * FScale, R.Top + 42 * FScale);
    ACanvas.Fill.Color := TAlphaColor($FF1C4355);
    ACanvas.FillRect(Track, 4 * FScale, 4 * FScale, AllCorners, 1);
    Fill := Track;
    Fill.Right := Fill.Left + Fill.Width * Pct / 100;
    ACanvas.Fill.Color := LimitColor(Pct);
    ACanvas.FillRect(Fill, 4 * FScale, 4 * FScale, AllCorners, 1);
    Text(ACanvas, TRectF.Create(R.Left + 10 * FScale, R.Top + 45 * FScale,
      R.Right - 10 * FScale, R.Bottom - 3 * FScale),
      FormatMoney(FSnapshot.PeriodCost, FSnapshot.Currency) + ' von ' +
      FormatMoney(FSnapshot.SpendingLimit, FSnapshot.Currency), 8, CMuted);
    Inc(I);
  end;
  while (I < Cards) and (I - Ord(FSnapshot.SpendingLimit > 0) < Count) do
  begin
    X := ARect.Left + 15 * FScale + I * (CardW + Gap);
    R := TRectF.Create(X, ARect.Top + 38 * FScale, X + CardW,
      ARect.Bottom - 10 * FScale);
    Box(ACanvas, R, TAlphaColor($FF091D25), CBlueBorder, 10);
    with FSnapshot.RateLimits[I - Ord(FSnapshot.SpendingLimit > 0)] do
    begin
      Pct := Clamp(UsedPercent, 0, 100);
      NameText := Name;
      Text(ACanvas, TRectF.Create(R.Left + 10 * FScale, R.Top + 5 * FScale,
        R.Right - 55 * FScale, R.Top + 27 * FScale), NameText, 9, CText, True);
      Text(ACanvas, TRectF.Create(R.Right - 55 * FScale, R.Top + 5 * FScale,
        R.Right - 9 * FScale, R.Top + 27 * FScale), FormatFloat('0', Pct) + '%',
        15, LimitColor(Pct), True, TTextAlign.Trailing);
      Track := TRectF.Create(R.Left + 10 * FScale, R.Top + 34 * FScale,
        R.Right - 10 * FScale, R.Top + 42 * FScale);
      ACanvas.Fill.Color := TAlphaColor($FF1C4355);
      ACanvas.FillRect(Track, 4 * FScale, 4 * FScale, AllCorners, 1);
      Fill := Track;
      Fill.Right := Fill.Left + Fill.Width * Pct / 100;
      ACanvas.Fill.Color := LimitColor(Pct);
      ACanvas.FillRect(Fill, 4 * FScale, 4 * FScale, AllCorners, 1);
      if ResetsAt > 0 then
        ResetText := WindowName + ' · Reset ' + FormatDateTime('dd.mm. hh:nn', ResetsAt)
      else
        ResetText := WindowName;
      Text(ACanvas, TRectF.Create(R.Left + 10 * FScale, R.Top + 45 * FScale,
        R.Right - 10 * FScale, R.Bottom - 3 * FScale), ResetText, 8, CMuted);
    end;
    Inc(I);
  end;
  if Cards = 1 then
    if (Count = 0) and (FSnapshot.SpendingLimit <= 0) then
      Text(ACanvas, TRectF.Create(ARect.Left + 15 * FScale,
        ARect.Top + 38 * FScale, ARect.Right - 15 * FScale,
        ARect.Bottom - 10 * FScale),
        'Kein Limit geliefert. Ein Budget kann in den Einstellungen hinterlegt werden.',
        10, CMuted, False, TTextAlign.Center);
end;

procedure TDashboardRenderer.DrawCodex(const ACanvas: TCanvas;
  const ARect: TRectF);
var
  Gap, W: Single;
  TodayDetail: string;

  function TokenValue(const AValue: Int64; const AAvailable: Boolean): string;
  begin
    if AAvailable then
      Result := CompactNumber(AValue)
    else
      Result := '–';
  end;

  function UsageDetail(const AText: string; const AAvailable: Boolean): string;
  begin
    if AAvailable then
      Result := AText
    else
      Result := 'Abfrage nicht verfügbar';
  end;

  function MonthDetail: string;
  begin
    if FSnapshot.CodexRateLimitsAvailable then
      Result := 'Reset-Credits: ' + IntToStr(FSnapshot.CodexResetCredits)
    else
      Result := 'aktueller Kalendermonat';
  end;

begin
  if FSnapshot.CodexTodayUsageAvailable then
    TodayDetail := 'lokaler Kalendertag'
  else
    TodayDetail := 'Heute noch nicht gemeldet';
  Box(ACanvas, ARect, CBluePanel, CBlueBorder);
  Text(ACanvas, TRectF.Create(ARect.Left + 15 * FScale, ARect.Top + 5 * FScale,
    ARect.Right - 12 * FScale, ARect.Top + 34 * FScale),
    'Codex · ChatGPT-Nutzung', 15, CText, True);
  Gap := 8 * FScale;
  W := (ARect.Width - 30 * FScale - Gap * 3) / 4;
  DrawKpi(ACanvas, TRectF.Create(ARect.Left + 15 * FScale, ARect.Top + 38 * FScale,
    ARect.Left + 15 * FScale + W, ARect.Bottom - 10 * FScale),
    'Tokens gesamt', TokenValue(FSnapshot.CodexLifetimeTokens,
      FSnapshot.CodexLifetimeAvailable), UsageDetail('lokaler Codex App Server',
      FSnapshot.CodexLifetimeAvailable));
  DrawKpi(ACanvas, TRectF.Create(ARect.Left + 15 * FScale + (W + Gap),
    ARect.Top + 38 * FScale, ARect.Left + 15 * FScale + (W + Gap) + W,
    ARect.Bottom - 10 * FScale), 'Tokens heute', TokenValue(FSnapshot.CodexTodayTokens,
      FSnapshot.CodexTodayUsageAvailable), TodayDetail);
  DrawKpi(ACanvas, TRectF.Create(ARect.Left + 15 * FScale + 2 * (W + Gap),
    ARect.Top + 38 * FScale, ARect.Left + 15 * FScale + 2 * (W + Gap) + W,
    ARect.Bottom - 10 * FScale), 'Tokens · 7 Tage',
    TokenValue(FSnapshot.CodexSevenDayTokens, FSnapshot.CodexDailyUsageAvailable),
    UsageDetail('rollierend', FSnapshot.CodexDailyUsageAvailable));
  DrawKpi(ACanvas, TRectF.Create(ARect.Left + 15 * FScale + 3 * (W + Gap),
    ARect.Top + 38 * FScale, ARect.Right - 15 * FScale, ARect.Bottom - 10 * FScale),
    'Tokens · Monat', TokenValue(FSnapshot.CodexMonthTokens,
      FSnapshot.CodexDailyUsageAvailable), UsageDetail(MonthDetail,
      FSnapshot.CodexDailyUsageAvailable));
end;

procedure TDashboardRenderer.Render(const ACanvas: TCanvas; const ARect: TRectF);
var
  Margin, Gap, HeaderH, KpiH, ContentTop, ContentBottom, ColLeftW,
    SideW, Left, Top, KpiW, SideTop, ModelH, FooterH: Single;
  I: Integer;
  KpiRects: array[0..3] of TRectF;
  LimitPct, Detail: string;
begin
  if (ACanvas = nil) or (ARect.Width <= 0) or (ARect.Height <= 0) then
    Exit;
  FScale := Clamp(Min(ARect.Width / 1920, ARect.Height / 1080), 0.62, 1.35);
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := CBackground;
  ACanvas.FillRect(ARect, 1);
  Margin := Clamp(ARect.Width * 0.019, 12, 36);
  Gap := 12 * FScale;
  HeaderH := 78 * FScale;
  KpiH := 112 * FScale;
  FooterH := 18 * FScale;
  DrawHeader(ACanvas, TRectF.Create(ARect.Left + Margin, ARect.Top + 15 * FScale,
    ARect.Right - Margin, ARect.Top + 15 * FScale + HeaderH));
  Top := ARect.Top + 15 * FScale + HeaderH + Gap;
  KpiW := (ARect.Width - 2 * Margin - 3 * Gap) / 4;
  for I := 0 to 3 do
    KpiRects[I] := TRectF.Create(ARect.Left + Margin + I * (KpiW + Gap), Top,
      ARect.Left + Margin + I * (KpiW + Gap) + KpiW, Top + KpiH);
  DrawKpi(ACanvas, KpiRects[0], 'Kosten · letzte 30 Tage',
    FormatMoney(FSnapshot.Cost30Days, FSnapshot.Currency), 'alle Projekte der Organisation', True);
  if FSnapshot.CostTodayAvailable then
    DrawKpi(ACanvas, KpiRects[1], 'Kosten · heute (UTC)',
      FormatMoney(FSnapshot.CostToday, FSnapshot.Currency), 'Kosten können zeitverzögert eintreffen')
  else
    DrawKpi(ACanvas, KpiRects[1], 'Kosten · heute (UTC)', '–',
      'Heute noch keine Kosten gemeldet');
  DrawKpi(ACanvas, KpiRects[2], 'Anfragen · letzte 7 Tage',
    CompactNumber(FSnapshot.Requests7Days), CompactNumber(FSnapshot.RequestsToday) + ' heute');
  DrawKpi(ACanvas, KpiRects[3], 'Tokens · letzte 7 Tage',
    CompactNumber(FSnapshot.Tokens7Days), CompactNumber(FSnapshot.TokensToday) + ' heute');

  ContentTop := Top + KpiH + Gap;
  ContentBottom := ARect.Bottom - Margin - FooterH;
  ColLeftW := (ARect.Width - 2 * Margin - Gap) * 0.61;
  SideW := ARect.Width - 2 * Margin - Gap - ColLeftW;
  SideTop := ContentTop;
  ModelH := (ContentBottom - ContentTop) * 0.36;
  DrawChart(ACanvas, TRectF.Create(ARect.Left + Margin, ContentTop,
    ARect.Left + Margin + ColLeftW, ContentTop + (ContentBottom - ContentTop) * 0.61));
  DrawLimits(ACanvas, TRectF.Create(ARect.Left + Margin,
    ContentTop + (ContentBottom - ContentTop) * 0.61 + Gap,
    ARect.Left + Margin + ColLeftW,
    ContentTop + (ContentBottom - ContentTop) * 0.78));
  DrawCodex(ACanvas, TRectF.Create(ARect.Left + Margin,
    ContentTop + (ContentBottom - ContentTop) * 0.78 + Gap,
    ARect.Left + Margin + ColLeftW, ContentBottom));
  Left := ARect.Left + Margin + ColLeftW + Gap;
  DrawModels(ACanvas, TRectF.Create(Left, SideTop, Left + SideW, SideTop + ModelH));
  DrawServices(ACanvas, TRectF.Create(Left, SideTop + ModelH + Gap,
    Left + SideW, ContentBottom));
  if FSnapshot.SpendingLimit > 0 then
    LimitPct := FormatFloat('0', 100 * FSnapshot.PeriodCost / FSnapshot.SpendingLimit) + '%'
  else
    LimitPct := 'kein Budget';
  Detail := FSnapshot.SourceText + ' · Periode ' +
    FormatDateTime('dd.mm.', FSnapshot.PeriodStart) + '–' +
    FormatDateTime('dd.mm.yyyy', FSnapshot.PeriodEnd - 1) + ' · ' + LimitPct;
  Text(ACanvas, TRectF.Create(ARect.Left + Margin, ContentBottom + 2 * FScale,
    ARect.Right - Margin, ARect.Bottom), Detail, 8, CMuted, False,
    TTextAlign.Leading);
end;

procedure TDashboardRenderer.RenderCompanion(const ACanvas: TCanvas;
  const ARect: TRectF; const ARevealed: Boolean; const ASecondsRemaining: Integer);
var
  Center: TRectF;
begin
  ACanvas.Fill.Color := TAlphaColorRec.Black;
  ACanvas.FillRect(ARect, 1);
  if not ARevealed then
    Exit;
  FScale := Clamp(Min(ARect.Width / 1000, ARect.Height / 700), 0.7, 1.4);
  Center := TRectF.Create(ARect.Left + ARect.Width * 0.16,
    ARect.Top + ARect.Height * 0.2, ARect.Right - ARect.Width * 0.16,
    ARect.Bottom - ARect.Height * 0.2);
  Box(ACanvas, Center, CPanel, CBorder, 18);
  Text(ACanvas, TRectF.Create(Center.Left + 24 * FScale, Center.Top + 20 * FScale,
    Center.Right - 24 * FScale, Center.Top + 72 * FScale),
    'Dashboard läuft auf dem externen Monitor', 22, CText, True,
    TTextAlign.Center);
  Text(ACanvas, TRectF.Create(Center.Left + 24 * FScale, Center.Top + 84 * FScale,
    Center.Right - 24 * FScale, Center.Top + 132 * FScale),
    FSnapshot.StatusText + ' · ' + FormatDateTime('dd.mm.yyyy hh:nn:ss',
    FSnapshot.LastUpdated), 13, CMuted, False, TTextAlign.Center);
  Text(ACanvas, TRectF.Create(Center.Left + 24 * FScale, Center.Top + 140 * FScale,
    Center.Right - 24 * FScale, Center.Top + 200 * FScale),
    'Dieser integrierte Statusbildschirm wird nach ' +
    IntToStr(Max(0, ASecondsRemaining div 60)) + ' Minuten wieder schwarz.',
    12, CMuted, False, TTextAlign.Center);
  Text(ACanvas, TRectF.Create(Center.Left + 24 * FScale, Center.Bottom - 85 * FScale,
    Center.Right - 24 * FScale, Center.Bottom - 25 * FScale),
    'Erneut tippen, um die Einstellungen zu öffnen.', 11, CBlue, False,
    TTextAlign.Center);
end;

end.
