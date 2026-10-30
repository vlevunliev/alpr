{ Minimal ONNX Runtime C API binding for Free Pascal / Lazarus.

  The library is loaded dynamically, so you can point it at a specific
  onnxruntime.dll / libonnxruntime.so (recommended on Windows: give the full
  path, because Windows also ships an old system onnxruntime.dll).

  The function-table indices below were taken from onnxruntime_c_api.h
  (ORT 1.31). The table is append-only, so they are valid for any ORT >= 1.14. }
unit OnnxRT;

{$mode objfpc}{$H+}
{$MACRO ON}
{$IFDEF WINDOWS}
  {$DEFINE ORTCALL := stdcall}
{$ELSE}
  {$DEFINE ORTCALL := cdecl}
{$ENDIF}

interface

uses
  SysUtils, DynLibs, Math;

const
  ORT_REQUESTED_API_VERSION = 14;  // ORT 1.14+; every function used here exists there

  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1;
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8 = 2;

type
  EOrtError = class(Exception);

  TInt64Array = array of Int64;
  TSingleArray = array of Single;

  { One output tensor, copied out of ONNX Runtime. Only float outputs are supported. }
  TOrtOutput = record
    Name: string;
    Shape: TInt64Array;
    Data: TSingleArray;
  end;
  TOrtOutputs = array of TOrtOutput;

  { ---- C function pointer types ---- }
  TOrtGetErrorMessage = function(status: Pointer): PAnsiChar; ORTCALL;
  TOrtCreateEnv = function(level: Integer; logid: PAnsiChar; out env: Pointer): Pointer; ORTCALL;
  TOrtCreateSession = function(env: Pointer; path: Pointer; options: Pointer; out session: Pointer): Pointer; ORTCALL;
  TOrtRun = function(session, runOptions: Pointer; inputNames: PPAnsiChar; inputs: PPointer;
    inputLen: SizeUInt; outputNames: PPAnsiChar; outputLen: SizeUInt; outputs: PPointer): Pointer; ORTCALL;
  TOrtCreateSessionOptions = function(out options: Pointer): Pointer; ORTCALL;
  TOrtSetGraphOptLevel = function(options: Pointer; level: Integer): Pointer; ORTCALL;
  TOrtSetIntraOpNumThreads = function(options: Pointer; n: Integer): Pointer; ORTCALL;
  TOrtSessionGetCount = function(session: Pointer; out count: SizeUInt): Pointer; ORTCALL;
  TOrtSessionGetTypeInfo = function(session: Pointer; index: SizeUInt; out typeInfo: Pointer): Pointer; ORTCALL;
  TOrtSessionGetName = function(session: Pointer; index: SizeUInt; allocator: Pointer; out name: PAnsiChar): Pointer; ORTCALL;
  TOrtCreateTensorWithData = function(memInfo: Pointer; data: Pointer; dataLen: SizeUInt;
    shape: PInt64; shapeLen: SizeUInt; elemType: Integer; out value: Pointer): Pointer; ORTCALL;
  TOrtGetTensorMutableData = function(value: Pointer; out data: Pointer): Pointer; ORTCALL;
  TOrtCastTypeInfoToTensorInfo = function(typeInfo: Pointer; out tensorInfo: Pointer): Pointer; ORTCALL;
  TOrtGetTensorElementType = function(info: Pointer; out elemType: Integer): Pointer; ORTCALL;
  TOrtGetDimensionsCount = function(info: Pointer; out count: SizeUInt): Pointer; ORTCALL;
  TOrtGetDimensions = function(info: Pointer; dims: PInt64; count: SizeUInt): Pointer; ORTCALL;
  TOrtGetTensorTypeAndShape = function(value: Pointer; out info: Pointer): Pointer; ORTCALL;
  TOrtCreateCpuMemoryInfo = function(allocType, memType: Integer; out memInfo: Pointer): Pointer; ORTCALL;
  TOrtAllocatorFree = function(allocator: Pointer; p: Pointer): Pointer; ORTCALL;
  TOrtGetDefaultAllocator = function(out allocator: Pointer): Pointer; ORTCALL;
  TOrtRelease = procedure(p: Pointer); ORTCALL;

  TOrtApiBase = record
    GetApi: function(version: Cardinal): Pointer; ORTCALL;
    GetVersionString: function: PAnsiChar; ORTCALL;
  end;
  POrtApiBase = ^TOrtApiBase;
  TOrtGetApiBase = function: POrtApiBase; ORTCALL;

  { Loads the library and holds the process-wide environment. Create one and share it. }
  TOrtRuntime = class
  private
    FLib: TLibHandle;
    FEnv, FMemInfo, FAllocator: Pointer;
    FVersion: string;
  public
    GetErrorMessage: TOrtGetErrorMessage;
    CreateEnv: TOrtCreateEnv;
    CreateSession: TOrtCreateSession;
    Run: TOrtRun;
    CreateSessionOptions: TOrtCreateSessionOptions;
    SetSessionGraphOptimizationLevel: TOrtSetGraphOptLevel;
    SetIntraOpNumThreads: TOrtSetIntraOpNumThreads;
    SessionGetInputCount, SessionGetOutputCount: TOrtSessionGetCount;
    SessionGetInputTypeInfo, SessionGetOutputTypeInfo: TOrtSessionGetTypeInfo;
    SessionGetInputName, SessionGetOutputName: TOrtSessionGetName;
    CreateTensorWithDataAsOrtValue: TOrtCreateTensorWithData;
    GetTensorMutableData: TOrtGetTensorMutableData;
    CastTypeInfoToTensorInfo: TOrtCastTypeInfoToTensorInfo;
    GetTensorElementType: TOrtGetTensorElementType;
    GetDimensionsCount: TOrtGetDimensionsCount;
    GetDimensions: TOrtGetDimensions;
    GetTensorTypeAndShape: TOrtGetTensorTypeAndShape;
    CreateCpuMemoryInfo: TOrtCreateCpuMemoryInfo;
    AllocatorFree: TOrtAllocatorFree;
    GetAllocatorWithDefaultOptions: TOrtGetDefaultAllocator;
    ReleaseEnv, ReleaseStatus, ReleaseMemoryInfo, ReleaseSession, ReleaseValue,
      ReleaseTypeInfo, ReleaseTensorTypeAndShapeInfo, ReleaseSessionOptions: TOrtRelease;

    { LibPath: full path to onnxruntime.dll / libonnxruntime.so, or '' for the default name. }
    constructor Create(const LibPath: string = '');
    destructor Destroy; override;
    procedure Check(Status: Pointer);
    property Env: Pointer read FEnv;
    property MemInfo: Pointer read FMemInfo;
    property Allocator: Pointer read FAllocator;
    property Version: string read FVersion;
  end;

  { One loaded .onnx model. }
  TOrtSession = class
  private
    FRT: TOrtRuntime;
    FSession: Pointer;
    FInputNames, FOutputNames: array of AnsiString;
    FInputShape: TInt64Array;
    FInputType: Integer;
    function ReadName(Input: Boolean; Index: SizeUInt): AnsiString;
    function ReadTypeInfo(Input: Boolean; Index: SizeUInt; out ElemType: Integer): TInt64Array;
  public
    constructor Create(RT: TOrtRuntime; const ModelPath: string; Threads: Integer = 0);
    destructor Destroy; override;
    { Runs the model with a single input tensor. Data must hold ElementCount(Shape) elements of
      ElemType (UINT8 = bytes, FLOAT = Single). Returns all outputs as float arrays. }
    function RunSingle(Data: Pointer; ByteLen: SizeUInt; const Shape: array of Int64;
      ElemType: Integer): TOrtOutputs;
    function OutputCount: Integer;
    function OutputName(I: Integer): string;
    function OutputShape(I: Integer): TInt64Array;  // -1 for dynamic dimensions
    property InputShape: TInt64Array read FInputShape;  // -1 for dynamic dimensions
    property InputType: Integer read FInputType;
  end;

