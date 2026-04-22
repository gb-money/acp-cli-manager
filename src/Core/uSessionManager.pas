unit uSessionManager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uACPAgent, System.IOUtils,
  JsonDataObjects, System.SyncObjs, uAgentTypes, System.Generics.Defaults, System.DateUtils;

type
  TSessionRestoredEvent = procedure(Sender: TObject; ASession: TSessionInfo) of object;

  TSessionManager = class
  private
    FSessions: TObjectList<TSessionInfo>;
    FActiveSession: TSessionInfo;
    FLock: TCriticalSection;
    FWatchdogTerminated: Boolean;
    FOnSessionRestored: TSessionRestoredEvent;
    function GetBaseConfigPath: string;
    procedure StartWatchdog;
  public
    constructor Create;
    destructor Destroy; override;

    function AddSession(AAgent: TACPAgent; AType: TAgentType; const ASessionId, AName: string; const ACwd: string = ''): TSessionInfo;
    procedure FinalizeSessionId(ASession: TSessionInfo; const ANewId: string);
    procedure DeleteSession(ASession: TSessionInfo);
    procedure SelectSession(ASession: TSessionInfo);
    procedure EnsureDirectoryStructure;
    function GetUniqueSessionName(const ABaseName: string): string;
    procedure SortSessions;
    procedure RecordActivity(const ASessionId: string);
    function GetSessionById(const ASessionId: string): TSessionInfo;
    function GetPendingSessionByAgent(AAgent: TACPAgent): TSessionInfo;

    procedure Lock;
    procedure Unlock;

    function GetSessionListSnapshot: TList<TSessionInfo>;

    property Sessions: TObjectList<TSessionInfo> read FSessions;
    property ActiveSession: TSessionInfo read FActiveSession;
    property BaseConfigPath: string read GetBaseConfigPath;
    property OnSessionRestored: TSessionRestoredEvent read FOnSessionRestored write FOnSessionRestored;
  end;

implementation

{ TSessionManager }

constructor TSessionManager.Create;
begin
  FSessions := TObjectList<TSessionInfo>.Create(True);
  FLock := TCriticalSection.Create;
  FWatchdogTerminated := False;
  EnsureDirectoryStructure;
  StartWatchdog;
end;

destructor TSessionManager.Destroy;
begin
  FWatchdogTerminated := True;
  FActiveSession := nil;
  FSessions.Free;
  FLock.Free;
  inherited;
end;

function TSessionManager.GetBaseConfigPath: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('USERPROFILE'), '.acp-cli-manager');
end;

procedure TSessionManager.StartWatchdog;
begin
  TThread.CreateAnonymousThread(procedure
  var
    I: Integer;
    LSession: TSessionInfo;
    LNow: Cardinal;
  begin
    while not FWatchdogTerminated do
    begin
      TThread.Sleep(5000);
      LNow := TThread.GetTickCount;
      Lock;
      try
        for I := 0 to Sessions.Count - 1 do
        begin
          LSession := Sessions[I];
          if LSession.IsActive and (LSession.LastHistoryTick > 0) then
          begin
            if (LNow - LSession.LastHistoryTick) > 300000 then // 5 minutes
            begin
              LSession.IsActive := False;
              // Event could be fired here if needed
            end;
          end;
        end;
      finally
        Unlock;
      end;
    end;
  end).Start;
end;

function TSessionManager.AddSession(AAgent: TACPAgent; AType: TAgentType; const ASessionId, AName, ACwd: string): TSessionInfo;
var
  LSessionDir: string;
begin
  Result := TSessionInfo.Create(AAgent, AAgent.AgentName, AType, ASessionId, AName, ACwd);

  if not ASessionId.StartsWith('pending-') then begin
    LSessionDir := TPath.Combine(BaseConfigPath, 'sessions');
    LSessionDir := TPath.Combine(LSessionDir, AAgent.AgentName.ToLower + '-cli');
    LSessionDir := TPath.Combine(LSessionDir, ASessionId);

    if not TDirectory.Exists(LSessionDir) then
      TDirectory.CreateDirectory(LSessionDir);

    Result.LogPath := TPath.Combine(LSessionDir, 'history.json');
    Result.DiffsPath := TPath.Combine(LSessionDir, 'diffs');
    
    if not TDirectory.Exists(Result.DiffsPath) then
      TDirectory.CreateDirectory(Result.DiffsPath);
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
  LOldDir, LNewDir, LParent: string;
