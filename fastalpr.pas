{ License plate recognition in pure Free Pascal / Lazarus, using the FastALPR models:
    - detector: open-image-models  yolo-v9-*-license-plate-end2end.onnx
    - OCR:      fast-plate-ocr     cct_*.onnx + *_plate_config.yaml

  Pre- and post-processing follow fast-alpr 0.4 / open-image-models 0.6 /
  fast-plate-ocr 1.1 so the results match the Python version.

  Works with any TFPCustomImage (TFPMemoryImage, Lazarus TLazIntfImage, ...)
  or with a raw pixel buffer. }
unit FastAlpr;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, FPImage, OnnxRT;

type
  { 8-bit RGB image, row-major, 3 bytes per pixel, no row padding. }
  TRGBImage = record
    Width, Height: Integer;
    Pix: TBytes;
  end;

  TPlateBox = record
    X1, Y1, X2, Y2: Integer;  // in pixels of the original image
    Score: Single;            // detector confidence 0..1
  end;
  TPlateBoxes = array of TPlateBox;

  TPlateText = record
    Text: string;              // e.g. 'CM6026BA' (pad characters removed)
    CharProbs: TSingleArray;   // probability of every slot, including padding slots
    Confidence: Single;        // mean of CharProbs (what fast-alpr draws on the image)
    Region: string;            // country, only with v2 models ('' otherwise)
    RegionProb: Single;
  end;

  TPlateResult = record
    Box: TPlateBox;
    Plate: TPlateText;
  end;
  TPlateResults = array of TPlateResult;

  { Contents of *_plate_config.yaml }
  TPlateConfig = class
  public
    MaxPlateSlots: Integer;
    Alphabet: string;
    PadChar: Char;
    ImgHeight, ImgWidth: Integer;
    KeepAspectRatio: Boolean;
    Grayscale: Boolean;
    PaddingColor: Byte;
    Regions: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
  end;

  TPlateDetector = class
  private
    FSession: TOrtSession;
    FSizeW, FSizeH: Integer;
  public
    ConfThreshold: Single;  // fast-alpr default 0.4
    constructor Create(RT: TOrtRuntime; const ModelFile: string; Threads: Integer = 0);
    destructor Destroy; override;
    function Detect(const Img: TRGBImage): TPlateBoxes;
  end;

  TPlateOCR = class
  private
    FSession: TOrtSession;
    FConfig: TPlateConfig;
  public
    constructor Create(RT: TOrtRuntime; const ModelFile, ConfigFile: string; Threads: Integer = 0);
    destructor Destroy; override;
    { Img is an already cropped plate. }
    function Recognize(const Img: TRGBImage): TPlateText;
    property Config: TPlateConfig read FConfig;
  end;

  { Complete pipeline: detect plates, crop, read them. }
  TAlpr = class
  private
    FRT: TOrtRuntime;
    FOwnsRT: Boolean;
    FDetector: TPlateDetector;
    FOCR: TPlateOCR;
  public
    { OrtLib: path to onnxruntime.dll ('' = default search). }
    constructor Create(const OrtLib, DetectorModel, OcrModel, OcrConfig: string;
      Threads: Integer = 0);
    constructor Create(RT: TOrtRuntime; const DetectorModel, OcrModel, OcrConfig: string;
      Threads: Integer = 0);
    destructor Destroy; override;
    function Predict(const Img: TRGBImage): TPlateResults;
    function Predict(Img: TFPCustomImage): TPlateResults;
    function PredictFile(const FileName: string): TPlateResults;
    property Detector: TPlateDetector read FDetector;
    property OCR: TPlateOCR read FOCR;
    property Runtime: TOrtRuntime read FRT;
  end;

{ Image helpers }
function RGBImageFromFP(Img: TFPCustomImage): TRGBImage;
{ Data points at the first row; BytesPerPixel 3 or 4; BGROrder = True for Windows bitmaps (BGRA). }
function RGBImageFromRaw(Data: PByte; Width, Height, Stride, BytesPerPixel: Integer;
  BGROrder: Boolean): TRGBImage;