function FindOutput(const Outs: TOrtOutputs; const Name: string): Integer;
{ Masks floating point exceptions in the calling thread (C libraries expect that). }
procedure MaskFPUExceptions;

implementation

procedure MaskFPUExceptions;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
end;

const
  // Indices into the OrtApi function table (verified against onnxruntime_c_api.h)
  IDX_GetErrorMessage = 2;
  IDX_CreateEnv = 3;
  IDX_CreateSession = 7;
  IDX_Run = 9;
  IDX_CreateSessionOptions = 10;
  IDX_SetSessionGraphOptimizationLevel = 23;
  IDX_SetIntraOpNumThreads = 24;
  IDX_SessionGetInputCount = 30;
  IDX_SessionGetOutputCount = 31;
  IDX_SessionGetInputTypeInfo = 33;
  IDX_SessionGetOutputTypeInfo = 34;
  IDX_SessionGetInputName = 36;
  IDX_SessionGetOutputName = 37;
  IDX_CreateTensorWithDataAsOrtValue = 49;
  IDX_GetTensorMutableData = 51;
  IDX_CastTypeInfoToTensorInfo = 55;
  IDX_GetTensorElementType = 60;
  IDX_GetDimensionsCount = 61;
  IDX_GetDimensions = 62;
  IDX_GetTensorTypeAndShape = 65;
  IDX_CreateCpuMemoryInfo = 69;
  IDX_AllocatorFree = 76;
  IDX_GetAllocatorWithDefaultOptions = 78;
  IDX_ReleaseEnv = 92;
  IDX_ReleaseStatus = 93;
  IDX_ReleaseMemoryInfo = 94;
  IDX_ReleaseSession = 95;
  IDX_ReleaseValue = 96;
  IDX_ReleaseTypeInfo = 98;
  IDX_ReleaseTensorTypeAndShapeInfo = 99;
  IDX_ReleaseSessionOptions = 100;

  ORT_LOGGING_LEVEL_WARNING = 2;
  ORT_ENABLE_ALL = 99;
  OrtArenaAllocator = 1;
  OrtMemTypeDefault = 0;

