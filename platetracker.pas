{ Turns per-frame ALPR results into one event per car.

  A car is visible in many frames and every frame gives a reading that may
  differ by a character. The tracker groups readings that belong to the same
  car (overlapping box or nearly the same text), votes for the most frequent
  text and reports it once.

    Tracker := TPlateTracker.Create;
    Tracker.OnPlate := @MyHandler;
    ... for every processed frame:  Tracker.Feed(Alpr.Predict(Img), TimeInSeconds);
    ... at end of a file:           Tracker.Flush;

  Platform independent, no LCL needed. }
unit PlateTracker;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, FastAlpr;

type
  TPlateEvent = record
    Text: string;          // the winning reading
    Votes: Integer;        // how many frames agreed on Text
    Frames: Integer;       // all frames that belonged to this car
    BestConf: Single;      // best OCR confidence for Text
    FirstTime, LastTime: Double;  // seconds
    Box: TPlateBox;        // box from the latest frame
    Confirmed: Boolean;    // True = reached ConfirmVotes; False = reported at the end with fewer votes
  end;

  TPlateEventProc = procedure(const E: TPlateEvent) of object;
  TPlateFilterFunc = function(const Text: string): Boolean;

  TVote = record
    Text: string;
    Count: Integer;
    BestConf: Single;
  end;

  TTrack = record
    Votes: array of TVote;
    Frames: Integer;
    FirstTime, LastTime: Double;
    Box: TPlateBox;
    Reported: Boolean;
  end;

  TPlateTracker = class
  private
    FTracks: array of TTrack;
    FRecentText: array of string;   // recently reported plates (cooldown)
    FRecentTime: array of Double;
    function Leader(const T: TTrack): Integer;
    function InCooldown(const Text: string; Now: Double): Boolean;
    procedure Report(var T: TTrack; Confirmed: Boolean);
    procedure Expire(Now: Double; All: Boolean);
  public
    MinConfidence: Single;   // ignore readings with lower mean OCR confidence (default 0.80)
    MinLength: Integer;      // ignore shorter texts (default 4)
    ConfirmVotes: Integer;   // report as soon as the leading text has this many votes (default 3)
    LostAfter: Double;       // a car is gone after this many seconds without a reading (default 1.5)
    Cooldown: Double;        // the same plate is not reported again within this time (default 30 s)
    ReportUnconfirmed: Boolean;  // report cars that left before ConfirmVotes (default True)
    UnconfirmedMinVotes: Integer;  // ...but only with at least this many equal readings (default 2)
    EdgeMargin: Integer;     // ignore plates closer than this to the frame edge - they are usually
                             // cut off and read as a confident but partial text (default 3 px, 0 = off)
    Filter: TPlateFilterFunc;    // optional, e.g. @IsBulgarianPlate
    OnPlate: TPlateEventProc;
    constructor Create;
    { ImgWidth/ImgHeight are needed for EdgeMargin; pass 0 to skip that check. }
    procedure Feed(const Res: TPlateResults; Time: Double; ImgWidth: Integer = 0; ImgHeight: Integer = 0);
    procedure Flush;  // call at the end of a file
    procedure Clear;
  end;

{ Bulgarian format: 1-2 letters, 4 digits, 1-2 letters (CA1234AB, B1234X, ...) }
function IsBulgarianPlate(const Text: string): Boolean;
function EditDistance(const A, B: string): Integer;

implementation

function IsBulgarianPlate(const Text: string): Boolean;
var
  I, N, L1, L2: Integer;
begin
  Result := False;
  N := Length(Text);
  I := 1;
  L1 := 0;
  while (I <= N) and (Text[I] in ['A'..'Z']) do begin Inc(I); Inc(L1); end;
  if not (L1 in [1, 2]) then Exit;
  if N - I + 1 < 5 then Exit;
  if not ((Text[I] in ['0'..'9']) and (Text[I + 1] in ['0'..'9']) and
          (Text[I + 2] in ['0'..'9']) and (Text[I + 3] in ['0'..'9'])) then Exit;
  Inc(I, 4);
  L2 := 0;
  while (I <= N) and (Text[I] in ['A'..'Z']) do begin Inc(I); Inc(L2); end;
  Result := (I > N) and (L2 in [1, 2]);
end;

function EditDistance(const A, B: string): Integer;
var
  D: array of array of Integer;
  I, J: Integer;
begin
  SetLength(D, Length(A) + 1, Length(B) + 1);
  for I := 0 to Length(A) do D[I, 0] := I;
  for J := 0 to Length(B) do D[0, J] := J;
  for I := 1 to Length(A) do
    for J := 1 to Length(B) do
      D[I, J] := Min(Min(D[I - 1, J] + 1, D[I, J - 1] + 1),
        D[I - 1, J - 1] + Ord(A[I] <> B[J]));
  Result := D[Length(A), Length(B)];
end;

function IoU(const A, B: TPlateBox): Single;
var
  IW, IH, Inter, UA: Single;
begin
  IW := Min(A.X2, B.X2) - Max(A.X1, B.X1);
  IH := Min(A.Y2, B.Y2) - Max(A.Y1, B.Y1);
  if (IW <= 0) or (IH <= 0) then Exit(0);
  Inter := IW * IH;
  UA := (A.X2 - A.X1) * (A.Y2 - A.Y1) + (B.X2 - B.X1) * (B.Y2 - B.Y1) - Inter;
  if UA <= 0 then Exit(0);
  Result := Inter / UA;
end;

