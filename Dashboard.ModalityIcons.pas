unit Dashboard.ModalityIcons;

interface

uses
  System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, Dashboard.ModelReference;

type
  TModelModalityIcons = class(TControl)
  private
    FMetadata: TModelMetadata;
    procedure SetMetadata(const AValue: TModelMetadata);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Metadata: TModelMetadata read FMetadata write SetMetadata;
  end;

implementation

constructor TModelModalityIcons.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := False;
  Width := 134;
  Height := 76;
end;

procedure TModelModalityIcons.SetMetadata(const AValue: TModelMetadata);
begin
  FMetadata := AValue;
  Repaint;
end;

procedure TModelModalityIcons.Paint;
const
  Muted = TAlphaColor($FF83CDB1);
  InColor = TAlphaColor($FF70EDAF);
  OutColor = TAlphaColor($FF67C9F4);
  Disabled = TAlphaColor($FF305143);
var
  Mode: TModelModality;
  Row, I: Integer;
  R: TRectF;
  Modes: TModelModalities;
  Color: TAlphaColor;
  Path: TPathData;

  procedure LabelText(const ARect: TRectF; const AText: string; AColor: TAlphaColor);
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := AColor;
    Canvas.Font.Size := 11;
    Canvas.FillText(ARect, AText, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  end;

  procedure Icon(const ARect: TRectF; AMode: TModelModality; AColor: TAlphaColor);
  var X, Y, W, H: Single;
  begin
    X := ARect.Left + 2;
    Y := ARect.Top + 3;
    W := ARect.Width - 4;
    H := ARect.Height - 6;
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := AColor;
    Canvas.Stroke.Thickness := 1.5;
    case AMode of
      mmText:
        begin
          Canvas.DrawLine(TPointF.Create(X, Y), TPointF.Create(X + W, Y), 1);
          Canvas.DrawLine(TPointF.Create(X + W / 2, Y), TPointF.Create(X + W / 2, Y + H), 1);
          Canvas.DrawLine(TPointF.Create(X + W * 0.25, Y + H), TPointF.Create(X + W * 0.75, Y + H), 1);
        end;
      mmImage:
        begin
          Canvas.DrawRect(TRectF.Create(X, Y, X + W, Y + H), 1, 1, [], 1);
          Canvas.DrawEllipse(TRectF.Create(X + W * 0.6, Y + 2, X + W * 0.8, Y + 5), 1);
          Path.Clear;
          Path.MoveTo(TPointF.Create(X + 2, Y + H - 2));
          Path.LineTo(TPointF.Create(X + W * 0.4, Y + H * 0.4));
          Path.LineTo(TPointF.Create(X + W * 0.65, Y + H * 0.75));
          Path.LineTo(TPointF.Create(X + W - 2, Y + H * 0.55));
          Canvas.DrawPath(Path, 1);
        end;
      mmAudio:
        begin
          Canvas.DrawLine(TPointF.Create(X + 2, Y + H * 0.35), TPointF.Create(X + 2, Y + H * 0.65), 1);
          Canvas.DrawLine(TPointF.Create(X + W * 0.3, Y + H * 0.15), TPointF.Create(X + W * 0.3, Y + H * 0.85), 1);
          Canvas.DrawLine(TPointF.Create(X + W * 0.6, Y), TPointF.Create(X + W * 0.6, Y + H), 1);
          Canvas.DrawLine(TPointF.Create(X + W - 2, Y + H * 0.25), TPointF.Create(X + W - 2, Y + H * 0.75), 1);
        end;
      mmVideo:
        begin
          Canvas.DrawRect(TRectF.Create(X, Y, X + W, Y + H), 1, 1, [], 1);
          Path.Clear;
          Path.MoveTo(TPointF.Create(X + W * 0.35, Y + H * 0.2));
          Path.LineTo(TPointF.Create(X + W * 0.75, Y + H * 0.5));
          Path.LineTo(TPointF.Create(X + W * 0.35, Y + H * 0.8));
          Path.ClosePath;
          Canvas.DrawPath(Path, 1);
        end;
    end;
  end;

begin
  inherited;
  Path := TPathData.Create;
  try
    LabelText(TRectF.Create(0, 0, Width, 18), 'Inhalte', Muted);
    for Row := 0 to 1 do
    begin
      if Row = 0 then
      begin
        Modes := FMetadata.InputModalities;
        Color := InColor;
        LabelText(TRectF.Create(0, 20, 25, 43), 'IN', Muted);
      end
      else
      begin
        Modes := FMetadata.OutputModalities;
        Color := OutColor;
        LabelText(TRectF.Create(0, 45, 25, 68), 'OUT', Muted);
      end;
      if not FMetadata.ModalitiesKnown then
      begin
        LabelText(TRectF.Create(28, 20 + Row * 25, Width, 43 + Row * 25), 'unbekannt', Muted);
        Continue;
      end;
      I := 0;
      for Mode := Low(TModelModality) to High(TModelModality) do
      begin
        R := TRectF.Create(28 + I * 25, 20 + Row * 25, 49 + I * 25, 43 + Row * 25);
        if Mode in Modes then Icon(R, Mode, Color) else Icon(R, Mode, Disabled);
        Inc(I);
      end;
    end;
  finally
    Path.Free;
  end;
end;

end.