type
  TPointerTable = array[0..IDX_ReleaseSessionOptions] of Pointer;
  PPointerTable = ^TPointerTable;

function FindOutput(const Outs: TOrtOutputs; const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Outs) do
    if Outs[I].Name = Name then
      Exit(I);
  Result := -1;
end;

{ TOrtRuntime }

constructor TOrtRuntime.Create(const LibPath: string);
var
  LibName: string;
  GetApiBase: TOrtGetApiBase;
  Base: POrtApiBase;
  T: PPointerTable;
begin
  inherited Create;
  // ONNX Runtime (and DirectX/Media Foundation it may touch) expect masked FPU exceptions,
  // FPC unmasks them. Call this also at the start of every thread that runs a model.
  MaskFPUExceptions;
  LibName := LibPath;
  if LibName = '' then
    {$IFDEF WINDOWS}LibName := 'onnxruntime.dll'{$ELSE}{$IFDEF DARWIN}LibName := 'libonnxruntime.dylib'{$ELSE}LibName := 'libonnxruntime.so'{$ENDIF}{$ENDIF};
  FLib := LoadLibrary(LibName);
  if FLib = NilHandle then
    raise EOrtError.CreateFmt('Cannot load ONNX Runtime library "%s"', [LibName]);
  Pointer(GetApiBase) := GetProcAddress(FLib, 'OrtGetApiBase');
  if not Assigned(GetApiBase) then
    raise EOrtError.CreateFmt('"%s" is not an ONNX Runtime library (OrtGetApiBase missing)', [LibName]);
  Base := GetApiBase();
  FVersion := string(Base^.GetVersionString());
  T := PPointerTable(Base^.GetApi(ORT_REQUESTED_API_VERSION));
  if T = nil then
    raise EOrtError.CreateFmt('ONNX Runtime %s is too old (need 1.14 or newer)', [FVersion]);

  Pointer(GetErrorMessage) := T^[IDX_GetErrorMessage];
  Pointer(CreateEnv) := T^[IDX_CreateEnv];
  Pointer(CreateSession) := T^[IDX_CreateSession];
  Pointer(Run) := T^[IDX_Run];
  Pointer(CreateSessionOptions) := T^[IDX_CreateSessionOptions];
  Pointer(SetSessionGraphOptimizationLevel) := T^[IDX_SetSessionGraphOptimizationLevel];
  Pointer(SetIntraOpNumThreads) := T^[IDX_SetIntraOpNumThreads];
  Pointer(SessionGetInputCount) := T^[IDX_SessionGetInputCount];
  Pointer(SessionGetOutputCount) := T^[IDX_SessionGetOutputCount];
  Pointer(SessionGetInputTypeInfo) := T^[IDX_SessionGetInputTypeInfo];
  Pointer(SessionGetOutputTypeInfo) := T^[IDX_SessionGetOutputTypeInfo];
  Pointer(SessionGetInputName) := T^[IDX_SessionGetInputName];
  Pointer(SessionGetOutputName) := T^[IDX_SessionGetOutputName];
  Pointer(CreateTensorWithDataAsOrtValue) := T^[IDX_CreateTensorWithDataAsOrtValue];
  Pointer(GetTensorMutableData) := T^[IDX_GetTensorMutableData];
  Pointer(CastTypeInfoToTensorInfo) := T^[IDX_CastTypeInfoToTensorInfo];
  Pointer(GetTensorElementType) := T^[IDX_GetTensorElementType];
  Pointer(GetDimensionsCount) := T^[IDX_GetDimensionsCount];
  Pointer(GetDimensions) := T^[IDX_GetDimensions];
  Pointer(GetTensorTypeAndShape) := T^[IDX_GetTensorTypeAndShape];
  Pointer(CreateCpuMemoryInfo) := T^[IDX_CreateCpuMemoryInfo];
  Pointer(AllocatorFree) := T^[IDX_AllocatorFree];
  Pointer(GetAllocatorWithDefaultOptions) := T^[IDX_GetAllocatorWithDefaultOptions];
  Pointer(ReleaseEnv) := T^[IDX_ReleaseEnv];
  Pointer(ReleaseStatus) := T^[IDX_ReleaseStatus];
  Pointer(ReleaseMemoryInfo) := T^[IDX_ReleaseMemoryInfo];
  Pointer(ReleaseSession) := T^[IDX_ReleaseSession];
  Pointer(ReleaseValue) := T^[IDX_ReleaseValue];
  Pointer(ReleaseTypeInfo) := T^[IDX_ReleaseTypeInfo];
  Pointer(ReleaseTensorTypeAndShapeInfo) := T^[IDX_ReleaseTensorTypeAndShapeInfo];
  Pointer(ReleaseSessionOptions) := T^[IDX_ReleaseSessionOptions];

  Check(CreateEnv(ORT_LOGGING_LEVEL_WARNING, 'alpr', FEnv));
  Check(CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, FMemInfo));
  Check(GetAllocatorWithDefaultOptions(FAllocator));  // owned by ORT, never released
