unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  IntfGraphics, GraphType, OnnxRT, FastAlpr, PlateTracker, FrameSource
  {$IFDEF WINDOWS}, MFVideo{$ENDIF};

type
  TFormMain = class;

  { Reads the video, recognises plates and hands every analysed frame to the form. }
  TVideoThread = class(TThread)
  private
    FForm: TFormMain;
    FFileName: string;
    FTracker: TPlateTracker;
    FFrame: TLazIntfImage;      // frame to show, built in the thread
    FResults: TPlateResults;
    FTime: Double;
    FEvents: TStringList;       // plates reported since the last Synchronize
    FError: string;
    procedure OnPlate(const E: TPlateEvent);
    procedure ShowFrame;
    procedure DoFinished;
  protected
    procedure Execute; override;
  public
    constructor Create(AForm: TFormMain; const AFileName: string);
    destructor Destroy; override;
  end;

  TFormMain = class(TForm)
    PanelTop: TPanel;
    BtnOpen: TButton;
    BtnVideo: TButton;
    BtnUrl: TButton;
    LabelStatus: TLabel;
    MemoResult: TMemo;
    ImageView: TImage;
    OpenDialog1: TOpenDialog;
    OpenDialogVideo: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnVideoClick(Sender: TObject);
    procedure BtnUrlClick(Sender: TObject);
  private
    FAlpr: TAlpr;
    FThread: TVideoThread;
    procedure ProcessFile(const FileName: string);
    procedure DrawResults(Bmp: TBitmap; const Res: TPlateResults);
    procedure StopVideo;
    function IsRunning: Boolean;
    procedure StartVideo(const Source, Title: string; RunButton: TButton);
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

const
  // Paths relative to the .exe folder. Put the program in C:\alpr next to the model folders.
  DETECTOR_MODEL = '..\model\yolo-v9-t-384-license-plates-end2end.onnx';
  OCR_MODEL      = '..\model\cct_xs_v1_global.onnx';
  OCR_CONFIG     = '..\model\cct_xs_v1_global_plate_config.yaml';
  {$IFDEF WINDOWS}
  ORT_LIBRARY    = 'onnxruntime.dll';
  {$ELSE}
  ORT_LIBRARY    = 'libonnxruntime.so';
  {$ENDIF}
  VIDEO_FPS      = 5;   // analysed frames per second of video

function AppPath(const Rel: string): string;
begin
  Result := ExtractFilePath(Application.ExeName) + SetDirSeparators(Rel);
end;

function FmtTime(T: Double): string;
begin
  Result := Format('%.2d:%.2d.%d', [Trunc(T) div 60, Trunc(T) mod 60, Trunc(Frac(T) * 10)]);
end;

{ RGB frame -> TLazIntfImage (pure memory, safe in a thread) }
function RGBToIntfImage(const Img: TRGBImage): TLazIntfImage;
var
  Desc: TRawImageDescription;
  Y, X: Integer;
  Src, Dst: PByte;
begin
  Desc.Init_BPP32_B8G8R8_BIO_TTB(Img.Width, Img.Height);  // 32 bit: native on Windows and GTK
  Result := TLazIntfImage.Create(0, 0);
  Result.DataDescription := Desc;
  for Y := 0 to Img.Height - 1 do
  begin
    Src := @Img.Pix[Y * Img.Width * 3];
    Dst := Result.GetDataLineStart(Y);
    for X := 0 to Img.Width - 1 do
    begin
      Dst[0] := Src[2];
      Dst[1] := Src[1];
      Dst[2] := Src[0];
      Dst[3] := 255;
      Inc(Src, 3);
      Inc(Dst, 4);
    end;
  end;
end;

{ TVideoThread }

constructor TVideoThread.Create(AForm: TFormMain; const AFileName: string);
begin
  FForm := AForm;
  FFileName := AFileName;
  FEvents := TStringList.Create;
  FTracker := TPlateTracker.Create;
  FTracker.OnPlate := @OnPlate;
  inherited Create(False);
end;

destructor TVideoThread.Destroy;
begin
  FTracker.Free;
  FEvents.Free;
  FFrame.Free;
  inherited Destroy;
end;

procedure TVideoThread.OnPlate(const E: TPlateEvent);
var
  S: string;
begin
  S := Format('  %s  %-10s  %d/%d  %.0f%%', [FmtTime(E.FirstTime), E.Text, E.Votes, E.Frames,
    E.BestConf * 100]);
  if not E.Confirmed then
    S := S + '  (few readings)';
  FEvents.Add(S);