function LoadRGBImage(const FileName: string): TRGBImage;
function CropRGB(const Img: TRGBImage; X1, Y1, X2, Y2: Integer): TRGBImage;
{ Bilinear resize, same sampling as OpenCV INTER_LINEAR (half-pixel centres, edge clamp). }
function ResizeRGB(const Img: TRGBImage; NewW, NewH: Integer): TRGBImage;

implementation

uses
  FPReadJPEG, FPReadPNG, FPReadBMP;

{ ---------- image helpers ---------- }

function RGBImageFromFP(Img: TFPCustomImage): TRGBImage;
var
  X, Y, I: Integer;
  C: TFPColor;
begin
  Result.Width := Img.Width;
  Result.Height := Img.Height;
  SetLength(Result.Pix, Img.Width * Img.Height * 3);
  I := 0;
  for Y := 0 to Img.Height - 1 do
    for X := 0 to Img.Width - 1 do
    begin
      C := Img.Colors[X, Y];  // alpha is ignored, like cv2.imread
      Result.Pix[I] := C.Red shr 8;
      Result.Pix[I + 1] := C.Green shr 8;
      Result.Pix[I + 2] := C.Blue shr 8;
      Inc(I, 3);
    end;
end;

function RGBImageFromRaw(Data: PByte; Width, Height, Stride, BytesPerPixel: Integer;
  BGROrder: Boolean): TRGBImage;
var
  X, Y, I: Integer;
  P: PByte;
begin
  Result.Width := Width;
  Result.Height := Height;
  SetLength(Result.Pix, Width * Height * 3);
  I := 0;
  for Y := 0 to Height - 1 do
  begin
    P := Data + PtrInt(Y) * Stride;
    for X := 0 to Width - 1 do
    begin
      if BGROrder then
      begin
        Result.Pix[I] := P[2];
        Result.Pix[I + 1] := P[1];
        Result.Pix[I + 2] := P[0];
      end
      else
      begin
        Result.Pix[I] := P[0];
        Result.Pix[I + 1] := P[1];
        Result.Pix[I + 2] := P[2];
      end;
      Inc(P, BytesPerPixel);
      Inc(I, 3);
    end;
  end;
end;

function LoadRGBImage(const FileName: string): TRGBImage;
var
  Img: TFPMemoryImage;
begin
  Img := TFPMemoryImage.Create(0, 0);
  try
    Img.LoadFromFile(FileName);
    Result := RGBImageFromFP(Img);
  finally
    Img.Free;
  end;
end;

function CropRGB(const Img: TRGBImage; X1, Y1, X2, Y2: Integer): TRGBImage;
var
  Y, RowLen: Integer;
begin
  Result.Width := Max(0, X2 - X1);
  Result.Height := Max(0, Y2 - Y1);
  SetLength(Result.Pix, Result.Width * Result.Height * 3);
  RowLen := Result.Width * 3;
  if RowLen = 0 then
    Exit;
  for Y := 0 to Result.Height - 1 do
    Move(Img.Pix[((Y1 + Y) * Img.Width + X1) * 3], Result.Pix[Y * RowLen], RowLen);
end;

function ResizeRGB(const Img: TRGBImage; NewW, NewH: Integer): TRGBImage;
var
  X, Y, C: Integer;
  SX0, SX1, SY0, SY1: array of Integer;
  FX, FY: array of Single;
  ScaleX, ScaleY, F, V: Single;
  Row0, Row1, Dst: Integer;

  procedure Map(DstLen, SrcLen: Integer; Scale: Single; var S0, S1: array of Integer;
    var Frac: array of Single);
  var
    D, S: Integer;
  begin
    for D := 0 to DstLen - 1 do
    begin
      F := (D + 0.5) * Scale - 0.5;
      S := Floor(F);
      F := F - S;
      if S < 0 then
      begin
        S := 0;
        F := 0;
      end;
      if S >= SrcLen - 1 then
      begin
        S := SrcLen - 1;
        F := 0;
      end;
      S0[D] := S;
      S1[D] := Min(S + 1, SrcLen - 1);
      Frac[D] := F;
    end;
  end;

