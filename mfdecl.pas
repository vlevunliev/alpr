unit mfdecl;
{ Media Foundation / COM декларации, общи за плейъра и рекордера.
  Редът на методите е сверен с mingw-w64 (mfobjects.h, mfreadwrite.h, mfmediaengine.idl). }

{$mode objfpc}{$H+}{$codepage utf8}
{$packrecords c}

interface

uses
  Windows;

type
  PIUnknown = ^IUnknown;

  IMFAttributes = interface(IUnknown)
    ['{2CD2D921-C447-44A7-A13C-4ADABFC247E3}']
    function GetItem(constref guidKey: TGUID; pValue: Pointer): HResult; stdcall;
    function GetItemType(constref guidKey: TGUID; pType: PDWORD): HResult; stdcall;
    function CompareItem(constref guidKey: TGUID; Value: Pointer; pbResult: PBOOL): HResult; stdcall;
    function Compare(pTheirs: Pointer; MatchType: DWORD; pbResult: PBOOL): HResult; stdcall;
    function GetUINT32(constref guidKey: TGUID; out punValue: UINT32): HResult; stdcall;
    function GetUINT64(constref guidKey: TGUID; out punValue: UInt64): HResult; stdcall;
    function GetDouble(constref guidKey: TGUID; out pfValue: Double): HResult; stdcall;
    function GetGUID(constref guidKey: TGUID; out pguidValue: TGUID): HResult; stdcall;
    function GetStringLength(constref guidKey: TGUID; out pcchLength: UINT32): HResult; stdcall;
    function GetString(constref guidKey: TGUID; pwszValue: PWideChar; cchBufSize: UINT32; pcchLength: PUINT32): HResult; stdcall;
    function GetAllocatedString(constref guidKey: TGUID; out ppwszValue: PWideChar; out pcchLength: UINT32): HResult; stdcall;
    function GetBlobSize(constref guidKey: TGUID; out pcbBlobSize: UINT32): HResult; stdcall;
    function GetBlob(constref guidKey: TGUID; pBuf: PByte; cbBufSize: UINT32; pcbBlobSize: PUINT32): HResult; stdcall;
    function GetAllocatedBlob(constref guidKey: TGUID; out ppBuf: PByte; out pcbSize: UINT32): HResult; stdcall;
    function GetUnknown(constref guidKey: TGUID; constref riid: TGUID; out ppv): HResult; stdcall;
    function SetItem(constref guidKey: TGUID; Value: Pointer): HResult; stdcall;
    function DeleteItem(constref guidKey: TGUID): HResult; stdcall;
    function DeleteAllItems: HResult; stdcall;
    function SetUINT32(constref guidKey: TGUID; unValue: UINT32): HResult; stdcall;
    function SetUINT64(constref guidKey: TGUID; unValue: UInt64): HResult; stdcall;
    function SetDouble(constref guidKey: TGUID; fValue: Double): HResult; stdcall;
    function SetGUID(constref guidKey: TGUID; constref guidValue: TGUID): HResult; stdcall;
    function SetString(constref guidKey: TGUID; wszValue: PWideChar): HResult; stdcall;
    function SetBlob(constref guidKey: TGUID; pBuf: PByte; cbBufSize: UINT32): HResult; stdcall;
    function SetUnknown(constref guidKey: TGUID; const pUnknown: IUnknown): HResult; stdcall;
    function LockStore: HResult; stdcall;
    function UnlockStore: HResult; stdcall;
    function GetCount(out pcItems: UINT32): HResult; stdcall;
    function GetItemByIndex(unIndex: UINT32; pguidKey: PGUID; pValue: Pointer): HResult; stdcall;
    function CopyAllItems(pDest: Pointer): HResult; stdcall;
  end;

  IMFMediaType = interface(IMFAttributes)
    ['{44AE0FA8-EA31-4109-8D2E-4CAE4997C555}']
    { следващите методи не се ползват }
  end;

  IMFMediaBuffer = interface(IUnknown)
    ['{045FA593-8799-42B8-BC8D-8968C6453507}']
    function Lock(out ppbBuffer: PByte; pcbMaxLength, pcbCurrentLength: PDWORD): HResult; stdcall;
    function Unlock: HResult; stdcall;
    function GetCurrentLength(out pcbCurrentLength: DWORD): HResult; stdcall;
    function SetCurrentLength(cbCurrentLength: DWORD): HResult; stdcall;
    function GetMaxLength(out pcbMaxLength: DWORD): HResult; stdcall;
  end;

  IMFSample = interface(IMFAttributes)
    ['{C40A00F2-B93A-4D80-AE8C-5A1C634F58E4}']
    function GetSampleFlags(out pdwSampleFlags: DWORD): HResult; stdcall;
    function SetSampleFlags(dwSampleFlags: DWORD): HResult; stdcall;
    function GetSampleTime(out phnsSampleTime: Int64): HResult; stdcall;
    function SetSampleTime(hnsSampleTime: Int64): HResult; stdcall;
    function GetSampleDuration(out phnsSampleDuration: Int64): HResult; stdcall;
    function SetSampleDuration(hnsSampleDuration: Int64): HResult; stdcall;
    function GetBufferCount(out pdwBufferCount: DWORD): HResult; stdcall;
    function GetBufferByIndex(dwIndex: DWORD; out ppBuffer: IMFMediaBuffer): HResult; stdcall;
    function ConvertToContiguousBuffer(out ppBuffer: IMFMediaBuffer): HResult; stdcall;
    function AddBuffer(const pBuffer: IMFMediaBuffer): HResult; stdcall;
  end;

  TPropVarI8 = record          // PROPVARIANT с VT_I8, 24 байта на x64
    vt: Word;
    r1, r2, r3: Word;
    hVal: Int64;
    pad: Int64;
  end;

  IMFSourceReader = interface(IUnknown)
    ['{70AE66F2-C809-4E4F-8915-BDCB406B7993}']
    function GetStreamSelection(dwStreamIndex: DWORD; out pfSelected: LongBool): HResult; stdcall;
    function SetStreamSelection(dwStreamIndex: DWORD; fSelected: LongBool): HResult; stdcall;
    function GetNativeMediaType(dwStreamIndex, dwMediaTypeIndex: DWORD; out ppMediaType: IMFMediaType): HResult; stdcall;
    function GetCurrentMediaType(dwStreamIndex: DWORD; out ppMediaType: IMFMediaType): HResult; stdcall;
    function SetCurrentMediaType(dwStreamIndex: DWORD; pdwReserved: PDWORD; const pMediaType: IMFMediaType): HResult; stdcall;
    function SetCurrentPosition(constref guidTimeFormat: TGUID; constref varPosition: TPropVarI8): HResult; stdcall;
    function ReadSample(dwStreamIndex, dwControlFlags: DWORD; pdwActualStreamIndex, pdwStreamFlags: PDWORD;
      pllTimestamp: PInt64; out ppSample: IMFSample): HResult; stdcall;
  end;

  IMFSinkWriter = interface(IUnknown)
    ['{3137F1CD-FE5E-4805-A5D8-FB477448CB3D}']
    function AddStream(const pTargetMediaType: IMFMediaType; out pdwStreamIndex: DWORD): HResult; stdcall;
    function SetInputMediaType(dwStreamIndex: DWORD; const pInputMediaType: IMFMediaType; const pEncodingParameters: IMFAttributes): HResult; stdcall;
    function BeginWriting: HResult; stdcall;
    function WriteSample(dwStreamIndex: DWORD; const pSample: IMFSample): HResult; stdcall;
    function SendStreamTick(dwStreamIndex: DWORD; llTimestamp: Int64): HResult; stdcall;
    function PlaceMarker(dwStreamIndex: DWORD; pvContext: Pointer): HResult; stdcall;
    function NotifyEndOfSegment(dwStreamIndex: DWORD): HResult; stdcall;
    function Flush(dwStreamIndex: DWORD): HResult; stdcall;
    function Finalize_: HResult; stdcall;
  end;

  IMFDXGIDeviceManager = interface(IUnknown)
    ['{EB533D5D-2DB6-40F8-97A9-494692014F07}']
    function CloseDeviceHandle(hDevice: THandle): HResult; stdcall;
    function GetVideoService(hDevice: THandle; constref riid: TGUID; out ppService): HResult; stdcall;
    function LockDevice(hDevice: THandle; constref riid: TGUID; out ppUnkDevice; fBlock: LongBool): HResult; stdcall;
    function OpenDeviceHandle(out phDevice: THandle): HResult; stdcall;
    function ResetDevice(const pUnkDevice: IUnknown; resetToken: UINT): HResult; stdcall;
  end;

  ID3D10Multithread = interface(IUnknown)
    ['{9B7E4E00-342C-4106-A19F-4F2704F689F0}']
    procedure Enter; stdcall;
    procedure Leave; stdcall;
    function SetMultithreadProtected(bMTProtect: LongBool): LongBool; stdcall;
    function GetMultithreadProtected: LongBool; stdcall;
  end;

  IMFMediaError = interface(IUnknown)
    ['{FC0E10D2-AB2A-4501-A951-06BB1075184C}']
    function GetErrorCode: Word; stdcall;
    function GetExtendedErrorCode: HResult; stdcall;
  end;

  IMFMediaEngine = interface(IUnknown)
    ['{98A1B0BB-03EB-4935-AE7C-93C1FA0E1C93}']
    function GetError(out ppError: IMFMediaError): HResult; stdcall;
    function SetErrorCode(error: DWORD): HResult; stdcall;
    function SetSourceElements(pSrcElements: Pointer): HResult; stdcall;
    function SetSource(pUrl: PWideChar): HResult; stdcall;            // BSTR
    function GetCurrentSource(out ppUrl: PWideChar): HResult; stdcall;
    function GetNetworkState: Word; stdcall;
    function GetPreload: DWORD; stdcall;
    function SetPreload(Preload: DWORD): HResult; stdcall;
    function GetBuffered(out ppBuffered: IUnknown): HResult; stdcall;
    function Load: HResult; stdcall;
    function CanPlayType(type_: PWideChar; out pAnswer: DWORD): HResult; stdcall;
    function GetReadyState: Word; stdcall;
    function IsSeeking: LongBool; stdcall;
    function GetCurrentTime: Double; stdcall;
    function SetCurrentTime(seekTime: Double): HResult; stdcall;
    function GetStartTime: Double; stdcall;
    function GetDuration: Double; stdcall;
    function IsPaused: LongBool; stdcall;
    function GetDefaultPlaybackRate: Double; stdcall;
    function SetDefaultPlaybackRate(Rate: Double): HResult; stdcall;
    function GetPlaybackRate: Double; stdcall;
    function SetPlaybackRate(Rate: Double): HResult; stdcall;
    function GetPlayed(out ppPlayed: IUnknown): HResult; stdcall;
    function GetSeekable(out ppSeekable: IUnknown): HResult; stdcall;
    function IsEnded: LongBool; stdcall;
    function GetAutoPlay: LongBool; stdcall;
    function SetAutoPlay(AutoPlay: LongBool): HResult; stdcall;
    function GetLoop: LongBool; stdcall;
    function SetLoop(Loop: LongBool): HResult; stdcall;
    function Play: HResult; stdcall;
    function Pause: HResult; stdcall;
    function GetMuted: LongBool; stdcall;
    function SetMuted(Muted: LongBool): HResult; stdcall;
    function GetVolume: Double; stdcall;
    function SetVolume(Volume: Double): HResult; stdcall;
    function HasVideo: LongBool; stdcall;
    function HasAudio: LongBool; stdcall;
    function GetNativeVideoSize(out cx, cy: DWORD): HResult; stdcall;
    function GetVideoAspectRatio(out cx, cy: DWORD): HResult; stdcall;
    function Shutdown: HResult; stdcall;
    function TransferVideoFrame(pDstSurf: Pointer; pSrc: Pointer; pDst: PRect; pBorderClr: Pointer): HResult; stdcall;
    function OnVideoStreamTick(out pPts: Int64): HResult; stdcall;
  end;

  IMFMediaEngineEx = interface(IMFMediaEngine)
    ['{83015EAD-B1E6-40D0-A98A-37145FFE1AD1}']
    function SetSourceFromByteStream(pByteStream: Pointer; pURL: PWideChar): HResult; stdcall;
    function GetStatistics(StatisticID: DWORD; pStatistic: Pointer): HResult; stdcall;
    function UpdateVideoStream(pSrc: Pointer; pDst: PRect; pBorderClr: Pointer): HResult; stdcall;
    function GetBalance: Double; stdcall;
    function SetBalance(balance: Double): HResult; stdcall;
    function IsPlaybackRateSupported(rate: Double): LongBool; stdcall;
    function FrameStep(Forward: LongBool): HResult; stdcall;
  end;

  IMFMediaEngineClassFactory = interface(IUnknown)
    ['{4D645ACE-26AA-4688-9BE1-DF3516990B93}']
    function CreateInstance(dwFlags: DWORD; const pAttr: IMFAttributes; out ppPlayer: IMFMediaEngine): HResult; stdcall;
    function CreateTimeRange(out ppTimeRange: IUnknown): HResult; stdcall;
    function CreateError(out ppError: IMFMediaError): HResult; stdcall;
  end;

  IMFMediaEngineNotify = interface(IUnknown)
    ['{FEE7C112-E776-42B5-9BBF-0048524E2BD5}']
    function EventNotify(event: DWORD; param1: PtrUInt; param2: DWORD): HResult; stdcall;
  end;