end;

procedure TVideoThread.Execute;
var
  Src: TFrameSource;
  Img: TRGBImage;
begin
  MaskFPUExceptions;  // per thread
  Src := nil;
  try
    try
      {$IFDEF WINDOWS}
      Src := TMFSource.Create(FFileName, 1 / VIDEO_FPS);
      {$ELSE}
      Src := TFFmpegSource.Create('ffmpeg', FFileName, VIDEO_FPS);
      {$ENDIF}
      while not Terminated and Src.ReadFrame(Img, FTime) do
      begin
        if Terminated then
          Break;
        FResults := FForm.FAlpr.Predict(Img);
        FTracker.Feed(FResults, FTime, Img.Width, Img.Height);
        FreeAndNil(FFrame);
        FFrame := RGBToIntfImage(Img);
        Synchronize(@ShowFrame);
      end;
      FResults := nil;
      FTracker.Flush;
    except
      on E: Exception do
        FError := E.Message;
    end;
  finally
    Src.Free;
  end;
  Synchronize(@DoFinished);
end;

procedure TVideoThread.ShowFrame;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.LoadFromIntfImage(FFrame);
    FForm.DrawResults(Bmp, FResults);
    FForm.ImageView.Picture.Assign(Bmp);
  finally
    Bmp.Free;
  end;
  FForm.LabelStatus.Caption := FmtTime(FTime);
  if FEvents.Count > 0 then
  begin
    FForm.MemoResult.Lines.AddStrings(FEvents);
    FEvents.Clear;
  end;
end;

procedure TVideoThread.DoFinished;
begin
  if FEvents.Count > 0 then
    FForm.MemoResult.Lines.AddStrings(FEvents);
  FEvents.Clear;
  if FError <> '' then
    FForm.MemoResult.Lines.Add('Video error: ' + FError)
  else if Terminated then
    FForm.MemoResult.Lines.Add('Stopped at ' + FmtTime(FTime))
  else
    FForm.MemoResult.Lines.Add('End of video');
  FForm.BtnVideo.Caption := 'Open video...';
  FForm.BtnUrl.Caption := 'Open URL...';
  FForm.BtnOpen.Enabled := True;
  FForm.BtnVideo.Enabled := True;
  FForm.BtnUrl.Enabled := True;
end;

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  try
    // Full path to the DLL so Windows does not pick up its own old System32\onnxruntime.dll
    FAlpr := TAlpr.Create(AppPath(ORT_LIBRARY), AppPath(DETECTOR_MODEL),
      AppPath(OCR_MODEL), AppPath(OCR_CONFIG));
    MemoResult.Lines.Add('ONNX Runtime ' + FAlpr.Runtime.Version + ' - ready');
  except
    on E: Exception do
    begin
      MemoResult.Lines.Add('Init error: ' + E.Message);
      BtnOpen.Enabled := False;
      BtnVideo.Enabled := False;
      BtnUrl.Enabled := False;
    end;
  end;
end;

procedure TFormMain.StopVideo;
var
  T0: QWord;
begin
  if FThread = nil then
    Exit;
  FThread.Terminate;
  // Synchronize calls from the thread need the main loop while we wait
  T0 := GetTickCount64;
  while not FThread.Finished and (GetTickCount64 - T0 < 5000) do
  begin
    CheckSynchronize(10);
    Application.ProcessMessages;
  end;
  if FThread.Finished then
  begin
    FThread.WaitFor;
    FThread.Free;
  end
  else
  begin
    // a dead camera stream can block the reader; leave the thread behind instead of hanging
    MemoResult.Lines.Add('The stream does not respond - stopped waiting');
    BtnVideo.Caption := 'Open video...';
    BtnUrl.Caption := 'Open URL...';
    BtnOpen.Enabled := True;
    BtnVideo.Enabled := True;
    BtnUrl.Enabled := True;
  end;
  FThread := nil;
end;

function TFormMain.IsRunning: Boolean;
begin
  Result := (FThread <> nil) and not FThread.Finished;
end;

procedure TFormMain.StartVideo(const Source, Title: string; RunButton: TButton);
begin
  StopVideo;               // free the previous, finished one
  MemoResult.Lines.Add(Title + ':');
  BtnOpen.Enabled := False;
  BtnVideo.Enabled := False;
  BtnUrl.Enabled := False;
  RunButton.Enabled := True;
  RunButton.Caption := 'Stop';   // the same button stops it
  FThread := TVideoThread.Create(Self, Source);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  StopVideo;
  FAlpr.Free;
