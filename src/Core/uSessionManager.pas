unit uSessionManager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uAgent, System.IOUtils,
  JsonDataObjects, System.SyncObjs, uAgentTypes;

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

    function AddSession(AAgent: TAgent; AType: TAgentType; const ASessionId, AName: string; const ACwd: string = ''): TSessionInfo;
    procedure FinalizeSessionId(ASession: TSessionInfo; const ANewId: string);
    procedure DeleteSession(ASession: TSessionInfo);
    procedure SelectSession(ASession: TSessionInfo);
    procedure EnsureDirectoryStructure;
    function GetUniqueSessionName(const ABaseName: string): string;
    procedure SortSessions;
    procedure RecordActivity(const ASessionId: string);
    function GetSessionById(const ASessionId: string): TSessionInfo;

    procedure Lock;
    procedure Unlock;

    function GetSessionListSnapshot: TList<TSessionInfo>;

    property Sessions: TObjectList<TSessionInfo> read FSessions;
    property ActiveSession: TSessionInfo read FActiveSession;
    property BaseConfigPath: string read GetBaseConfigPath;
    property OnSessionRestored: TSessionRestoredEvent read FOnSessionRestored write FOnSessionRestored;
  end;

implementation

uses
  System.Generics.Defaults;

{ TSessionManager }

constructor TSessionManager.Create;
begin
  FLock := TCriticalSection.Create;
  FSessions := TObjectList<TSessionInfo>.Create(True);
  FActiveSession := nil;
  FWatchdogTerminated := False;
  EnsureDirectoryStructure;
  StartWatchdog;
end;

destructor TSessionManager.Destroy;
begin
  FWatchdogTerminated := True;
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

procedure TSessionManager.StartWatchdog;
var
  LManager: TSessionManager;
begin
  LManager := Self;
  TThread.CreateAnonymousThread(
    procedure
    var
      LSession: TSessionInfo;
      LNow: Cardinal;
      LTimedOutSessions: TList<TSessionInfo>;
      LS: TSessionInfo;
    begin
      while not LManager.FWatchdogTerminated do begin
        Sleep(500);
        LTimedOutSessions := TList<TSessionInfo>.Create;
        try
          LNow := TThread.GetTickCount;
          LManager.Lock;
          try
            for LSession in LManager.FSessions do begin
              if LSession.IsLoading and (LSession.LastHistoryTick > 0) then begin
                if (LNow - LSession.LastHistoryTick) > 10000 then // 10s
                  LTimedOutSessions.Add(LSession);
              end;
            end;
          finally
            LManager.Unlock;
          end;

          for LS in LTimedOutSessions do begin
            LS.IsLoading := False;
            LS.IsActive := True;
            LS.LastHistoryTick := 0;
            if Assigned(LManager.FOnSessionRestored) then begin
              var
              LCapturedSession := LS;
              TThread.Queue(nil,
                TThreadProcedure(procedure
                begin
                  if Assigned(LManager.FOnSessionRestored) then
                    LManager.FOnSessionRestored(LManager, LCapturedSession);
                end));
            end;
          end;
        finally
          LTimedOutSessions.Free;
        end;
      end;
    end).Start;
end;

function TSessionManager.GetSessionById(const ASessionId: string): TSessionInfo;
var
  LSession: TSessionInfo;
begin
  Result := nil;
  Lock;
  try
    for LSession in FSessions do
      if LSession.SessionId = ASessionId then begin
        Result := LSession;
        Break;
      end;
  finally
    Unlock;
  end;
end;

procedure TSessionManager.RecordActivity(const ASessionId: string);
var
  LSession: TSessionInfo;
begin
  Lock;
  try
    for LSession in FSessions do
      if LSession.SessionId = ASessionId then begin
        LSession.MarkActivity;
        Break;
      end;
  finally
    Unlock;
  end;
end;

procedure TSessionManager.SortSessions;
begin
  Lock;
  try
    FSessions.Sort(TComparer<TSessionInfo>.Construct(
      function(const Left, Right: TSessionInfo): Integer
      begin
        // Pinned sessions first
        if Left.IsPinned <> Right.IsPinned then begin
          if Left.IsPinned then
            Result := -1
          else
            Result := 1;
        end
        else begin
          // Descending by LastConversationDate
          if Left.LastConversationDate > Right.LastConversationDate then
            Result := -1
          else if Left.LastConversationDate < Right.LastConversationDate then
            Result := 1
          else
            Result := 0;
        end;
      end));
  finally
    Unlock;
  end;
end;

function TSessionManager.GetSessionListSnapshot: TList<TSessionInfo>;
var
  LSession: TSessionInfo;
begin
  Result := TList<TSessionInfo>.Create;
  Lock;
  try
    SortSessions; // Sort before returning snapshot
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
  if LHome = '' then
    LHome := TPath.GetHomePath;
  Result := TPath.Combine(LHome, '.acp-cli-manager');
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

function TSessionManager.AddSession(AAgent: TAgent; AType: TAgentType; const ASessionId, AName, ACwd: string): TSessionInfo;
var
  LSessionDir: string;
begin
  Result := TSessionInfo.Create(AAgent, AType, ASessionId, AName, ACwd);

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
    Result.LoadMetadata;
  end
  else begin
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
var
  LSessionDir: string;
begin
  if ASession = nil then
    Exit;

  // 1. Determine session directory path
  LSessionDir := TPath.Combine(BaseConfigPath, 'sessions');
  LSessionDir := TPath.Combine(LSessionDir, ASession.Agent.AgentName.ToLower + '-cli');
  LSessionDir := TPath.Combine(LSessionDir, ASession.SessionId);

  // 2. Remove from memory
  Lock;
  try
    if FActiveSession = ASession then
      FActiveSession := nil;
    FSessions.Remove(ASession);
  finally
    Unlock;
  end;

  // 3. Delete from disk
  try
    if TDirectory.Exists(LSessionDir) then
      TDirectory.Delete(LSessionDir, True);
  except
    on E: Exception do; // Silently fail if directory is locked or already deleted
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
      for LSession in FSessions do begin
        if SameText(LSession.Name, LName) then begin
          LFound := True;
          Break;
        end;
      end;
    finally
      Unlock;
    end;

    if LFound then begin
      Inc(LIndex);
      LName := ABaseName + ' ' + IntToStr(LIndex);
    end;
  until not LFound;

  Result := LName;
end;

end.
