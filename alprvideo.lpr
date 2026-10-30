{ License plates from a video file or a camera stream.

  alprvideo <video or rtsp://...> [--ffmpeg <ffmpeg.exe>] [--fps 5] [--ort <onnxruntime.dll>]
            [--models <folder>] [--bg] [--verbose] [--save]

  Windows: without --ffmpeg the video is decoded by Media Foundation (nothing to install).
  Prints one line per car:   00:12.4  CM6026BA   votes 9/11  conf 1.00 }
program alprvideo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, DateUtils, Math, FPImage, FPWritePNG, FastAlpr, PlateTracker, FrameSource
  {$IFDEF WINDOWS}, MFVideo{$ENDIF};

type
  TPrinter = class
    procedure OnPlate(const E: TPlateEvent);
  end;

function FmtTime(T: Double): string;
begin
  Result := Format('%.2d:%.2d.%d', [Trunc(T) div 60, Trunc(T) mod 60, Trunc(Frac(T) * 10)]);
end;

procedure TPrinter.OnPlate(const E: TPlateEvent);
const
  Mark: array[Boolean] of string = ('  (few readings)', '');
begin
  WriteLn(Format('%s  %-10s votes %d/%d  conf %.2f%s',
    [FmtTime(E.FirstTime), E.Text, E.Votes, E.Frames, E.BestConf, Mark[E.Confirmed]]));
end;

{ Writes the frame exactly as the models get it (to check orientation, colours, sharpness). }
procedure SavePNG(const Img: TRGBImage; const FileName: string);
var
  P: TFPMemoryImage;
  X, Y, I: Integer;
  C: TFPColor;
begin
  P := TFPMemoryImage.Create(Img.Width, Img.Height);
  try
    I := 0;
    for Y := 0 to Img.Height - 1 do
      for X := 0 to Img.Width - 1 do
      begin
        C.Red := Img.Pix[I] * 257;
        C.Green := Img.Pix[I + 1] * 257;
        C.Blue := Img.Pix[I + 2] * 257;
        C.Alpha := alphaOpaque;
        P.Colors[X, Y] := C;
        Inc(I, 3);
      end;
    P.SaveToFile(FileName);
  finally
    P.Free;
  end;
end;

function Opt(const Name, Default: string): string;
var
  I: Integer;
begin
  for I := 2 to ParamCount - 1 do
    if ParamStr(I) = Name then
      Exit(ParamStr(I + 1));
  Result := Default;
end;

function HasOpt(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 2 to ParamCount do
    if ParamStr(I) = Name then
      Exit(True);
  Result := False;
end;

var
  Models, FFmpeg, OrtLib: string;
  Fps: Double;
  Alpr: TAlpr;
  Src: TFrameSource;
  Tracker: TPlateTracker;
  Printer: TPrinter;
  Img: TRGBImage;
  T: Double;
  Frames, LastW, LastH: Integer;
  T0: TDateTime;
  FS: TFormatSettings;
  Verbose, Save: Boolean;
  Saved: Integer;
  Res: TPlateResults;
  Line: string;
  I: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: alprvideo <video or rtsp://...> [--ffmpeg ffmpeg.exe] [--fps 5] [--ort onnxruntime.dll] [--models folder] [--bg] [--verbose] [--save]');
    Halt(1);
  end;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Models := IncludeTrailingPathDelimiter(Opt('--models', ExtractFilePath(ParamStr(0))));
  FFmpeg := Opt('--ffmpeg', {$IFDEF WINDOWS}''{$ELSE}'ffmpeg'{$ENDIF});
  OrtLib := Opt('--ort', {$IFDEF WINDOWS}ExtractFilePath(ParamStr(0)) + 'onnxruntime.dll'{$ELSE}''{$ENDIF});
  Fps := StrToFloat(Opt('--fps', '5'), FS);
  Verbose := HasOpt('--verbose');
  Save := HasOpt('--save');
  Saved := 0;

  Printer := TPrinter.Create;
  Tracker := TPlateTracker.Create;
  Tracker.OnPlate := @Printer.OnPlate;
  if HasOpt('--bg') then
    Tracker.Filter := @IsBulgarianPlate;
  Src := nil;
  Alpr := nil;
  try
    try
      Alpr := TAlpr.Create(OrtLib,
        Models + SetDirSeparators('..\model\yolo-v9-t-384-license-plates-end2end.onnx'),
        Models + SetDirSeparators('..\model\cct_xs_v1_global.onnx'),
        Models + SetDirSeparators('..\model\cct_xs_v1_global_plate_config.yaml'));
      {$IFDEF WINDOWS}
      if FFmpeg = '' then
        Src := TMFSource.Create(ParamStr(1), 1 / Fps)
      else
      {$ENDIF}
        Src := TFFmpegSource.Create(FFmpeg, ParamStr(1), Fps);

      Frames := 0;
      LastW := 0;
      LastH := 0;
      T0 := Now;
      while Src.ReadFrame(Img, T) do
      begin
        Res := Alpr.Predict(Img);
        if Verbose then
        begin
          // one line per analysed frame: time, frame size, every plate found (even uncertain)
          Line := Format('%s  %dx%d', [FmtTime(T), Img.Width, Img.Height]);
          if Length(Res) = 0 then
            Line := Line + '  -';
          for I := 0 to High(Res) do
            Line := Line + Format('  [%s %.0f%% %dx%d]', [Res[I].Plate.Text,
              Res[I].Plate.Confidence * 100, Res[I].Box.X2 - Res[I].Box.X1,
              Res[I].Box.Y2 - Res[I].Box.Y1]);
          WriteLn(Line);
        end;
        if Save and (Length(Res) > 0) and (Saved < 10) then
        begin
          // first 10 frames with a plate: debug_1.png .. debug_10.png next to the exe's current folder
          Inc(Saved);
          SavePNG(Img, Format('debug_%d.png', [Saved]));
          WriteLn('  saved debug_', Saved, '.png');
        end;
        Tracker.Feed(Res, T, Img.Width, Img.Height);
        LastW := Img.Width;
        LastH := Img.Height;
        Inc(Frames);
      end;
      Tracker.Flush;
      if (Src is TFFmpegSource) and (TFFmpegSource(Src).LastError <> '') then
        WriteLn('ffmpeg: ', Trim(TFFmpegSource(Src).LastError));
      WriteLn(Format('%d frames analysed (%dx%d), %.0f ms per frame', [Frames, LastW, LastH,
        MilliSecondsBetween(Now, T0) / Max(Frames, 1)]));
    except
      on E: Exception do
      begin
        WriteLn('Error: ', E.Message);
        ExitCode := 2;
      end;
    end;
  finally
    Src.Free;
    Alpr.Free;
    Tracker.Free;
    Printer.Free;
  end;
end.