begin
  if not Assigned(ASession) or not ASession.SessionId.StartsWith('pending-') then Exit;

  LParent := TPath.Combine(BaseConfigPath, 'sessions');
  LParent := TPath.Combine(LParent, ASession.AgentName.ToLower + '-cli');
  
  LOldDir := TPath.Combine(LParent, ASession.SessionId);
  LNewDir := TPath.Combine(LParent, ANewId);

  ASession.SessionId := ANewId;
  ASession.LogPath := TPath.Combine(LNewDir, 'history.json');
  ASession.DiffsPath := TPath.Combine(LNewDir, 'diffs');

  if TDirectory.Exists(LOldDir) then
  begin
    if TDirectory.Exists(LNewDir) then
      TDirectory.Delete(LNewDir, True);
    TDirectory.Move(LOldDir, LNewDir);
  end
  else if not TDirectory.Exists(LNewDir) then
    TDirectory.CreateDirectory(LNewDir);
    
  if not TDirectory.Exists(ASession.DiffsPath) then
    TDirectory.CreateDirectory(ASession.DiffsPath);

  ASession.SaveMetadata;
end;

procedure TSessionManager.DeleteSession(ASession: TSessionInfo);
var
  LDir: string;
begin
  if not Assigned(ASession) then Exit;

  LDir := TPath.Combine(BaseConfigPath, 'sessions');
  LDir := TPath.Combine(LDir, ASession.AgentName.ToLower + '-cli');
  LDir := TPath.Combine(LDir, ASession.SessionId);

  if TDirectory.Exists(LDir) then
  begin
    try
      TDirectory.Delete(LDir, True);
    except
    end;
  end;

  Lock;
  try
    if FActiveSession = ASession then
      FActiveSession := nil;
    FSessions.Remove(ASession);
  finally
    Unlock;
  end;
end;

procedure TSessionManager.SelectSession(ASession: TSessionInfo);
begin
  FActiveSession := ASession;
end;

procedure TSessionManager.EnsureDirectoryStructure;
var
  LRoot: string;
begin
  LRoot := BaseConfigPath;
  try
    if not TDirectory.Exists(LRoot) then
      TDirectory.CreateDirectory(LRoot);
    if not TDirectory.Exists(TPath.Combine(LRoot, 'sessions')) then
      TDirectory.CreateDirectory(TPath.Combine(LRoot, 'sessions'));
    if not TDirectory.Exists(TPath.Combine(LRoot, 'images')) then
      TDirectory.CreateDirectory(TPath.Combine(LRoot, 'images'));
  except
    on E: Exception do;
  end;
end;

function TSessionManager.GetUniqueSessionName(const ABaseName: string): string;
var
  LName: string;
  LIdx: Integer;
  LFound: Boolean;
  LSession: TSessionInfo;
begin
  LIdx := 1;
  while True do
  begin
    if LIdx = 1 then LName := ABaseName else LName := Format('%s %d', [ABaseName, LIdx]);
    LFound := False;
    Lock;
    try
      for LSession in FSessions do
        if SameText(LSession.Name, LName) then begin
          LFound := True;
          Break;
        end;
    finally
      Unlock;
    end;
    if not LFound then Exit(LName);
    Inc(LIdx);
  end;
end;

procedure TSessionManager.SortSessions;
begin
  Lock;
  try
    FSessions.Sort(TComparer<TSessionInfo>.Construct(
      function(const Left, Right: TSessionInfo): Integer
      begin
        if Left.IsPinned <> Right.IsPinned then
          Result := Ord(Right.IsPinned) - Ord(Left.IsPinned)
        else if (Left.LastConversationDate <> 0) and (Right.LastConversationDate <> 0) then
          Result := CompareDateTime(Right.LastConversationDate, Left.LastConversationDate)
        else if (Left.LastConversationDate <> 0) then
          Result := -1
        else if (Right.LastConversationDate <> 0) then
          Result := 1
        else
          Result := CompareDateTime(Right.CreatedAt, Left.CreatedAt);
      end));
  finally
    Unlock;
  end;
end;

procedure TSessionManager.RecordActivity(const ASessionId: string);
var
  LSession: TSessionInfo;
begin
  LSession := GetSessionById(ASessionId);
  if Assigned(LSession) then
    LSession.MarkActivity;
end;

function TSessionManager.GetSessionById(const ASessionId: string): TSessionInfo;
var
  LSession: TSessionInfo;
begin
  Result := nil;
  Lock;
  try
    for LSession in FSessions do
      if LSession.SessionId = ASessionId then
      begin
        Result := LSession;
        Break;
      end;
  finally
    Unlock;
  end;
end;

function TSessionManager.GetPendingSessionByAgent(AAgent: TACPAgent): TSessionInfo;
var
  LSession: TSessionInfo;
begin
  Result := nil;
  Lock;
  try
    for LSession in FSessions do
      if (LSession.Agent = AAgent) and LSession.SessionId.StartsWith('pending-') then
      begin
        Result := LSession;
        Break;
      end;
  finally
    Unlock;
  end;
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

end.