const
  CLSID_MFMediaEngineClassFactory: TGUID = '{B44392DA-499B-446B-A4CB-005FEAD0E6D5}';
  MF_MEDIA_ENGINE_CALLBACK: TGUID            = '{C60381B8-83A4-41F8-A3D0-DE05076849A9}';
  MF_MEDIA_ENGINE_PLAYBACK_HWND: TGUID       = '{D988879B-67C9-4D92-BAA7-6EADD446039D}';
  MF_MEDIA_ENGINE_DXGI_MANAGER: TGUID        = '{065702DA-1094-486D-8617-EE7CC4EE4648}';
  MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT: TGUID = '{5066893C-8CF9-42BC-8B8A-472212E52726}';

  MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING: TGUID = '{FB394F3D-CCF1-42EE-BBB3-F9B845D5681D}';
  MF_MT_MAJOR_TYPE: TGUID     = '{48EBA18E-F8C9-4687-BF11-0A74C9F96A8F}';
  MF_MT_SUBTYPE: TGUID        = '{F7E34C9A-42E8-4714-B74B-CB29D72C35E5}';
  MF_MT_FRAME_SIZE: TGUID     = '{1652C33D-D6B2-4012-B834-72030849A37D}';
  MF_MT_DEFAULT_STRIDE: TGUID = '{644B4E48-1E02-4516-B0EB-C01CA9D49AC6}';
  MFMediaType_Video: TGUID    = '{73646976-0000-0010-8000-00AA00389B71}';
  MFVideoFormat_RGB32: TGUID  = '{00000016-0000-0010-8000-00AA00389B71}';
  GUID_NULL: TGUID            = '{00000000-0000-0000-0000-000000000000}';
  MFVideoFormat_H264: TGUID   = '{34363248-0000-0010-8000-00AA00389B71}';
  MFVideoFormat_HEVC: TGUID   = '{43564548-0000-0010-8000-00AA00389B71}';
  MFMediaType_Audio: TGUID    = '{73647561-0000-0010-8000-00AA00389B71}';
  MFAudioFormat_PCM: TGUID    = '{00000001-0000-0010-8000-00AA00389B71}';
  MFAudioFormat_AAC: TGUID    = '{00001610-0000-0010-8000-00AA00389B71}';
  MF_MT_AVG_BITRATE: TGUID        = '{20332624-FB0D-4D9E-BD0D-CBF6786C102E}';
  MF_MT_INTERLACE_MODE: TGUID     = '{E2724BB8-E676-4806-B4B2-A8D6EFB44CCD}';
  MF_MT_FRAME_RATE: TGUID         = '{C459A2E8-3D2C-4E44-B132-FEE5156C7BB0}';
  MF_MT_PIXEL_ASPECT_RATIO: TGUID = '{C6376A1E-8D0A-4027-BE45-6D9A0AD39BB6}';
  MF_MT_AUDIO_SAMPLES_PER_SECOND: TGUID   = '{5FAEEAE7-0290-4C31-9E8A-C534F68D9DBA}';
  MF_MT_AUDIO_NUM_CHANNELS: TGUID         = '{37E48BF5-645E-4C5B-89DE-ADA9E29B696A}';
  MF_MT_AUDIO_BITS_PER_SAMPLE: TGUID      = '{F2DEB57F-40FA-4764-AA33-ED4F2D1FF669}';
  MF_MT_AUDIO_AVG_BYTES_PER_SECOND: TGUID = '{1AAB75C8-CFEF-451C-AB95-AC034B8E1731}';
  MF_MT_AUDIO_BLOCK_ALIGNMENT: TGUID      = '{322DE230-9EEB-43BD-AB7A-FF412251541D}';
  MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS: TGUID = '{A634A91C-822B-41B9-A494-4DE4643612B0}';

  MF_VERSION = $00020070;
  MFSTARTUP_FULL = 0;
  MF_SOURCE_READER_ALL_STREAMS = $FFFFFFFE;
  MF_SOURCE_READER_FIRST_VIDEO_STREAM = $FFFFFFFC;
  MF_SOURCE_READERF_ERROR = $1;
  MF_SOURCE_READERF_ENDOFSTREAM = $2;
  DXGI_FORMAT_B8G8R8A8_UNORM = 87;
  VT_I8 = 20;

  ME_LOADSTART = 1; ME_ERROR = 5; ME_PLAY = 8; ME_PAUSE = 9; ME_LOADEDMETADATA = 10;
  ME_PLAYING = 13; ME_SEEKED = 17; ME_ENDED = 19; ME_RATECHANGE = 20; ME_DURATIONCHANGE = 21;
  ME_VOLUMECHANGE = 22; ME_FORMATCHANGE = 1000; ME_FIRSTFRAMEREADY = 1009;

