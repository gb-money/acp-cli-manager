unit uSessionManager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uAgent, System.IOUtils, 
  JsonDataObjects, System.SyncObjs;

type
  TSessionInfo = class
  public
    Agent: TAgent;
    SessionId: string;
    Name: string;
    IsLoading: Boolean;
    IsPinned: Boolean;
    LogPath: string;
    DiffsPath: string; // Directory for diff blocks
    Cwd: string; // Workspace directory
    constructor Create(AAgent: TAgent; const ASessionId, AName: string; const ACwd: string = '');
    procedure SaveMetadata;
    procedure LoadMetadata;
  end;

  TSessionManager = class
  private
    FSessions: TObjectList<TSessionInfo>;
    FActiveSession: TSessionInfo;
    FLock: TCriticalSection;
    function GetBaseConfigPath: string;
  public
    constructor Create;
    destructor Destroy; override;
    
    function AddSession(AAgent: TAgent; const ASessionId, AName: string; const ACwd: string = ''): TSessionInfo;
    procedure FinalizeSessionId(ASession: TSessionInfo; const ANewId: string);
    procedure DeleteSession(ASession: TSessionInfo);
    procedure SelectSession(ASession: TSessionInfo);
    procedure EnsureDirectoryStructure;
    function GetUniqueSessionName(const ABaseName: string): string;
    
    procedure Lock;
    procedure Unlock;
    
    // 안전한 스냅샷 리스트 반환 (for in 루프 안전성 확보)
    function GetSessionListSnapshot: TList<TSessionInfo>;
    
    property Sessions: TObjectList<TSessionInfo> read FSessions;
    property ActiveSession: TSessionInfo read FActiveSession;
    property BaseConfigPath: string read GetBaseConfigPath;
  end;

implementation

{ TSessionInfo }

constructor TSessionInfo.Create(AAgent: TAgent; const ASessionId, AName: string; const ACwd: string);
begin
  Agent := AAgent;
  SessionId := ASessionId;
  Name := AName;
  Cwd := ACwd;
  IsLoading := False;
  IsPinned := False;
end;

procedure TSessionInfo.SaveMetadata;
var
  LDir, LFile, LHome: string;
  LObj: TJsonObject;
begin
  if SessionId.StartsWith('pending-') then Exit;
  
  LHome := GetEnvironmentVariable('USERPROFILE');
  if LHome = '' then LHome := TPath.GetHomePath;
  LDir := TPath.Combine(TPath.Combine(LHome, '.acp-cli-manager'), 'sessions');
  LDir := TPath.Combine(LDir, Agent.AgentName.ToLower + '-cli');
  LDir := TPath.Combine(LDir, SessionId);
  
  if not TDirectory.Exists(LDir) then TDirectory.CreateDirectory(LDir);
  
  LFile := TPath.Combine(LDir, 'metadata.json');
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := SessionId;
    LObj.S['name'] := Name;
    LObj.S['cwd'] := Cwd;
    LObj.B['pinned'] := IsPinned;
    LObj.SaveToFile(LFile);
  finally
    LObj.Free;
  end;
end;

procedure TSessionInfo.LoadMetadata;
var
  LDir, LFile, LHome: string;
  LObj: TJsonObject;
begin
  if SessionId.StartsWith('pending-') then Exit;
  
  LHome := GetEnvironmentVariable('USERPROFILE');
  if LHome = '' then LHome := TPath.GetHomePath;
  LDir := TPath.Combine(TPath.Combine(LHome, '.acp-cli-manager'), 'sessions');
  LDir := TPath.Combine(LDir, Agent.AgentName.ToLower + '-cli');
  LDir := TPath.Combine(LDir, SessionId);
  
  LFile := TPath.Combine(LDir, 'metadata.json');
  if not TFile.Exists(LFile) then Exit;
  
  LObj := TJsonObject.Create;
  try
    LObj.LoadFromFile(LFile);
    Name := LObj.S['name'];
    Cwd := LObj.S['cwd'];
    IsPinned := LObj.B['pinned'];
  finally
    LObj.Free;
  end;
end;

{ TSessionManager }

constructor TSessionManager.Create;
begin
  FLock := TCriticalSection.Create;
  FSessions := TObjectList<TSessionInfo>.Create(True);
  FActiveSession := nil;
  EnsureDirectoryStructure;
end;

destructor TSessionManager.Destroy;
begin
  FSessions.Free;
  FLock.Free;
  inherited;
end;

procedure TSessionManager.Lock;
begin
  FLock.Enter;
