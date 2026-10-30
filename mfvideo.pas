{ Video frames through Windows Media Foundation (IMFSourceReader) - nothing to install.
  Built on the declarations from vidplay's mfdecl.pas.

  Decodes every frame (H.264/HEVC need that) but converts and returns only one
  frame per Interval seconds, which is all ALPR needs. Windows only. }
unit MFVideo;

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, mfdecl, OnnxRT, FastAlpr, FrameSource;

type
  TMFSource = class(TFrameSource)
  private
    FReader: IMFSourceReader;
    FW, FH, FStride: Integer;     // visible size and row stride of the RGB32 frames
    FBufH: Integer;               // decoded height (may be 1088 for 1080p)
    FInterval: Int64;             // in 100 ns
    FNext: Int64;
    FStarted: Boolean;
    FNV12: Boolean;               // decoder output used directly, converted here
    procedure ReadFormat;
  public
    { URL: file name (or a URL Media Foundation can open).
      Interval: seconds between analysed frames (0.2 = 5 per second; 0 = every frame). }
    constructor Create(const URL: string; Interval: Double = 0.2);
    destructor Destroy; override;
    function ReadFrame(out Img: TRGBImage; out Time: Double): Boolean; override;
    { Jump to a position in seconds (files only). }
    procedure Seek(Seconds: Double);
    property Width: Integer read FW;
    property Height: Integer read FH;
    property UsingNV12: Boolean read FNV12;
  end;

implementation

const
  // verified against mingw-w64 mfapi.h / mfreadwrite.h
  MF_MT_MINIMUM_DISPLAY_APERTURE: TGUID = '{D7388766-18FE-48C6-A177-EE894867C8C4}';
  MF_LOW_LATENCY: TGUID = '{9C27891A-ED7A-40E1-88E8-B22727A024EE}';
  MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED = $20;
  MFVideoFormat_NV12: TGUID = '{3231564E-0000-0010-8000-00AA00389B71}';
  COINIT_MULTITHREADED = 0;

type
  TMFVideoArea = record
    OffsetXFract: Word; OffsetXValue: SmallInt;
    OffsetYFract: Word; OffsetYValue: SmallInt;
    cx, cy: LongInt;
  end;

procedure Check(hr: HResult; const What: string);
begin
  if Failed(hr) then
    raise Exception.CreateFmt('%s failed (0x%.8x)', [What, DWORD(hr)]);
end;

constructor TMFSource.Create(const URL: string; Interval: Double);
var
  Attr: IMFAttributes;
  mt: IMFMediaType;
  W: UnicodeString;
begin
  inherited Create;
  FInterval := Round(Interval * 10000000);
  MaskFPUExceptions;  // Media Foundation / D3D do not tolerate unmasked FPU exceptions
  ole_CoInitializeEx(nil, COINIT_MULTITHREADED);  // harmless if COM is already initialised
  Check(MFStartup(MF_VERSION, MFSTARTUP_FULL), 'MFStartup');
  FStarted := True;

  Check(MFCreateAttributes(Attr, 2), 'MFCreateAttributes');
  Attr.SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, 1);  // YUV -> RGB32 inside MF
  if Pos('://', URL) > 0 then
    Attr.SetUINT32(MF_LOW_LATENCY, 1);                        // network stream: no extra delay
  W := UTF8Decode(URL);
  Check(MFCreateSourceReaderFromURL(PWideChar(W), Attr, FReader), 'Opening ' + URL);
  FReader.SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, False);
  FReader.SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, True);

  Check(MFCreateMediaType(mt), 'MFCreateMediaType');
  mt.SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  mt.SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  if Failed(FReader.SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nil, mt)) then
  begin
    // no colour converter available: take NV12 straight from the decoder
    mt.SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    Check(FReader.SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nil, mt),
      'The decoder gives neither RGB32 nor NV12 for this video');
    FNV12 := True;
  end;
  ReadFormat;
end;

destructor TMFSource.Destroy;
begin
  FReader := nil;
  if FStarted then
    MFShutdown;
  inherited Destroy;
end;

procedure TMFSource.ReadFormat;
var
  cur: IMFMediaType;
  size64: UInt64;
  st32: UINT32;
  area: TMFVideoArea;
  got: UINT32;