end;

destructor TOrtRuntime.Destroy;
begin
  if Assigned(FMemInfo) then ReleaseMemoryInfo(FMemInfo);
  if Assigned(FEnv) then ReleaseEnv(FEnv);
  if FLib <> NilHandle then UnloadLibrary(FLib);
  inherited Destroy;
end;

procedure TOrtRuntime.Check(Status: Pointer);
var
  Msg: string;
begin
  if Status = nil then
    Exit;
  Msg := string(GetErrorMessage(Status));
  ReleaseStatus(Status);
  raise EOrtError.Create('ONNX Runtime: ' + Msg);
end;

{ TOrtSession }

constructor TOrtSession.Create(RT: TOrtRuntime; const ModelPath: string; Threads: Integer);
var
  Opts: Pointer;
  N: SizeUInt;
  I: Integer;
  {$IFDEF WINDOWS}WPath: UnicodeString;{$ELSE}APath: RawByteString;{$ENDIF}
begin
  inherited Create;
  FRT := RT;
  if not FileExists(ModelPath) then
    raise EOrtError.CreateFmt('Model file not found: %s', [ModelPath]);
  RT.Check(RT.CreateSessionOptions(Opts));
  try
    RT.Check(RT.SetSessionGraphOptimizationLevel(Opts, ORT_ENABLE_ALL));
    if Threads > 0 then
      RT.Check(RT.SetIntraOpNumThreads(Opts, Threads));
    {$IFDEF WINDOWS}
    WPath := UTF8Decode(ModelPath);  // ORT on Windows wants a wide-char path
    RT.Check(RT.CreateSession(RT.Env, PWideChar(WPath), Opts, FSession));
    {$ELSE}
    APath := UTF8Encode(ModelPath);
    RT.Check(RT.CreateSession(RT.Env, PAnsiChar(APath), Opts, FSession));
    {$ENDIF}
  finally
    RT.ReleaseSessionOptions(Opts);
  end;

  RT.Check(RT.SessionGetInputCount(FSession, N));
  if N <> 1 then
    raise EOrtError.CreateFmt('Expected a model with 1 input, got %d', [N]);
  SetLength(FInputNames, 1);
  FInputNames[0] := ReadName(True, 0);
  FInputShape := ReadTypeInfo(True, 0, FInputType);

  RT.Check(RT.SessionGetOutputCount(FSession, N));
  SetLength(FOutputNames, N);
  for I := 0 to Integer(N) - 1 do
    FOutputNames[I] := ReadName(False, I);
end;

destructor TOrtSession.Destroy;
begin
  if Assigned(FSession) then
    FRT.ReleaseSession(FSession);
  inherited Destroy;
end;

function TOrtSession.ReadName(Input: Boolean; Index: SizeUInt): AnsiString;
var
  P: PAnsiChar;
