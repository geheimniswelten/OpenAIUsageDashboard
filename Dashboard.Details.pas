unit Dashboard.Details;

interface

uses
  System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Layouts, FMX.Objects, FMX.StdCtrls,
  Dashboard.Model, Dashboard.DetailLayout, Dashboard.ModelReference;

type
  TDashboardDetails = class(TLayout)
  private
    FPanel: TRectangle;
    FTitle, FSubtitle, FFooter: TLabel;
    FClose: TButton;
    FScroll: TScrollBox;
    FKind: TDashboardDetailKind;
    FSnapshot: TUsageSnapshot;
    FOnInteraction: TNotifyEvent;
    FRows: TArray<TRectangle>;
    procedure CloseClicked(Sender: TObject);
    procedure MouseInteraction(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    function NewLabel(AParent: TFmxObject; const AText: string;
      const ASize: Single; const ABold: Boolean = False): TLabel;
    procedure AddRow(const AName: string; const ACaptions, AValues: array of string);
    procedure AddPriceMetadata(const AModel: TModelReference);
    procedure LayoutRows;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Open(const AKind: TDashboardDetailKind; const ASnapshot: TUsageSnapshot);
    procedure Refresh;
    procedure FitIn(const AViewport: TRectF);
    procedure ScrollTo(const AY: Single);
    procedure Close;
    property Kind: TDashboardDetailKind read FKind;
    property OnInteraction: TNotifyEvent read FOnInteraction write FOnInteraction;
  end;

implementation

uses System.SysUtils, System.Math, System.DateUtils, Dashboard.ModalityIcons;

const
  PanelColor = TAlphaColor($FF0B2018);
  TextColor = TAlphaColor($FFF4FFF9);
  MutedColor = TAlphaColor($FF83CDB1);
  ValueColor = TAlphaColor($FF67C9F4);

function Number(const AValue: Double): string;
var Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Invariant;
  Fmt.DecimalSeparator := ',';
  Fmt.ThousandSeparator := '.';
  Result := FormatFloat('#,##0.##', AValue, Fmt);
end;

function Money(const AValue: Double): string;
var Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Invariant;
  Fmt.DecimalSeparator := ',';
  Fmt.ThousandSeparator := '.';
  Result := FormatFloat('#,##0.00##', AValue, Fmt) + ' $';
end;

constructor TDashboardDetails.Create(AOwner: TComponent);
var Shade: TRectangle;
begin
  inherited;
  Align := TAlignLayout.Client;
  Visible := False;
  Shade := TRectangle.Create(Self);
  Shade.Parent := Self;
  Shade.Align := TAlignLayout.Client;
  Shade.Fill.Color := TAlphaColor($C0000000);
  Shade.Stroke.Kind := TBrushKind.None;
  Shade.OnClick := CloseClicked;
  FPanel := TRectangle.Create(Self);
  FPanel.Parent := Self;
  FPanel.Fill.Color := PanelColor;
  FPanel.Stroke.Color := TAlphaColor($FF2A7053);
  FPanel.XRadius := 14;
  FPanel.YRadius := 14;
  FPanel.OnMouseDown := MouseInteraction;
  FTitle := NewLabel(FPanel, '', 21, True);
  FSubtitle := NewLabel(FPanel, '', 13);
  FFooter := NewLabel(FPanel, '', 12);
  FClose := TButton.Create(FPanel);
  FClose.Parent := FPanel;
  FClose.Text := 'Schließen';
  FClose.OnClick := CloseClicked;
  FScroll := TScrollBox.Create(FPanel);
  FScroll.Parent := FPanel;
  FScroll.ShowScrollBars := True;
  FScroll.ApplyStyleLookup;
  FScroll.OnMouseDown := MouseInteraction;
end;

function TDashboardDetails.NewLabel(AParent: TFmxObject; const AText: string;
  const ASize: Single; const ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  Result.Text := AText;
  Result.HitTest := False;
  Result.StyledSettings := [];
  Result.TextSettings.Font.Size := ASize;
  Result.TextSettings.FontColor := TextColor;
  Result.TextSettings.VertAlign := TTextAlign.Leading;
  if ABold then Result.TextSettings.Font.Style := [TFontStyle.fsBold];
  Result.WordWrap := True;
  Result.ApplyStyleLookup;
end;

procedure TDashboardDetails.MouseInteraction(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Assigned(FOnInteraction) then FOnInteraction(Self);
end;

procedure TDashboardDetails.CloseClicked(Sender: TObject);
begin
  Close;
end;

procedure TDashboardDetails.Close;
begin
  if Assigned(FOnInteraction) then FOnInteraction(Self);
  Visible := False;
end;

procedure TDashboardDetails.Open(const AKind: TDashboardDetailKind;
  const ASnapshot: TUsageSnapshot);
begin
  if (AKind = dkNone) or (ASnapshot = nil) then Exit;
  FKind := AKind;
  FSnapshot := ASnapshot;
  Refresh;
  Visible := True;
  FScroll.ApplyStyleLookup;
  BringToFront;
  FitIn(LocalRect);
  FScroll.ViewportPosition := TPointF.Zero;
  FClose.SetFocus;
end;

procedure TDashboardDetails.AddRow(const AName: string;
  const ACaptions, AValues: array of string);
var Row: TRectangle; Caption, Value: TText; I, N: Integer;
  function RowText(const AText: string; const ASize: Single; const ABold: Boolean = False): TText;
  begin
    Result := TText.Create(Row);
    Result.Parent := Row;
    Result.Text := AText;
    Result.HitTest := False;
    Result.TextSettings.Font.Size := ASize;
    Result.TextSettings.FontColor := TextColor;
    Result.TextSettings.VertAlign := TTextAlign.Leading;
    Result.TextSettings.HorzAlign := TTextAlign.Leading;
    if ABold then Result.TextSettings.Font.Style := [TFontStyle.fsBold];
    Result.WordWrap := True;
  end;
begin
  Row := TRectangle.Create(FScroll);
  Row.Parent := FScroll;
  Row.Fill.Color := TAlphaColor($FF081B14);
  Row.Stroke.Color := TAlphaColor($FF214D3B);
  Row.XRadius := 9;
  Row.YRadius := 9;
  Row.HitTest := False;
  RowText(AName, 16, True);
  for I := 0 to High(ACaptions) do
  begin
    Caption := RowText(ACaptions[I], 11);
    Caption.TextSettings.FontColor := MutedColor;
    Value := RowText(AValues[I], 14, True);
    Value.TextSettings.FontColor := ValueColor;
  end;
  N := Length(FRows);
  SetLength(FRows, N + 1);
  FRows[N] := Row;
end;

procedure TDashboardDetails.AddPriceMetadata(const AModel: TModelReference);
var
  Row: TRectangle;
  Icons: TModelModalityIcons;
  Field: TText;
  I: Integer;
  Values: array[0..5] of string;
  function DateText(const ADate: TDateTime): string;
  begin
    if ADate > 0 then Result := FormatDateTime('dd.mm.yyyy', ADate) else Result := '–';
  end;
begin
  if Length(FRows) = 0 then Exit;
  Row := FRows[High(FRows)];
  Values[0] := 'Veröffentlicht: ' + DateText(AModel.Metadata.PublishedAt);
  Values[1] := 'Wissensstand: ' + DateText(AModel.Metadata.KnowledgeCutoff);
  Values[2] := 'Modellupdate: ' + DateText(AModel.Metadata.ModelUpdatedAt);
  if AModel.Metadata.ContextTokens > 0 then
    Values[3] := 'Kontext: ' + Number(AModel.Metadata.ContextTokens) + ' Tokens'
  else
    Values[3] := 'Kontext: –';
  Values[4] := 'Status: –';
  if AModel.Metadata.Status = 'active' then Values[4] := 'Status: Aktuell';
  if AModel.Metadata.Status = 'deprecated' then Values[4] := 'Status: Abgekündigt';
  if AModel.Metadata.Status = 'shutdown' then Values[4] := 'Status: Abgeschaltet';
  Values[5] := 'Abschaltung: ' + DateText(AModel.Metadata.ShutdownAt);
  if (AModel.Metadata.ShutdownAt = 0) and AModel.Metadata.ShutdownKnown then
    Values[5] := 'Abschaltung: nicht angekündigt';
  for I := 0 to High(Values) do
  begin
    Field := TText.Create(Row);
    Field.Parent := Row;
    Field.Tag := 100 + I;
    Field.Text := Values[I];
    Field.TextSettings.Font.Size := 12;
    Field.TextSettings.FontColor := MutedColor;
    Field.TextSettings.HorzAlign := TTextAlign.Leading;
    Field.TextSettings.VertAlign := TTextAlign.Leading;
    Field.HitTest := False;
    Field.WordWrap := True;
    if (I >= 4) and ((AModel.Metadata.ShutdownAt > 0) or
      (AModel.Metadata.Status = 'deprecated') or (AModel.Metadata.Status = 'shutdown')) then
    begin
      Field.TextSettings.FontColor := TAlphaColor($FFFFD166);
      if (AModel.Metadata.Status = 'shutdown') or ((AModel.Metadata.ShutdownAt > 0) and
        (DateOf(AModel.Metadata.ShutdownAt) <= DateOf(TTimeZone.Local.ToUniversalTime(Now)))) then
        Field.TextSettings.FontColor := TAlphaColor($FFFF7D7D);
    end;
  end;
  Icons := TModelModalityIcons.Create(Row);
  Icons.Parent := Row;
  Icons.Tag := 200;
  Icons.Metadata := AModel.Metadata;
end;

procedure TDashboardDetails.Refresh;
var
  I: Integer;
  Services: TArray<TServiceUsage>;
  Models: TArray<TModelReference>;
  Value, Status, InputPrice, OutputPrice, Score: string;
  PreviousPosition: TPointF;
begin
  if FSnapshot = nil then Exit;
  PreviousPosition := FScroll.ViewportPosition;
  for I := 0 to High(FRows) do FRows[I].Free;
  FRows := nil;
  FFooter.Text := '';
  case FKind of
    dkModels:
      begin
        FTitle.Text := 'Alle API-Modelle';
        FSubtitle.Text := Format('%d Modelle · letzte 7 Tage · nach Tokens sortiert',
          [Length(FSnapshot.Models)]);
        for I := 0 to High(FSnapshot.Models) do
          AddRow(FSnapshot.Models[I].Model, ['Anfragen', 'Tokens'],
            [Number(FSnapshot.Models[I].Requests), Number(FSnapshot.Models[I].Tokens)]);
        FFooter.Text := 'API-Nutzung der Organisation · Eingabe und Ausgabe zusammengerechnet';
      end;
    dkServices:
      begin
        Services := FSnapshot.GetServicesByUsage;
        FTitle.Text := 'Alle API-Dienste';
        FSubtitle.Text := Format('%d Dienste · nach Nutzung sortiert', [Length(Services)]);
        for I := 0 to High(Services) do
        begin
          if Services[I].Available then
          begin
            Value := Trim(Number(Services[I].Value) + ' ' + Services[I].UnitText);
            Status := 'Verfügbar';
            InputPrice := Number(Services[I].Requests);
          end
          else
          begin
            Value := '–';
            Status := 'Nicht verfügbar';
            InputPrice := '–';
          end;
          AddRow(Services[I].Name, ['Nutzung', 'Anfragen', 'Daten'], [Value, InputPrice, Status]);
        end;
        FFooter.Text := 'Gemeldete Nullwerte werden als 0 angezeigt; fehlende Daten als –.';
      end;
    dkPrices:
      begin
        Models := FSnapshot.PriceCatalog.Models;
        FTitle.Text := 'Alle Modellpreise';
        FSubtitle.Text := Format('%d Modelle · USD je 1 Mio. Tokens · Standard · ohne Cache', [Length(Models)]);
        for I := 0 to High(Models) do
        begin
          InputPrice := '–';
          OutputPrice := '–';
          if Models[I].PriceAvailable then
          begin
            InputPrice := Money(Models[I].InputPerMillion);
            OutputPrice := Money(Models[I].OutputPerMillion);
          end;
          Score := '–';
          if Models[I].Intelligence >= 0 then Score := IntToStr(Models[I].Intelligence);
          AddRow(Models[I].Name, ['Eingabe', 'Ausgabe', 'Index'], [InputPrice, OutputPrice, Score]);
          AddPriceMetadata(Models[I]);
        end;
        FFooter.Text := 'OpenAI-Preise · Stand ' + FormatDateTime('dd.mm.yyyy', FSnapshot.PriceCatalog.UpdatedAt) +
          ' · ' + FSnapshot.PriceCatalog.StatusText + sLineBreak +
          ModelReferenceIndex + ' · Indexstand ' + ModelReferenceDate + sLineBreak +
          'Symbole: Text · Bild · Audio · Video. IN = Eingabe, OUT = Ausgabe. Fehlende Angaben: –';
      end;
  end;
  if Length(FRows) = 0 then
    AddRow('Noch keine Daten vorhanden', ['Status'], ['Bitte nach der nächsten Aktualisierung erneut öffnen.']);
  FitIn(LocalRect);
  FScroll.ViewportPosition := PreviousPosition;
end;

procedure TDashboardDetails.LayoutRows;
var
  I, J, Count, MetaColumns, MetaRows, Index: Integer;
  Row: TRectangle;
  Control: TControl;
  CellWidth, ListWidth, Y, RowHeight, MetaWidth: Single;
  SideIcons: Boolean;
begin
  if FScroll = nil then Exit;
  ListWidth := Max(1, FScroll.Width - 20);
  Y := 0;
  for I := 0 to High(FRows) do
  begin
    Row := FRows[I];
    Count := (Row.ChildrenCount - 1) div 2;
    RowHeight := 104;
    MetaColumns := 1;
    SideIcons := ListWidth >= 340;
    if (FKind = dkPrices) and (Row.ChildrenCount > 7) then
    begin
      Count := 3;
      if ListWidth >= 700 then MetaColumns := 2;
      MetaRows := 6 div MetaColumns;
      RowHeight := 108 + MetaRows * 23 + 8;
      if not SideIcons then RowHeight := RowHeight + 80;
    end;
    Row.SetBounds(0, Y, ListWidth, RowHeight);
    TControl(Row.Children[0]).SetBounds(12, 8, ListWidth - 24, 40);
    if Count <= 0 then Continue;
    CellWidth := (ListWidth - 24) / Count;
    for J := 0 to Count - 1 do
    begin
      TControl(Row.Children[1 + J * 2]).SetBounds(12 + J * CellWidth, 49, CellWidth - 6, 17);
      TControl(Row.Children[2 + J * 2]).SetBounds(12 + J * CellWidth, 67, CellWidth - 6, 32);
    end;
    if (FKind = dkPrices) and (Row.ChildrenCount > 7) then
    begin
      MetaWidth := ListWidth - 24;
      if SideIcons then MetaWidth := MetaWidth - 152;
      for J := 7 to Row.ChildrenCount - 1 do
        if Row.Children[J] is TControl then
        begin
          Control := TControl(Row.Children[J]);
          if (Control.Tag >= 100) and (Control.Tag < 106) then
          begin
            Index := Control.Tag - 100;
            Control.SetBounds(12 + (Index mod MetaColumns) * (MetaWidth / MetaColumns),
              108 + (Index div MetaColumns) * 23, MetaWidth / MetaColumns - 6, 22);
          end
          else if Control.Tag = 200 then
          begin
            if SideIcons then
              Control.SetBounds(ListWidth - 146, 108, 134, 76)
            else
              Control.SetBounds(12, RowHeight - 82, 134, 76);
          end;
        end;
    end;
    Y := Y + RowHeight + 8;
  end;
  FScroll.RealignContent;
end;

procedure TDashboardDetails.FitIn(const AViewport: TRectF);
var Margin, W, H, MaxWidth, FooterHeight: Single;
begin
  if FScroll = nil then Exit;
  Margin := Min(16, Max(0, Min(AViewport.Width, AViewport.Height) / 30));
  MaxWidth := 860;
  if FKind = dkPrices then MaxWidth := 1040;
  W := Max(1, Min(MaxWidth, AViewport.Width - 2 * Margin));
  H := Max(1, Min(780, AViewport.Height - 2 * Margin));
  FPanel.SetBounds(AViewport.Left + (AViewport.Width - W) / 2,
    AViewport.Top + (AViewport.Height - H) / 2, W, H);
  FTitle.SetBounds(18, 16, Max(1, W - 156), 58);
  FClose.SetBounds(Max(0, W - 126), 16, 108, 38);
  FSubtitle.SetBounds(18, 76, Max(1, W - 36), 44);
  FSubtitle.TextSettings.FontColor := MutedColor;
  FooterHeight := 60;
  if FKind = dkPrices then FooterHeight := 92;
  if (FKind = dkPrices) and (W < 600) then FooterHeight := 116;
  FFooter.SetBounds(18, Max(120, H - FooterHeight - 8), Max(1, W - 36), FooterHeight);
  FFooter.TextSettings.FontColor := MutedColor;
  FScroll.SetBounds(18, 124, Max(1, W - 36), Max(1, H - FooterHeight - 144));
  LayoutRows;
end;

procedure TDashboardDetails.Resize;
begin
  inherited;
  FitIn(LocalRect);
end;

procedure TDashboardDetails.ScrollTo(const AY: Single);
begin
  FScroll.ViewportPosition := TPointF.Create(0, EnsureRange(AY, Single(0),
    Max(Single(0), FScroll.ContentBounds.Bottom - FScroll.ClientHeight)));
end;

end.