begin
  Check(FReader.GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, cur), 'GetCurrentMediaType');
  Check(cur.GetUINT64(MF_MT_FRAME_SIZE, size64), 'Frame size');
  FW := Integer(size64 shr 32);
  FBufH := Integer(size64 and $FFFFFFFF);
  FH := FBufH;
  // decoders align the height (1088 instead of 1080); the visible part is the aperture
  if Succeeded(cur.GetBlob(MF_MT_MINIMUM_DISPLAY_APERTURE, @area, SizeOf(area), @got)) and
     (got = SizeOf(area)) and (area.cx > 0) and (area.cy > 0) then
  begin
    if area.cx < FW then FW := area.cx;
    if area.cy < FH then FH := area.cy;
  end;
  if Succeeded(cur.GetUINT32(MF_MT_DEFAULT_STRIDE, st32)) then
    FStride := Int32(st32)
  else if FNV12 then
    FStride := 0                       // worked out from the buffer size
  else
    FStride := Integer(size64 shr 32) * 4;
end;

{ NV12 (Y plane + interleaved UV at half resolution) -> RGB, BT.601 limited range }
function NV12ToRGB(Y: PByte; Stride, BufH, W, H: Integer): TRGBImage;
var
  X, Row, C, D, E, R, G, B, I: Integer;
  PY, PUV: PByte;
begin
  Result.Width := W;
  Result.Height := H;
  SetLength(Result.Pix, W * H * 3);
  I := 0;
  for Row := 0 to H - 1 do
  begin
    PY := Y + PtrInt(Row) * Stride;
    PUV := Y + PtrInt(BufH) * Stride + PtrInt(Row shr 1) * Stride;
    for X := 0 to W - 1 do
    begin
      C := (PY[X] - 16) * 298;
      D := PUV[X and not 1] - 128;
      E := PUV[(X and not 1) + 1] - 128;
      R := (C + 409 * E + 128) shr 8;
      G := (C - 100 * D - 208 * E + 128) shr 8;
      B := (C + 516 * D + 128) shr 8;
      if R < 0 then R := 0 else if R > 255 then R := 255;
      if G < 0 then G := 0 else if G > 255 then G := 255;
      if B < 0 then B := 0 else if B > 255 then B := 255;
      Result.Pix[I] := R;
      Result.Pix[I + 1] := G;
      Result.Pix[I + 2] := B;
      Inc(I, 3);
    end;
  end;
end;

procedure TMFSource.Seek(Seconds: Double);
var
  pv: TPropVarI8;
begin
  FillChar(pv, SizeOf(pv), 0);
  pv.vt := VT_I8;
  pv.hVal := Round(Seconds * 10000000);
  FReader.SetCurrentPosition(GUID_NULL, pv);  // lands on the key frame before
  FNext := pv.hVal;
end;

function TMFSource.ReadFrame(out Img: TRGBImage; out Time: Double): Boolean;
var
  Sample: IMFSample;
  Buf: IMFMediaBuffer;
  idx, flags, curLen: DWORD;
  ts: Int64;
  p, scan0: PByte;
begin
  Result := False;
  Img := Default(TRGBImage);
  Time := 0;
  repeat
    Sample := nil;
    if Failed(FReader.ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, @idx, @flags, @ts, Sample)) then
      Exit;
    if flags and (MF_SOURCE_READERF_ERROR or MF_SOURCE_READERF_ENDOFSTREAM) <> 0 then
      Exit;
    if flags and MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED <> 0 then
      ReadFormat;
    if Sample = nil then
      Continue;                       // stream tick / gap
    if ts < FNext then
      Continue;                       // decoded, but not one we analyse
    FNext := ts + FInterval;

    Check(Sample.ConvertToContiguousBuffer(Buf), 'ConvertToContiguousBuffer');
    Check(Buf.Lock(p, nil, @curLen), 'Lock');
    try
      if FNV12 then
      begin
        FStride := Abs(FStride);
        if FStride = 0 then
          FStride := Integer(curLen) * 2 div (3 * FBufH);
        if (FStride < FW) or (curLen < DWORD(FStride * FBufH * 3 div 2)) then
          raise Exception.Create('Unexpected NV12 frame layout');
        Img := NV12ToRGB(p, FStride, FBufH, FW, FH);
        Time := ts / 10000000;
        Exit(True);
      end;
      if curLen < DWORD(Abs(FStride) * FBufH) then
        raise Exception.Create('Video frame is smaller than expected');
      if FStride < 0 then
        scan0 := p + PtrInt(FBufH - 1) * Abs(FStride)   // bottom-up
      else
        scan0 := p;
      Img := RGBImageFromRaw(scan0, FW, FH, FStride, 4, True);  // RGB32 = B,G,R,X
    finally
      Buf.Unlock;
    end;
    Time := ts / 10000000;
    Exit(True);
  until False;
end;

end.