begin
  if Input then
    FRT.Check(FRT.SessionGetInputName(FSession, Index, FRT.Allocator, P))
  else
    FRT.Check(FRT.SessionGetOutputName(FSession, Index, FRT.Allocator, P));
  Result := AnsiString(P);
  FRT.Check(FRT.AllocatorFree(FRT.Allocator, P));
end;

function TOrtSession.ReadTypeInfo(Input: Boolean; Index: SizeUInt; out ElemType: Integer): TInt64Array;
var
  TI, Info: Pointer;
  N: SizeUInt;
begin
  Result := nil;
  if Input then
    FRT.Check(FRT.SessionGetInputTypeInfo(FSession, Index, TI))
  else
    FRT.Check(FRT.SessionGetOutputTypeInfo(FSession, Index, TI));
  try
    FRT.Check(FRT.CastTypeInfoToTensorInfo(TI, Info));  // Info belongs to TI, not released
    FRT.Check(FRT.GetTensorElementType(Info, ElemType));
    FRT.Check(FRT.GetDimensionsCount(Info, N));
    SetLength(Result, N);
    if N > 0 then
      FRT.Check(FRT.GetDimensions(Info, @Result[0], N));
  finally
    FRT.ReleaseTypeInfo(TI);
  end;
end;

function TOrtSession.OutputCount: Integer;
begin
  Result := Length(FOutputNames);
end;

function TOrtSession.OutputName(I: Integer): string;
begin
  Result := string(FOutputNames[I]);
end;

function TOrtSession.OutputShape(I: Integer): TInt64Array;
var
  ET: Integer;
begin
  Result := ReadTypeInfo(False, I, ET);
end;

function TOrtSession.RunSingle(Data: Pointer; ByteLen: SizeUInt; const Shape: array of Int64;
  ElemType: Integer): TOrtOutputs;
var
  InValue: Pointer;
  InNames: array[0..0] of PAnsiChar;
  OutNames: array of PAnsiChar;
  OutValues: array of Pointer;
  ShapeCopy: TInt64Array;
  I, ET: Integer;
  J: SizeUInt;
  Info, P: Pointer;
  N, Count: SizeUInt;
begin
  Result := nil;
  SetLength(ShapeCopy, Length(Shape));
  for I := 0 to High(Shape) do
    ShapeCopy[I] := Shape[I];
  FRT.Check(FRT.CreateTensorWithDataAsOrtValue(FRT.MemInfo, Data, ByteLen, @ShapeCopy[0],
    Length(ShapeCopy), ElemType, InValue));
  SetLength(OutNames, Length(FOutputNames));
  SetLength(OutValues, Length(FOutputNames));
  for I := 0 to High(FOutputNames) do
  begin
    OutNames[I] := PAnsiChar(FOutputNames[I]);
    OutValues[I] := nil;
  end;
  InNames[0] := PAnsiChar(FInputNames[0]);
  try
    FRT.Check(FRT.Run(FSession, nil, @InNames[0], @InValue, 1,
      @OutNames[0], Length(OutNames), @OutValues[0]));
    SetLength(Result, Length(OutValues));
    for I := 0 to High(OutValues) do
    begin
      Result[I].Name := string(FOutputNames[I]);
      FRT.Check(FRT.GetTensorTypeAndShape(OutValues[I], Info));
      try
        FRT.Check(FRT.GetTensorElementType(Info, ET));
        if ET <> ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT then
          raise EOrtError.CreateFmt('Output "%s" is not float', [Result[I].Name]);
        FRT.Check(FRT.GetDimensionsCount(Info, N));
        SetLength(Result[I].Shape, N);
        if N > 0 then
          FRT.Check(FRT.GetDimensions(Info, @Result[I].Shape[0], N));
      finally
        FRT.ReleaseTensorTypeAndShapeInfo(Info);
      end;
      Count := 1;
      for J := 1 to N do
        Count := Count * SizeUInt(Result[I].Shape[J - 1]);
      SetLength(Result[I].Data, Count);
      if Count > 0 then
      begin
        FRT.Check(FRT.GetTensorMutableData(OutValues[I], P));
        Move(P^, Result[I].Data[0], Count * SizeOf(Single));
      end;
    end;
  finally
    for I := 0 to High(OutValues) do
      if OutValues[I] <> nil then
        FRT.ReleaseValue(OutValues[I]);
    FRT.ReleaseValue(InValue);
  end;
end;

end.