end;

procedure TSessionManager.Unlock;
begin
  FLock.Leave;
end;

function TSessionManager.GetSessionListSnapshot: TList<TSessionInfo>;
var
  LSession: TSessionInfo;
begin
  Result := TList<TSessionInfo>.Create;
  Lock;
  try
    for LSession in FSessions do
      Result.Add(LSession);
  finally
    Unlock;
  end;
end;

function TSessionManager.GetBaseConfigPath: string;
var
  LHome: string;
begin
  LHome := GetEnvironmentVariable('USERPROFILE');
  if LHome = '' then LHome := TPath.GetHomePath;
  Result := TPath.Combine(LHome, '.acp-cli-manager');
end;

procedure TSessionManager.EnsureDirectoryStructure;
var
  LRoot: string;
begin
  LRoot := BaseConfigPath;
  try
    if not TDirectory.Exists(LRoot) then TDirectory.CreateDirectory(LRoot);
    if not TDirectory.Exists(TPath.Combine(LRoot, 'sessions')) then TDirectory.CreateDirectory(TPath.Combine(LRoot, 'sessions'));
    if not TDirectory.Exists(TPath.Combine(LRoot, 'images')) then TDirectory.CreateDirectory(TPath.Combine(LRoot, 'images'));
  except
    on E: Exception do ;
  end;
end;

function TSessionManager.AddSession(AAgent: TAgent; const ASessionId, AName, ACwd: string): TSessionInfo;
var
  LSessionDir: string;
begin
  Result := TSessionInfo.Create(AAgent, ASessionId, AName, ACwd);
  
  if not ASessionId.StartsWith('pending-') then
  begin
    LSessionDir := TPath.Combine(BaseConfigPath, 'sessions');
    LSessionDir := TPath.Combine(LSessionDir, AAgent.AgentName.ToLower + '-cli');
    LSessionDir := TPath.Combine(LSessionDir, ASessionId);
    
    if not TDirectory.Exists(LSessionDir) then
      TDirectory.CreateDirectory(LSessionDir);
      
    Result.LogPath := TPath.Combine(LSessionDir, 'history.json');
    Result.DiffsPath := TPath.Combine(LSessionDir, 'diffs');
    if not TDirectory.Exists(Result.DiffsPath) then
      TDirectory.CreateDirectory(Result.DiffsPath);
    Result.LoadMetadata; 
  end
  else
  begin
    Result.LogPath := '';
    Result.DiffsPath := '';
  end;
    
  Lock;
  try
    FSessions.Add(Result);
  finally
    Unlock;
  end;
end;

procedure TSessionManager.FinalizeSessionId(ASession: TSessionInfo; const ANewId: string);
var
  LSessionDir: string;
begin
  Lock;
  try
    ASession.SessionId := ANewId;
    LSessionDir := TPath.Combine(BaseConfigPath, 'sessions');
    LSessionDir := TPath.Combine(LSessionDir, ASession.Agent.AgentName.ToLower + '-cli');
    LSessionDir := TPath.Combine(LSessionDir, ANewId);
    
    if not TDirectory.Exists(LSessionDir) then
      TDirectory.CreateDirectory(LSessionDir);
      
    ASession.LogPath := TPath.Combine(LSessionDir, 'history.json');
    ASession.SaveMetadata;
  finally
    Unlock;
  end;
end;

procedure TSessionManager.DeleteSession(ASession: TSessionInfo);
begin
  Lock;
  try
    if FActiveSession = ASession then FActiveSession := nil;
    FSessions.Remove(ASession);
  finally
    Unlock;
  end;
end;

procedure TSessionManager.SelectSession(ASession: TSessionInfo);
begin
  Lock;
  try
    FActiveSession := ASession;
  finally
    Unlock;
  end;
end;

function TSessionManager.GetUniqueSessionName(const ABaseName: string): string;
var
  LName: string;
  LIndex: Integer;
  LFound: Boolean;
  LSession: TSessionInfo;
begin
  LName := ABaseName;
  LIndex := 1;
  
  repeat
    LFound := False;
    Lock;
    try
      for LSession in FSessions do
      begin
        if SameText(LSession.Name, LName) then
        begin
          LFound := True;
          Break;
        end;
      end;
    finally
      Unlock;
    end;
    
    if LFound then
    begin
      Inc(LIndex);
      LName := ABaseName + ' ' + IntToStr(LIndex);
    end;
  until not LFound;
  
  Result := LName;
end;

end.