begin
  Result.Width := NewW;
  Result.Height := NewH;
  SetLength(Result.Pix, NewW * NewH * 3);
  if (NewW = Img.Width) and (NewH = Img.Height) then
  begin
    Result.Pix := Copy(Img.Pix);
    Exit;
  end;
  SetLength(SX0, NewW); SetLength(SX1, NewW); SetLength(FX, NewW);
  SetLength(SY0, NewH); SetLength(SY1, NewH); SetLength(FY, NewH);
  ScaleX := Img.Width / NewW;
  ScaleY := Img.Height / NewH;
  Map(NewW, Img.Width, ScaleX, SX0, SX1, FX);
  Map(NewH, Img.Height, ScaleY, SY0, SY1, FY);
  Dst := 0;
  for Y := 0 to NewH - 1 do
  begin
    Row0 := SY0[Y] * Img.Width * 3;
    Row1 := SY1[Y] * Img.Width * 3;
    for X := 0 to NewW - 1 do
      for C := 0 to 2 do
      begin
        V := (Img.Pix[Row0 + SX0[X] * 3 + C] * (1 - FX[X]) + Img.Pix[Row0 + SX1[X] * 3 + C] * FX[X]) * (1 - FY[Y])
           + (Img.Pix[Row1 + SX0[X] * 3 + C] * (1 - FX[X]) + Img.Pix[Row1 + SX1[X] * 3 + C] * FX[X]) * FY[Y];
        Result.Pix[Dst] := EnsureRange(Round(V), 0, 255);
        Inc(Dst);
      end;
  end;
end;

{ Resize keeping aspect ratio and pad with Color (YOLO "letterbox").
  Returns the scale ratio and the (unrounded) padding, as in the Python code. }
function Letterbox(const Img: TRGBImage; DstW, DstH: Integer; Color: Byte;
  out Ratio, PadW, PadH: Double): TRGBImage;
var
  NW, NH, Top, Left, Y: Integer;
  R: TRGBImage;
begin
  Ratio := Min(DstH / Img.Height, DstW / Img.Width);
  NW := Round(Img.Width * Ratio);   // Pascal Round = banker's rounding, same as Python round()
  NH := Round(Img.Height * Ratio);
  PadW := (DstW - NW) / 2;
  PadH := (DstH - NH) / 2;
  R := ResizeRGB(Img, NW, NH);
  Top := Round(PadH - 0.1);
  Left := Round(PadW - 0.1);
  Result.Width := DstW;
  Result.Height := DstH;
  SetLength(Result.Pix, DstW * DstH * 3);
  FillChar(Result.Pix[0], Length(Result.Pix), Color);
  for Y := 0 to NH - 1 do
    Move(R.Pix[Y * NW * 3], Result.Pix[((Top + Y) * DstW + Left) * 3], NW * 3);
end;

{ ---------- TPlateConfig ---------- }

constructor TPlateConfig.Create;
begin
  inherited Create;
  Regions := TStringList.Create;
  PadChar := '_';
  PaddingColor := 114;
end;

destructor TPlateConfig.Destroy;
begin
  Regions.Free;
  inherited Destroy;
end;

