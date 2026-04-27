unit uFileService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Types, JsonDataObjects,
  System.Generics.Collections, System.Generics.Defaults, System.Hash, uAgentTypes, uSessionManager;

type
  TFileService = class
  private
    FSessionMgr: TSessionManager;
    function IsIgnoredDir(const ADirName: string): Boolean;
    function GetLocalTimeString: string;
  public
    constructor Create(ASessionMgr: TSessionManager = nil);

    // 파일 쓰기 및 히스토리 기록
    procedure WriteTextFile(const ASessionId, APath, AContent: string;
      OnSuccess: TProc;
      OnError: TProc<string>);

    // 파일 텍스트 읽기
    procedure ReadTextFile(const APath: string;
      OnSuccess: TProc<string>;
      OnError: TProc<string>);

    // 파일 내용 로드 (성공 시 파일명, 경로, JSON 인코딩된 내용을 콜백으로 전달)
    procedure LoadFile(const APath: string; 
      OnSuccess: TProc<string, string, string>; 
      OnError: TProc<string>);

    // 디렉토리 목록 조회 (성공 시 현재 경로와 JSON 목록을 콜백으로 전달)
    procedure GetDirectoryList(const APath: string;
      OnSuccess: TProc<string, TJsonObject>;
      OnError: TProc<string>);

    // 파일 프리뷰 내용 조회 (성공 시 내용과 확장자를 콜백으로 전달)
    procedure GetFilePreview(const APath: string;
      OnSuccess: TProc<string, string>;
      OnError: TProc<string>);

    // 파일 히스토리 조회 (diff 내역)
    procedure GetFileHistory(const ADiffsPath: string;
      OnSuccess: TProc<TJsonArray>;
      OnError: TProc<string>);

    // 워크스페이스 파일 목록 재귀 조회
    procedure GetWorkspaceFiles(const ARootPath: string;
      OnSuccess: TProc<TJsonArray>;
      OnError: TProc<string>);
  end;

implementation

{ TFileService }

constructor TFileService.Create(ASessionMgr: TSessionManager);
begin
  FSessionMgr := ASessionMgr;
end;

function TFileService.GetLocalTimeString: string;
var
  d: TDateTime;
begin
  d := Now;
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', d);
end;

procedure TFileService.WriteTextFile(const ASessionId, APath, AContent: string;
  OnSuccess: TProc;
  OnError: TProc<string>);
var
  LSession: TSessionInfo;
  LOldContent, LDiffPath, LHashId: string;
  LDiffObj: TJsonObject;
  LSessions: TList<TSessionInfo>;
  I: Integer;
begin
  LSession := nil;
  if not Assigned(FSessionMgr) then
  begin
    if Assigned(OnError) then OnError('Session Manager not initialized');
    Exit;
  end;

  LSessions := FSessionMgr.GetSessionListSnapshot;
  try
    for I := 0 to LSessions.Count - 1 do
      if SameText(LSessions[I].SessionId, ASessionId) then
      begin
        LSession := LSessions[I];
        Break;
      end;
  finally
    // List is freed later, but we need the session data
  end;

  if not Assigned(LSession) then
  begin
    if Assigned(OnError) then OnError('Session not found for file write: ' + ASessionId);
    LSessions.Free;
    Exit;
  end;

  try
    // 1. Get old content for diff
    LOldContent := '';
    if TFile.Exists(APath) then
      LOldContent := TFile.ReadAllText(APath, TEncoding.UTF8);

    // 2. Write new content
    TFile.WriteAllText(APath, AContent, TEncoding.UTF8);

    // 3. Record history (Diff)
    if (LSession.DiffsPath <> '') then
    begin
      TDirectory.CreateDirectory(LSession.DiffsPath);
      LHashId := LowerCase(Copy(THashMD5.GetHashString(AContent + FormatDateTime('yyyymmddhhnnsszzz', Now) + Random(999999).ToString), 1, 8));
      LDiffPath := TPath.Combine(LSession.DiffsPath, LHashId + '.json');
      
      LDiffObj := TJsonObject.Create;
      try
        LDiffObj.S['id'] := LHashId;
        LDiffObj.S['path'] := APath;
        LDiffObj.S['timestamp'] := GetLocalTimeString;
        LDiffObj.S['oldContent'] := LOldContent;
        LDiffObj.S['newContent'] := AContent;
        TFile.WriteAllText(LDiffPath, LDiffObj.ToJSON, TEncoding.UTF8);
      finally
        LDiffObj.Free;
      end;
    end;

    if Assigned(OnSuccess) then OnSuccess();
  except
    on E: Exception do
      if Assigned(OnError) then OnError('File write failed: ' + E.Message);
  end;
  LSessions.Free;
