{ Video frame sources for ALPR.

  TFrameSource       - common interface: ReadFrame gives the next frame to analyse
  TFFmpegSource      - any file or stream through an external ffmpeg(.exe):
                       RTSP from IP cameras, USB cameras, every codec. Cross-platform.
  TMFSource (unit MFVideo) - Windows Media Foundation, nothing to install. }
unit FrameSource;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, FastAlpr;

type
  TFrameSource = class
  public
    { Img: next frame; Time: seconds from the start. False = end of video / stream closed. }
    function ReadFrame(out Img: TRGBImage; out Time: Double): Boolean; virtual; abstract;
  end;

  { Runs:  ffmpeg -i <source> -vf fps=<Fps>,scale=<W>x<H> -f rawvideo -pix_fmt rgb24 -
    and reads the frames from its standard output.
    Frames are scaled to fit Width x Height keeping the aspect ratio (black bars). }
  TFFmpegSource = class(TFrameSource)
  private
    FProc: TProcess;
    FW, FH: Integer;
    FFps: Double;
    FIndex: Int64;
    FLastErr: string;
    procedure DrainStderr;
  public
    { FFmpegExe: 'ffmpeg' if it is in PATH, or a full path to ffmpeg.exe.
      Source: file name or rtsp://user:pass@ip/...
      Fps: frames per second to analyse (5 is plenty for cars). }
    constructor Create(const FFmpegExe, Source: string; Fps: Double = 5;
      Width: Integer = 1280; Height: Integer = 720);
    { Full control over the input part, e.g. a USB camera on Windows:
        ['-f', 'dshow', '-i', 'video=USB Camera'] }
    constructor CreateArgs(const FFmpegExe: string; const InputArgs: array of string;
      Fps: Double = 5; Width: Integer = 1280; Height: Integer = 720);
    destructor Destroy; override;
    function ReadFrame(out Img: TRGBImage; out Time: Double): Boolean; override;
    property LastError: string read FLastErr;
  end;

implementation

constructor TFFmpegSource.Create(const FFmpegExe, Source: string; Fps: Double;
  Width, Height: Integer);
begin
  if LowerCase(Copy(Source, 1, 7)) = 'rtsp://' then
    // TCP: UDP loses packets -> broken frames; nobuffer keeps the delay low
    CreateArgs(FFmpegExe, ['-rtsp_transport', 'tcp', '-fflags', 'nobuffer', '-i', Source],
      Fps, Width, Height)
  else
    CreateArgs(FFmpegExe, ['-i', Source], Fps, Width, Height);
end;

constructor TFFmpegSource.CreateArgs(const FFmpegExe: string; const InputArgs: array of string;
  Fps: Double; Width, Height: Integer);
var
  FS: TFormatSettings;
  I: Integer;
begin
  inherited Create;
  FW := Width;
  FH := Height;
  FFps := Fps;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FProc := TProcess.Create(nil);
  FProc.Executable := FFmpegExe;
  with FProc.Parameters do
  begin
    Add('-nostdin');
    Add('-hide_banner');
    Add('-loglevel'); Add('error');
    for I := 0 to High(InputArgs) do
      Add(InputArgs[I]);
    Add('-an');
    Add('-vf');
    Add(Format('fps=%s,scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2',
      [FormatFloat('0.###', Fps, FS), FW, FH, FW, FH]));
    Add('-f'); Add('rawvideo');
    Add('-pix_fmt'); Add('rgb24');
    Add('-');
  end;
  FProc.Options := [poUsePipes, poNoConsole];
  FProc.Execute;
end;

destructor TFFmpegSource.Destroy;
begin
  if FProc.Running then
    FProc.Terminate(0);
  FProc.Free;
  inherited Destroy;
end;

procedure TFFmpegSource.DrainStderr;
var
  Buf: array[0..1023] of Char;
  N: Integer;
begin
  // ffmpeg blocks if nobody empties its stderr pipe
  while FProc.Stderr.NumBytesAvailable > 0 do
  begin
    N := FProc.Stderr.Read(Buf, SizeOf(Buf));
    if N <= 0 then Break;
    SetString(FLastErr, PChar(@Buf[0]), N);
  end;
end;

function TFFmpegSource.ReadFrame(out Img: TRGBImage; out Time: Double): Boolean;
var
  Need, Got, N: Integer;
begin
  Img.Width := FW;
  Img.Height := FH;
  SetLength(Img.Pix, FW * FH * 3);
  Need := Length(Img.Pix);
  Got := 0;
  while Got < Need do
  begin
    DrainStderr;
    N := FProc.Output.Read(Img.Pix[Got], Need - Got);  // blocks until data or end
    if N <= 0 then
    begin
      DrainStderr;
      Exit(False);
    end;
    Inc(Got, N);
  end;
  Time := FIndex / FFps;
  Inc(FIndex);
  Result := True;
end;

end.