function Unquote(const S: string): string;
begin
  Result := Trim(S);
  if (Length(Result) >= 2) and (Result[1] in ['''', '"']) and (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

{ Small parser for the flat YAML files that fast-plate-ocr ships. }
procedure TPlateConfig.LoadFromFile(const FileName: string);
var
  Lines: TStringList;
  I, P: Integer;
  Line, Key, Value, ListText: string;

  procedure AddListItems(const S: string);
  var
    Q: Char;
    J, Start: Integer;
  begin
    J := 1;
    while J <= Length(S) do
    begin
      if S[J] in ['''', '"'] then
      begin
        Q := S[J];
        Start := J + 1;
        repeat
          Inc(J);
        until (J > Length(S)) or (S[J] = Q);
        Regions.Add(Copy(S, Start, J - Start));
      end;
      Inc(J);
    end;
  end;

begin
  Regions.Clear;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    I := 0;
    while I < Lines.Count do
    begin
      Line := Lines[I];
      Inc(I);
      if (Trim(Line) = '') or (Trim(Line)[1] = '#') then
        Continue;
      P := Pos(':', Line);
      if P = 0 then
        Continue;
      Key := Trim(Copy(Line, 1, P - 1));
      Value := Trim(Copy(Line, P + 1, MaxInt));
      if Key = 'max_plate_slots' then MaxPlateSlots := StrToInt(Value)
      else if Key = 'alphabet' then Alphabet := Unquote(Value)
      else if Key = 'pad_char' then PadChar := Unquote(Value)[1]
      else if Key = 'img_height' then ImgHeight := StrToInt(Value)
      else if Key = 'img_width' then ImgWidth := StrToInt(Value)
      else if Key = 'keep_aspect_ratio' then KeepAspectRatio := LowerCase(Value) = 'true'
      else if Key = 'image_color_mode' then Grayscale := LowerCase(Unquote(Value)) = 'grayscale'
      else if Key = 'interpolation' then
      begin
        if LowerCase(Unquote(Value)) <> 'linear' then
          raise Exception.CreateFmt('Interpolation "%s" is not supported (only linear)', [Value]);
      end
      else if Key = 'padding_color' then
      begin
        Value := StringReplace(StringReplace(Value, '[', '', []), '(', '', []);
        P := Pos(',', Value);
        if P > 0 then Value := Copy(Value, 1, P - 1);
        PaddingColor := StrToIntDef(Trim(Value), 114);
      end
      else if Key = 'plate_regions' then
      begin
        if (Value <> '') and (Value[1] = '[') then
        begin
          // inline list, possibly over several lines: [ 'A', 'B',
          ListText := Value;
          while (Pos(']', ListText) = 0) and (I < Lines.Count) do
          begin
            ListText := ListText + ' ' + Lines[I];
            Inc(I);
          end;
          AddListItems(ListText);
        end
        else
          // block list:  - 'A'
          while (I < Lines.Count) and (Copy(TrimLeft(Lines[I]), 1, 1) = '-') do
          begin
            Regions.Add(Unquote(Copy(TrimLeft(Lines[I]), 2, MaxInt)));
            Inc(I);
          end;
      end;
    end;
  finally
    Lines.Free;
  end;
  if (MaxPlateSlots <= 0) or (Alphabet = '') or (ImgHeight <= 0) or (ImgWidth <= 0) then
    raise Exception.CreateFmt('Incomplete plate config: %s', [FileName]);
end;

{ ---------- TPlateDetector ---------- }

constructor TPlateDetector.Create(RT: TOrtRuntime; const ModelFile: string; Threads: Integer);
var
  S: TInt64Array;
begin
  inherited Create;
  ConfThreshold := 0.4;
  FSession := TOrtSession.Create(RT, ModelFile, Threads);
  S := FSession.InputShape;  // [1, 3, H, W]
  if (Length(S) <> 4) or (S[1] <> 3) or (S[2] <= 0) or (S[3] <= 0) then
    raise EOrtError.Create('Unexpected detector input shape');
  FSizeH := S[2];
  FSizeW := S[3];
end;

destructor TPlateDetector.Destroy;
begin
  FSession.Free;
  inherited Destroy;
end;

function TPlateDetector.Detect(const Img: TRGBImage): TPlateBoxes;
var
  LB: TRGBImage;
  Ratio, PadW, PadH: Double;
  Tensor: array of Single;
  Plane, I, N, Row: Integer;
  Outs: TOrtOutputs;
  D: TSingleArray;
  B: TPlateBox;
begin
  Result := nil;
  if (Img.Width <= 0) or (Img.Height <= 0) then
    Exit;
  LB := Letterbox(Img, FSizeW, FSizeH, 114, Ratio, PadW, PadH);
  // HWC RGB bytes -> CHW float 0..1
  Plane := FSizeW * FSizeH;
  SetLength(Tensor, Plane * 3);
  for I := 0 to Plane - 1 do
  begin
    Tensor[I] := LB.Pix[I * 3] / 255;
    Tensor[Plane + I] := LB.Pix[I * 3 + 1] / 255;
    Tensor[2 * Plane + I] := LB.Pix[I * 3 + 2] / 255;
  end;
  Outs := FSession.RunSingle(@Tensor[0], Length(Tensor) * SizeOf(Single),
    [1, 3, FSizeH, FSizeW], ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
  // output: N rows of [batch_id, x1, y1, x2, y2, class_id, score]
  D := Outs[0].Data;
  if (Length(Outs[0].Shape) <> 2) or (Outs[0].Shape[1] <> 7) then
    raise EOrtError.Create('Unexpected detector output shape');
  N := Outs[0].Shape[0];
  for I := 0 to N - 1 do
  begin
    Row := I * 7;
    if D[Row + 6] < ConfThreshold then
      Continue;
    B.X1 := Trunc((D[Row + 1] - PadW) / Ratio);
    B.Y1 := Trunc((D[Row + 2] - PadH) / Ratio);
    B.X2 := Trunc((D[Row + 3] - PadW) / Ratio);
    B.Y2 := Trunc((D[Row + 4] - PadH) / Ratio);
    B.Score := D[Row + 6];
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := B;
  end;
end;

{ ---------- TPlateOCR ---------- }

constructor TPlateOCR.Create(RT: TOrtRuntime; const ModelFile, ConfigFile: string; Threads: Integer);
begin
  inherited Create;
  FConfig := TPlateConfig.Create;
  FConfig.LoadFromFile(ConfigFile);
  FSession := TOrtSession.Create(RT, ModelFile, Threads);
end;

destructor TPlateOCR.Destroy;
begin
  FSession.Free;
  FConfig.Free;
  inherited Destroy;
end;

function TPlateOCR.Recognize(const Img: TRGBImage): TPlateText;
var
  R: TRGBImage;
  Ratio, PadW, PadH: Double;
  Tensor: TBytes;
  Channels, I, Slot, Best, K, Vocab, PlateIdx, RegionIdx: Integer;
  Outs: TOrtOutputs;
  BestP, Sum: Single;
  Txt: string;
begin
  Result := Default(TPlateText);
  if (Img.Width <= 0) or (Img.Height <= 0) then
    Exit;
  if FConfig.KeepAspectRatio then
    R := Letterbox(Img, FConfig.ImgWidth, FConfig.ImgHeight, FConfig.PaddingColor, Ratio, PadW, PadH)
  else
    R := ResizeRGB(Img, FConfig.ImgWidth, FConfig.ImgHeight);

  if FConfig.Grayscale then
  begin
    Channels := 1;
    SetLength(Tensor, R.Width * R.Height);
    for I := 0 to High(Tensor) do  // same weights as cv2 COLOR_RGB2GRAY
      Tensor[I] := EnsureRange(Round(0.299 * R.Pix[I * 3] + 0.587 * R.Pix[I * 3 + 1]
        + 0.114 * R.Pix[I * 3 + 2]), 0, 255);
  end
  else
  begin
    Channels := 3;
    Tensor := R.Pix;  // already HWC RGB uint8
  end;

  Outs := FSession.RunSingle(@Tensor[0], Length(Tensor),
    [1, FConfig.ImgHeight, FConfig.ImgWidth, Channels], ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8);

  // plate output: [1, slots, vocab]; v2 models also have 'region': [1, regions]
  PlateIdx := FindOutput(Outs, 'plate');
  if PlateIdx < 0 then
    PlateIdx := 0;
  Vocab := Length(FConfig.Alphabet);
  if (Length(Outs[PlateIdx].Shape) <> 3) or (Outs[PlateIdx].Shape[2] <> Vocab) then
    raise EOrtError.Create('OCR output does not match the alphabet in the plate config');

  SetLength(Result.CharProbs, Outs[PlateIdx].Shape[1]);
  Txt := '';
  Sum := 0;
  for Slot := 0 to High(Result.CharProbs) do
  begin
    Best := 0;
    BestP := Outs[PlateIdx].Data[Slot * Vocab];
    for K := 1 to Vocab - 1 do
      if Outs[PlateIdx].Data[Slot * Vocab + K] > BestP then
      begin
        BestP := Outs[PlateIdx].Data[Slot * Vocab + K];
        Best := K;
      end;
    Txt := Txt + FConfig.Alphabet[Best + 1];
    Result.CharProbs[Slot] := BestP;
    Sum := Sum + BestP;
  end;
  // remove trailing padding, like str.rstrip(pad_char)
  while (Txt <> '') and (Txt[Length(Txt)] = FConfig.PadChar) do
    Delete(Txt, Length(Txt), 1);
  Result.Text := Txt;
  if Length(Result.CharProbs) > 0 then
    Result.Confidence := Sum / Length(Result.CharProbs);

  RegionIdx := FindOutput(Outs, 'region');
  if (RegionIdx >= 0) and (FConfig.Regions.Count = Length(Outs[RegionIdx].Data)) then
  begin
    Best := 0;
    for K := 1 to High(Outs[RegionIdx].Data) do
      if Outs[RegionIdx].Data[K] > Outs[RegionIdx].Data[Best] then
        Best := K;
    Result.Region := FConfig.Regions[Best];
    Result.RegionProb := Outs[RegionIdx].Data[Best];
  end;
end;

{ ---------- TAlpr ---------- }

constructor TAlpr.Create(const OrtLib, DetectorModel, OcrModel, OcrConfig: string; Threads: Integer);
begin
  Create(TOrtRuntime.Create(OrtLib), DetectorModel, OcrModel, OcrConfig, Threads);
  FOwnsRT := True;
end;

constructor TAlpr.Create(RT: TOrtRuntime; const DetectorModel, OcrModel, OcrConfig: string;
  Threads: Integer);
begin
  inherited Create;
  FRT := RT;
  FDetector := TPlateDetector.Create(RT, DetectorModel, Threads);
  FOCR := TPlateOCR.Create(RT, OcrModel, OcrConfig, Threads);
end;

destructor TAlpr.Destroy;
begin
  FOCR.Free;
  FDetector.Free;
  if FOwnsRT then
    FRT.Free;
  inherited Destroy;
end;

function TAlpr.Predict(const Img: TRGBImage): TPlateResults;
var
  Boxes: TPlateBoxes;
  I: Integer;
  B: TPlateBox;
begin
  Boxes := FDetector.Detect(Img);
  SetLength(Result, Length(Boxes));
  for I := 0 to High(Boxes) do
  begin
    Result[I].Box := Boxes[I];
    B := Boxes[I];
    // clip like fast-alpr: img[max(y1,0):min(y2,h), max(x1,0):min(x2,w)]
    B.X1 := Max(B.X1, 0);
    B.Y1 := Max(B.Y1, 0);
    B.X2 := Min(B.X2, Img.Width);
    B.Y2 := Min(B.Y2, Img.Height);
    if (B.X2 > B.X1) and (B.Y2 > B.Y1) then
      Result[I].Plate := FOCR.Recognize(CropRGB(Img, B.X1, B.Y1, B.X2, B.Y2))
    else
      Result[I].Plate := Default(TPlateText);
  end;
end;

function TAlpr.Predict(Img: TFPCustomImage): TPlateResults;
begin
  Result := Predict(RGBImageFromFP(Img));
end;

function TAlpr.PredictFile(const FileName: string): TPlateResults;
begin
  Result := Predict(LoadRGBImage(FileName));
end;

end.