constructor TPlateTracker.Create;
begin
  inherited Create;
  MinConfidence := 0.80;
  MinLength := 4;
  ConfirmVotes := 3;
  LostAfter := 1.5;
  Cooldown := 30;
  ReportUnconfirmed := True;
  UnconfirmedMinVotes := 2;
  EdgeMargin := 3;
end;

procedure TPlateTracker.Clear;
begin
  FTracks := nil;
  FRecentText := nil;
  FRecentTime := nil;
end;

function TPlateTracker.Leader(const T: TTrack): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(T.Votes) do
    if (Result < 0) or (T.Votes[I].Count > T.Votes[Result].Count) or
       ((T.Votes[I].Count = T.Votes[Result].Count) and (T.Votes[I].BestConf > T.Votes[Result].BestConf)) then
      Result := I;
end;

function TPlateTracker.InCooldown(const Text: string; Now: Double): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FRecentText) do
    if (FRecentText[I] = Text) and (Now - FRecentTime[I] < Cooldown) then
      Exit(True);
  Result := False;
end;

procedure TPlateTracker.Report(var T: TTrack; Confirmed: Boolean);
var
  E: TPlateEvent;
  L, I: Integer;
begin
  T.Reported := True;
  L := Leader(T);
  if L < 0 then Exit;
  if InCooldown(T.Votes[L].Text, T.LastTime) then Exit;
  // remember for the cooldown (drop old entries)
  I := 0;
  while I <= High(FRecentText) do
    if T.LastTime - FRecentTime[I] >= Cooldown then
    begin
      Delete(FRecentText, I, 1);
      Delete(FRecentTime, I, 1);
    end
    else
      Inc(I);
  SetLength(FRecentText, Length(FRecentText) + 1);
  SetLength(FRecentTime, Length(FRecentTime) + 1);
  FRecentText[High(FRecentText)] := T.Votes[L].Text;
  FRecentTime[High(FRecentTime)] := T.LastTime;

  E.Text := T.Votes[L].Text;
  E.Votes := T.Votes[L].Count;
  E.Frames := T.Frames;
  E.BestConf := T.Votes[L].BestConf;
  E.FirstTime := T.FirstTime;
  E.LastTime := T.LastTime;
  E.Box := T.Box;
  E.Confirmed := Confirmed;
  if Assigned(OnPlate) then
    OnPlate(E);
end;

procedure TPlateTracker.Expire(Now: Double; All: Boolean);
var
  I: Integer;
begin
  I := 0;
  while I <= High(FTracks) do
    if All or (Now - FTracks[I].LastTime > LostAfter) then
    begin
      if not FTracks[I].Reported and ReportUnconfirmed and (Length(FTracks[I].Votes) > 0) and
         (FTracks[I].Votes[Leader(FTracks[I])].Count >= UnconfirmedMinVotes) then
        Report(FTracks[I], False);
      Delete(FTracks, I, 1);
    end
    else
      Inc(I);
end;

procedure TPlateTracker.Feed(const Res: TPlateResults; Time: Double; ImgWidth: Integer;
  ImgHeight: Integer);
var
  R, I, Best, V, L: Integer;
  Score, BestScore, Ov: Single;
  Txt: string;
  Used: array of Boolean;
begin
  Expire(Time, False);
  SetLength(Used, Length(FTracks));
  for R := 0 to High(Res) do
  begin
    Txt := Res[R].Plate.Text;
    if (Length(Txt) < MinLength) or (Res[R].Plate.Confidence < MinConfidence) then
      Continue;
    if Assigned(Filter) and not Filter(Txt) then
      Continue;
    if (EdgeMargin > 0) and (ImgWidth > 0) and (ImgHeight > 0) then
      with Res[R].Box do
        if (X1 < EdgeMargin) or (Y1 < EdgeMargin) or
           (X2 > ImgWidth - EdgeMargin) or (Y2 > ImgHeight - EdgeMargin) then
          Continue;

    // find the track of the same car: overlapping box or nearly the same text
    Best := -1;
    BestScore := 0;
    for I := 0 to High(FTracks) do
    begin
      if Used[I] then
        Continue;
      Ov := IoU(Res[R].Box, FTracks[I].Box);
      L := Leader(FTracks[I]);
      Score := Ov;
      if (L >= 0) and (EditDistance(Txt, FTracks[I].Votes[L].Text) <= 2) then
        Score := Score + 1;
      if (Score > 0.1) and (Score > BestScore) then
      begin
        BestScore := Score;
        Best := I;
      end;
    end;
    if Best < 0 then
    begin
      SetLength(FTracks, Length(FTracks) + 1);
      Best := High(FTracks);
      FTracks[Best] := Default(TTrack);
      FTracks[Best].FirstTime := Time;
      SetLength(Used, Length(FTracks));
    end;
    Used[Best] := True;  // one reading per car per frame

    with FTracks[Best] do
    begin
      Inc(Frames);
      LastTime := Time;
      Box := Res[R].Box;
      V := -1;
      for I := 0 to High(Votes) do
        if Votes[I].Text = Txt then V := I;
      if V < 0 then
      begin
        SetLength(Votes, Length(Votes) + 1);
        V := High(Votes);
        Votes[V].Text := Txt;
        Votes[V].Count := 0;
        Votes[V].BestConf := 0;
      end;
      Inc(Votes[V].Count);
      Votes[V].BestConf := Max(Votes[V].BestConf, Res[R].Plate.Confidence);
    end;

    L := Leader(FTracks[Best]);
    if not FTracks[Best].Reported and (FTracks[Best].Votes[L].Count >= ConfirmVotes) then
      Report(FTracks[Best], True);
  end;
end;

procedure TPlateTracker.Flush;
begin
  Expire(0, True);
end;

end.
