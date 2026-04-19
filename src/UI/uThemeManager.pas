unit uThemeManager;

interface

uses
  System.UIConsts, System.UITypes, System.Classes, FMX.Types, FMX.Objects, 
  FMX.Forms, FMX.Graphics, FMX.ListBox, FMX.Memo, FMX.StdCtrls, FMX.Layouts, FMX.Edit;

type
  TThemeType = (ttLight, ttDark);

  TThemeManager = class
  private
    class function ColorIf(Condition: Boolean; TrueVal, FalseVal: Cardinal): Cardinal;
  public
    class procedure ApplyTheme(AForm: TForm; ATheme: TThemeType);
    class procedure SetGradient(ARect: TRectangle; ATheme: TThemeType);
  end;

const
  // Nocturnal Architect Colors (ARGB)
  N_SURFACE            = $FF0E0E0E;
  N_SURFACE_LOW        = $FF131313;
  N_SURFACE_CONTAINER  = $FF1A1A1A;
  N_SURFACE_HIGH       = $FF20201F;
  N_SURFACE_HIGHEST    = $FF262626;
  N_SURFACE_LOWEST     = $FF000000;
  N_PRIMARY            = $FF3FFF8B;
  N_PRIMARY_CONTAINER  = $FF13EA79;
  N_ON_PRIMARY         = $FF005D2C;
  N_SECONDARY_CONTAINER= $FF36485B;
  N_ON_SURFACE         = $FFFFFFFF;
  N_ON_SURFACE_VARIANT = $FFADAAAA;
  N_OUTLINE_VARIANT    = $FF484847;

  // Light Mode Colors (ARGB) - Keep for compatibility or future use
  L_BG_START = $FFFFFFFF;
  L_BG_END   = $FFF2F2F7;
  L_SIDEBAR  = $FFF2F2F2;
  L_ACCENT   = $FF007AFF;
  L_TEXT     = $FF1D1D1F;

  // Dark Mode Colors (ARGB) - Legacy, will be mapped to Nocturnal
  D_BG_START = N_SURFACE;
  D_BG_END   = N_SURFACE;
  D_SIDEBAR  = N_SURFACE_LOWEST;
  D_ACCENT   = N_PRIMARY;
  D_TEXT     = N_ON_SURFACE;

implementation

{ TThemeManager }

class function TThemeManager.ColorIf(Condition: Boolean; TrueVal, FalseVal: Cardinal): Cardinal;
begin
  if Condition then Result := TrueVal else Result := FalseVal;
end;

class procedure TThemeManager.ApplyTheme(AForm: TForm; ATheme: TThemeType);
var
  I: Integer;
  Comp: TComponent;
  TextCol, SubTextCol: Cardinal;
begin
  TextCol := ColorIf(ATheme = ttLight, L_TEXT, N_ON_SURFACE);
  SubTextCol := ColorIf(ATheme = ttLight, L_TEXT, N_ON_SURFACE_VARIANT);
  
  for I := 0 to AForm.ComponentCount - 1 do
  begin
    Comp := AForm.Components[I];
    
    if Comp is TButton then
    begin
      TButton(Comp).StyledSettings := TButton(Comp).StyledSettings - [TStyledSetting.FontColor];
      if TButton(Comp).StyleLookup = 'actionbuttonstyle' then
      begin
        TButton(Comp).FontColor := ColorIf(ATheme = ttLight, L_ACCENT, N_PRIMARY);
      end
      else
        TButton(Comp).FontColor := TextCol;
    end;

    if Comp is TMemo then
    begin
      TMemo(Comp).StyledSettings := TMemo(Comp).StyledSettings - [TStyledSetting.FontColor];
      TMemo(Comp).TextSettings.FontColor := TextCol;
    end;

    if Comp is TEdit then
    begin
      TEdit(Comp).StyledSettings := TEdit(Comp).StyledSettings - [TStyledSetting.FontColor];
      TEdit(Comp).TextSettings.FontColor := TextCol;
    end;
    
    if Comp is TLabel then
    begin
       TLabel(Comp).StyledSettings := TLabel(Comp).StyledSettings - [TStyledSetting.FontColor];
       if TLabel(Comp).StyleLookup = 'sublabel' then
         TLabel(Comp).TextSettings.FontColor := SubTextCol
       else
         TLabel(Comp).TextSettings.FontColor := TextCol;
    end;
  end;
end;

class procedure TThemeManager.SetGradient(ARect: TRectangle; ATheme: TThemeType);
begin
  if not Assigned(ARect) then Exit;
  
  ARect.Fill.Kind := TBrushKind.Solid;
  ARect.Fill.Color := ColorIf(ATheme = ttLight, L_BG_START, N_SURFACE);
  ARect.Stroke.Kind := TBrushKind.None;
end;

end.