end;

procedure TFileService.ReadTextFile(const APath: string;
  OnSuccess: TProc<string>;
  OnError: TProc<string>);
var
  LContent: string;
begin
  if not TFile.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('File not found: ' + APath);
    Exit;
  end;

  try
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    if Assigned(OnSuccess) then OnSuccess(LContent);
  except
    on E: Exception do
      if Assigned(OnError) then OnError('Failed to read file: ' + E.Message);
  end;
end;

function FormatSize(ASize: Int64): string;
const
  K = 1024;
  M = K * K;
  G = M * K;
begin
  if ASize >= G then Result := Format('%.2f GB', [ASize / G])
  else if ASize >= M then Result := Format('%.2f MB', [ASize / M])
  else if ASize >= K then Result := Format('%.2f KB', [ASize / K])
  else Result := Format('%d B', [ASize]);
end;

function TFileService.IsIgnoredDir(const ADirName: string): Boolean;
const IGNORED: array[0..5] of string = ('.git', 'node_modules', '__history', '__recovery', '.gemini', 'Win32');
var S: string; begin Result := False; for S in IGNORED do if SameText(ADirName, S) then Exit(True); end;

procedure TFileService.LoadFile(const APath: string; 
  OnSuccess: TProc<string, string, string>; 
  OnError: TProc<string>);
var
  LContent, LFileName, LJsonContent: string;
begin
  if not TFile.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('File not found: ' + APath);
    Exit;
  end;

  try
    LFileName := TPath.GetFileName(APath);
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    
    // JSON 문자열로 안전하게 변환 (이스케이프 처리)
    LJsonContent := TJsonObject.Parse('"' + LContent.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '"').ToJSON;

    if Assigned(OnSuccess) then
      OnSuccess(LFileName, APath, LJsonContent);
  except
    on E: Exception do
    begin
      if Assigned(OnError) then OnError('Failed to read file: ' + E.Message);
    end;
  end;
end;

procedure TFileService.GetDirectoryList(const APath: string;
  OnSuccess: TProc<string, TJsonObject>;
  OnError: TProc<string>);
var
  LRootObj, LFileObj: TJsonObject;
  LFileArray: TJsonArray;
  LDirs, LFiles: TStringDynArray;
  S: string;
  LSize: Int64;
  LTime: TDateTime;
begin
  if not TDirectory.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('Directory not found: ' + APath);
    Exit;
  end;

  LRootObj := TJsonObject.Create;
  try
    LRootObj.S['currentPath'] := APath;
    LFileArray := LRootObj.A['files'];
    
    try
      LDirs := TDirectory.GetDirectories(APath);
      for S in LDirs do
      begin
        LFileObj := LFileArray.AddObject;
        LFileObj.S['name'] := TPath.GetFileName(S);
        LFileObj.S['path'] := S;
        LFileObj.B['isDir'] := True;
        LFileObj.S['date'] := DateTimeToStr(TDirectory.GetLastWriteTime(S));
        LFileObj.S['type'] := 'File folder';
      end;

      LFiles := TDirectory.GetFiles(APath);
      for S in LFiles do
      begin
        LFileObj := LFileArray.AddObject;
        LFileObj.S['name'] := TPath.GetFileName(S);
        LFileObj.S['path'] := S;
        LFileObj.B['isDir'] := False;
        LTime := TFile.GetLastWriteTime(S);
        LFileObj.S['date'] := DateTimeToStr(LTime);
        LFileObj.S['type'] := TPath.GetExtension(S).ToUpper.Replace('.', '') + ' File';
        try
          LSize := TFile.GetSize(S);
          LFileObj.S['size'] := FormatSize(LSize);
        except
          LFileObj.S['size'] := '0 B';
        end;
      end;

      if Assigned(OnSuccess) then OnSuccess(APath, LRootObj) else LRootObj.Free;
    except
      on E: Exception do
      begin
        LRootObj.Free;
        if Assigned(OnError) then OnError('Failed to list directory: ' + E.Message);
      end;
    end;
  finally
    // LRootObj is managed by OnSuccess or freed on error
  end;
