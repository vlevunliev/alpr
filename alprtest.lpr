{ Console test for the FastAlpr unit.

  Usage:
    alprtest <image> [onnxruntime library] [models folder] [ocr model folder name]

  Defaults expect the folder layout you get in C:\alpr:
    open-image-models\yolo-v9-t-384-license-plate-end2end\yolo-v9-t-384-license-plates-end2end.onnx
    fast-plate-ocr\cct-xs-v1-global-model\cct_xs_v1_global.onnx (+ _plate_config.yaml) }
program alprtest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, DateUtils, FastAlpr;

var
  OrtLib, Models, OcrName, OcrDir, OcrBase, Det: string;
  Alpr: TAlpr;
  Img: TRGBImage;
  Res: TPlateResults;
  I, Run: Integer;
  T0: TDateTime;
  Ms: Int64;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: alprtest <image> [onnxruntime library] [models folder] [ocr model]');
    Halt(1);
  end;
  OrtLib := '';
  if ParamCount >= 2 then OrtLib := ParamStr(2);
  Models := ExtractFilePath(ParamStr(0));
  if ParamCount >= 3 then Models := IncludeTrailingPathDelimiter(ParamStr(3));
  OcrName := 'cct-xs-v1-global-model';
  if ParamCount >= 4 then OcrName := ParamStr(4);

  Det := Models + 'open-image-models' + PathDelim + 'yolo-v9-t-384-license-plate-end2end'
    + PathDelim + 'yolo-v9-t-384-license-plates-end2end.onnx';
  OcrDir := Models + 'fast-plate-ocr' + PathDelim + OcrName + PathDelim;
  // cct-xs-v1-global-model -> cct_xs_v1_global
  OcrBase := StringReplace(StringReplace(OcrName, '-model', '', []), '-', '_', [rfReplaceAll]);

  try
    Alpr := TAlpr.Create(OrtLib, Det, OcrDir + OcrBase + '.onnx',
      OcrDir + OcrBase + '_plate_config.yaml');
    try
      WriteLn('ONNX Runtime ', Alpr.Runtime.Version);
      Img := LoadRGBImage(ParamStr(1));
      WriteLn('Image ', Img.Width, 'x', Img.Height);
      Res := Alpr.Predict(Img);
      for I := 0 to High(Res) do
        with Res[I] do
          WriteLn(Format('box %d,%d-%d,%d det %.4f  %s  conf %.5f  %s %.4f',
            [Box.X1, Box.Y1, Box.X2, Box.Y2, Box.Score, Plate.Text, Plate.Confidence,
             Plate.Region, Plate.RegionProb]));
      if Length(Res) = 0 then
        WriteLn('No plates found');

      // timing
      T0 := Now;
      for Run := 1 to 10 do
        Alpr.Predict(Img);
      Ms := MilliSecondsBetween(Now, T0);
      WriteLn(Format('Average %.1f ms per image', [Ms / 10]));
    finally
      Alpr.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn('Error: ', E.Message);
      Halt(2);
    end;
  end;
end.