end;

procedure TFormMain.BtnOpenClick(Sender: TObject);
begin
  if OpenDialog1.Execute then
    ProcessFile(OpenDialog1.FileName);
end;

procedure TFormMain.BtnVideoClick(Sender: TObject);
begin
  if IsRunning then
  begin
    StopVideo;
    Exit;
  end;
  if OpenDialogVideo.Execute then
    StartVideo(OpenDialogVideo.FileName, ExtractFileName(OpenDialogVideo.FileName), BtnVideo);
end;

procedure TFormMain.BtnUrlClick(Sender: TObject);
var
  URL, UrlFile: string;
  SL: TStringList;
begin
  if IsRunning then
  begin
    StopVideo;
    Exit;
  end;
  // remember the last address next to the exe
  UrlFile := ChangeFileExt(Application.ExeName, '.url');
  URL := 'rtsp://192.168.43.1:8080/h264_ulaw.sdp';
  SL := TStringList.Create;
  try
    if FileExists(UrlFile) then
    begin
      SL.LoadFromFile(UrlFile);
      if SL.Count > 0 then
        URL := Trim(SL[0]);
    end;
    if not InputQuery('Camera stream', 'Address (rtsp://...):', URL) then
      Exit;
    URL := Trim(URL);
    if URL = '' then
      Exit;
    SL.Text := URL;
    try
      SL.SaveToFile(UrlFile);
    except
      // read-only folder: just do not remember it
    end;
  finally
    SL.Free;
  end;
  StartVideo(URL, URL, BtnUrl);
end;

procedure TFormMain.DrawResults(Bmp: TBitmap; const Res: TPlateResults);
var
  I: Integer;
  Line: string;
begin
  Bmp.Canvas.Pen.Width := 2;
  Bmp.Canvas.Font.Size := 14;
  Bmp.Canvas.Font.Style := [fsBold];
  for I := 0 to High(Res) do
    with Res[I] do
    begin
      Bmp.Canvas.Brush.Style := bsClear;
      // uncertain readings: yellow box without text (the tracker ignores them too)
      if Plate.Confidence < 0.8 then
        Bmp.Canvas.Pen.Color := clYellow
      else
        Bmp.Canvas.Pen.Color := clLime;
      Bmp.Canvas.Rectangle(Box.X1, Box.Y1, Box.X2, Box.Y2);
      if (Plate.Text = '') or (Plate.Confidence < 0.8) then
        Continue;
      Line := Format('%s %.0f%%', [Plate.Text, Plate.Confidence * 100]);
      Bmp.Canvas.Brush.Style := bsSolid;
      Bmp.Canvas.Brush.Color := clBlack;
      Bmp.Canvas.Font.Color := clWhite;
      Bmp.Canvas.TextOut(Box.X1, Box.Y1 - Bmp.Canvas.TextHeight(Line) - 2, Line);
    end;
  Bmp.Canvas.Brush.Style := bsClear;
end;

procedure TFormMain.ProcessFile(const FileName: string);
var
  Pic: TPicture;
  Bmp: TBitmap;
  Intf: TLazIntfImage;
  Res: TPlateResults;
  I: Integer;
  T0: QWord;
  Line: string;
begin
  Pic := TPicture.Create;
  Bmp := TBitmap.Create;
  try
    Pic.LoadFromFile(FileName);
    Bmp.SetSize(Pic.Width, Pic.Height);
    Bmp.Canvas.Draw(0, 0, Pic.Graphic);

    // TLazIntfImage is a TFPCustomImage, so FastAlpr can read it directly
    Intf := Bmp.CreateIntfImage;
    try
      T0 := GetTickCount64;
      Res := FAlpr.Predict(Intf);
      T0 := GetTickCount64 - T0;
    finally
      Intf.Free;
    end;

    MemoResult.Lines.Add(Format('%s - %d plate(s), %d ms',
      [ExtractFileName(FileName), Length(Res), T0]));
    DrawResults(Bmp, Res);
    for I := 0 to High(Res) do
      with Res[I] do
      begin
        Line := Format('%s %.0f%%', [Plate.Text, Plate.Confidence * 100]);
        if Plate.Region <> '' then
          Line := Line + '  ' + Plate.Region;
        MemoResult.Lines.Add('  ' + Line);
      end;
    ImageView.Picture.Assign(Bmp);
  finally
    Bmp.Free;
    Pic.Free;
  end;
end;

end.