end;

procedure TFileService.GetFilePreview(const APath: string;
  OnSuccess: TProc<string, string>;
  OnError: TProc<string>);
var
  LContent, LExt: string;
begin
  if not TFile.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('File not found for preview');
    Exit;
  end;

  try
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    LExt := TPath.GetExtension(APath).Replace('.', '').ToLower;
    if Assigned(OnSuccess) then OnSuccess(LContent, LExt);
  except
    on E: Exception do
    begin
      if Assigned(OnError) then OnError('Preview failed: ' + E.Message);
    end;
  end;
end;

procedure TFileService.GetFileHistory(const ADiffsPath: string;
  OnSuccess: TProc<TJsonArray>;
  OnError: TProc<string>);
var
  LFiles: TStringDynArray;
  LPath, LJsonText: string;
  LArray: TJsonArray;
  LObj, LItem: TJsonObject;
  LList: TList<TJsonObject>;
  I: Integer;
begin
  if not TDirectory.Exists(ADiffsPath) then
  begin
    if Assigned(OnSuccess) then OnSuccess(TJsonArray.Create);
    Exit;
  end;

  LArray := TJsonArray.Create;
  LList := TList<TJsonObject>.Create;
  try
    LFiles := TDirectory.GetFiles(ADiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
    for LPath in LFiles do
    begin
      try
        LJsonText := TFile.ReadAllText(LPath, TEncoding.UTF8);
        LObj := TJsonObject.Parse(LJsonText) as TJsonObject;
        if Assigned(LObj) then LList.Add(LObj);
      except
        // Skip invalid files
      end;
    end;

    LList.Sort(TComparer<TJsonObject>.Construct(
      function(const Left, Right: TJsonObject): Integer
      begin
        Result := CompareText(Right.S['timestamp'], Left.S['timestamp']);
      end));

    for I := 0 to LList.Count - 1 do
    begin
      LItem := LArray.AddObject;
      LItem.Assign(LList[I]);
    end;

    if Assigned(OnSuccess) then OnSuccess(LArray) else LArray.Free;
  finally
    for I := 0 to LList.Count - 1 do LList[I].Free;
    LList.Free;
  end;
end;

procedure TFileService.GetWorkspaceFiles(const ARootPath: string;
  OnSuccess: TProc<TJsonArray>;
  OnError: TProc<string>);
var
  LArray: TJsonArray;
  LTargetRoot: string;

  procedure ScanDir(const ADir: string);
  var
    LFile, LSubDir: string;
    LRelPath: string;
  begin
    try
      for LFile in TDirectory.GetFiles(ADir) do
      begin
        LRelPath := ExtractRelativePath(LTargetRoot, LFile);
        LArray.Add(LRelPath.Replace('\', '/'));
      end;

      for LSubDir in TDirectory.GetDirectories(ADir) do
      begin
        if not IsIgnoredDir(TPath.GetFileName(LSubDir)) then
          ScanDir(LSubDir);
      end;
    except
    end;
  end;

begin
  if not TDirectory.Exists(ARootPath) then
  begin
    if Assigned(OnError) then OnError('Workspace root not found: ' + ARootPath);
    Exit;
  end;

  LTargetRoot := IncludeTrailingPathDelimiter(ARootPath);
  LArray := TJsonArray.Create;
  try
    ScanDir(ExcludeTrailingPathDelimiter(LTargetRoot));
    if Assigned(OnSuccess) then OnSuccess(LArray) else LArray.Free;
  except
    on E: Exception do
    begin
      LArray.Free;
      if Assigned(OnError) then OnError('Workspace scan failed: ' + E.Message);
    end;
  end;
end;

end.
