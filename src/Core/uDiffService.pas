unit uDiffService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults, System.Types, JsonDataObjects, uSessionManager, uAgentTypes;

type
  TDiffService = class
  private
    FSessionMgr: TSessionManager;
    function FindSession(const ASessionId: string): TSessionInfo;
  public
    constructor Create(ASessionMgr: TSessionManager);
    
    // 모든 세션 목록 조회
    procedure LoadAllSessions(OnSuccess: TProc<TList<TSessionInfo>>);
    
    // 특정 세션 정보 조회
    procedure SelectSession(const ASessionId: string; OnSuccess: TProc<TSessionInfo>; OnError: TProc<string>);
    
    // 특정 세션의 정렬된 히스토리 메타데이터 조회
    procedure LoadDiffsFromSession(const ASessionId: string; OnSuccess: TProc<TJsonArray>; OnError: TProc<string>);
    
    // 특정 히스토리 상세 데이터 조회
    procedure LoadDiffDetail(const ASessionId, AHashId: string; ACompareToLatest: Boolean; OnSuccess: TProc<TJsonObject>; OnError: TProc<string>);

    // 파일 전체 롤백
    procedure Rollback(const ASessionId, AHashId: string; OnSuccess: TProc; OnError: TProc<string>);
    
    // 로컬 파일의 현재 내용 읽기
    function GetLocalFileContent(const AFilePath: string): string;
    
    // 부분 롤백 (블록 단위)
    procedure PartialRollback(const ASessionId, AHashId: string; ABlockIndex: Integer; OnSuccess: TProc; OnError: TProc<string>);
  end;

implementation

{ TDiffService }

constructor TDiffService.Create(ASessionMgr: TSessionManager);
begin
  FSessionMgr := ASessionMgr;
end;

function TDiffService.FindSession(const ASessionId: string): TSessionInfo;
var
  LSessions: TList<TSessionInfo>;
  LSession: TSessionInfo;
begin
  Result := nil;
  LSessions := FSessionMgr.GetSessionListSnapshot;
  try
    for LSession in LSessions do
      if LSession.SessionId = ASessionId then begin
        Result := LSession;
        Break;
      end;
  finally LSessions.Free; end;
end;

procedure TDiffService.LoadAllSessions(OnSuccess: TProc<TList<TSessionInfo>>);
begin
  if Assigned(OnSuccess) then
    OnSuccess(FSessionMgr.GetSessionListSnapshot);
end;

procedure TDiffService.SelectSession(const ASessionId: string; OnSuccess: TProc<TSessionInfo>; OnError: TProc<string>);
var
  LSession: TSessionInfo;
begin
  LSession := FindSession(ASessionId);
  if Assigned(LSession) then begin
    if Assigned(OnSuccess) then OnSuccess(LSession);
  end else begin
    if Assigned(OnError) then OnError('Session not found: ' + ASessionId);
  end;
end;

procedure TDiffService.LoadDiffsFromSession(const ASessionId: string; OnSuccess: TProc<TJsonArray>; OnError: TProc<string>);
var
  LTargetSession: TSessionInfo;
  LFiles: TStringDynArray;
  LPath, LJsonText: string;
  LObj: TJsonObject;
  LList: TList<TJsonObject>;
  I: Integer;
  LArray: TJsonArray;
begin
  LTargetSession := FindSession(ASessionId);
  if not Assigned(LTargetSession) then begin
    if Assigned(OnError) then OnError('Session not found');
    Exit;
  end;

  if (LTargetSession.DiffsPath = '') or not TDirectory.Exists(LTargetSession.DiffsPath) then begin
    if Assigned(OnSuccess) then OnSuccess(TJsonArray.Create);
    Exit;
  end;

  LArray := TJsonArray.Create;
  LList := TList<TJsonObject>.Create;
  try
    LFiles := TDirectory.GetFiles(LTargetSession.DiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
    for LPath in LFiles do
    begin
      try
        LJsonText := TFile.ReadAllText(LPath, TEncoding.UTF8);
        LObj := TJsonObject.Parse(LJsonText) as TJsonObject;
        if Assigned(LObj) then
        begin
          LObj.Remove('oldContent');
          LObj.Remove('newContent');
          LList.Add(LObj);
        end;
      except
      end;
    end;

    LList.Sort(TComparer<TJsonObject>.Construct(
      function(const Left, Right: TJsonObject): Integer
      begin
        Result := CompareText(Right.S['timestamp'], Left.S['timestamp']);
      end));

    for I := 0 to LList.Count - 1 do
      LArray.AddObject.Assign(LList[I]);
      
    if Assigned(OnSuccess) then OnSuccess(LArray) else LArray.Free;
  finally
    for I := 0 to LList.Count - 1 do LList[I].Free;
    LList.Free;
  end;
end;

procedure TDiffService.LoadDiffDetail(const ASessionId, AHashId: string; ACompareToLatest: Boolean; OnSuccess: TProc<TJsonObject>; OnError: TProc<string>);
var
  LTargetSession: TSessionInfo;
  LFiles: TStringDynArray;
  LFile, LJsonText: string;
  LObj: TJsonObject;
  LFound: Boolean;
begin
  LTargetSession := FindSession(ASessionId);
  if not Assigned(LTargetSession) or (LTargetSession.DiffsPath = '') or not TDirectory.Exists(LTargetSession.DiffsPath) then begin
    if Assigned(OnError) then OnError('Session or history path not found');
    Exit;
  end;

  LFound := False;
  LFiles := TDirectory.GetFiles(LTargetSession.DiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
  for LFile in LFiles do
  begin
    try
      LJsonText := TFile.ReadAllText(LFile, TEncoding.UTF8);
      LObj := TJsonObject.Parse(LJsonText) as TJsonObject;
      if Assigned(LObj) then
      begin
        if LObj.S['id'] = AHashId then
        begin
          if ACompareToLatest then
            LObj.S['newContent'] := GetLocalFileContent(LObj.S['path']);
            
          if Assigned(OnSuccess) then OnSuccess(LObj) else LObj.Free;
          LFound := True;
          Break;
        end;
        LObj.Free;
      end;
    except
    end;
  end;
  
  if not LFound and Assigned(OnError) then
    OnError('Diff history not found: ' + AHashId);
end;

function TDiffService.GetLocalFileContent(const AFilePath: string): string;
begin
  Result := '';
  if (AFilePath <> '') and TFile.Exists(AFilePath) then
  begin
    try
      Result := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    except
    end;
  end;
end;

procedure TDiffService.Rollback(const ASessionId, AHashId: string; OnSuccess: TProc; OnError: TProc<string>);
begin
  LoadDiffDetail(ASessionId, AHashId, False,
    procedure(AObj: TJsonObject)
    var
      LFilePath, LOldContent: string;
    begin
      try
        LFilePath := AObj.S['path'];
        LOldContent := AObj.S['oldContent'];
        if LFilePath <> '' then
        begin
          TFile.WriteAllText(LFilePath, LOldContent, TEncoding.UTF8);
          if Assigned(OnSuccess) then OnSuccess();
        end else begin
          if Assigned(OnError) then OnError('Invalid file path in history');
        end;
      finally
        AObj.Free;
      end;
    end,
    OnError
  );
end;

procedure TDiffService.PartialRollback(const ASessionId, AHashId: string; ABlockIndex: Integer; OnSuccess: TProc; OnError: TProc<string>);
begin
  Rollback(ASessionId, AHashId, OnSuccess, OnError);
end;

end.