function ole_CoInitializeEx(pvReserved: Pointer; dwCoInit: DWORD): HResult; stdcall; external 'ole32.dll' name 'CoInitializeEx';
function ole_CoCreateInstance(constref clsid: TGUID; unkOuter: Pointer; dwClsContext: DWORD;
  constref iid: TGUID; out pv): HResult; stdcall; external 'ole32.dll' name 'CoCreateInstance';
function MFStartup(Version: ULONG; dwFlags: DWORD): HResult; stdcall; external 'mfplat.dll';
function MFShutdown: HResult; stdcall; external 'mfplat.dll';
function MFCreateAttributes(out ppMFAttributes: IMFAttributes; cInitialSize: UINT32): HResult; stdcall; external 'mfplat.dll';
function MFCreateMediaType(out ppMFType: IMFMediaType): HResult; stdcall; external 'mfplat.dll';
function MFCreateDXGIDeviceManager(out resetToken: UINT; out ppDeviceManager: IMFDXGIDeviceManager): HResult; stdcall; external 'mfplat.dll';
function MFCreateSourceReaderFromURL(pwszURL: PWideChar; const pAttributes: IMFAttributes;
  out ppSourceReader: IMFSourceReader): HResult; stdcall; external 'mfreadwrite.dll';
function D3D11CreateDevice(pAdapter: Pointer; DriverType: UINT; Software: HMODULE; Flags: UINT;
  pFeatureLevels: Pointer; FeatureLevels: UINT; SDKVersion: UINT; out ppDevice: IUnknown;
  pFeatureLevel: Pointer; ppImmediateContext: Pointer): HResult; stdcall; external 'd3d11.dll';
function MFCreateSinkWriterFromURL(pwszOutputURL: PWideChar; pByteStream: Pointer; const pAttributes: IMFAttributes;
  out ppSinkWriter: IMFSinkWriter): HResult; stdcall; external 'mfreadwrite.dll';
function MFCreateMemoryBuffer(cbMaxLength: DWORD; out ppBuffer: IMFMediaBuffer): HResult; stdcall; external 'mfplat.dll';
function MFCreateSample(out ppIMFSample: IMFSample): HResult; stdcall; external 'mfplat.dll';

function Pack2(hi, lo: UINT32): UInt64; inline;

implementation

function Pack2(hi, lo: UINT32): UInt64; inline;
begin
  Result := (UInt64(hi) shl 32) or lo;
end;

end.
