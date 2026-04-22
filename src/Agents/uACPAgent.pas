unit uACPAgent;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.IOUtils,
  JsonDataObjects, uACPClient, uAgentTypes;

type
  TACPAgent = class;

  TMethodHandler = procedure(const ID: string; Params: TJsonObject) of object;

  TSessionInfo = class
  public
    Agent: TACPAgent;
    AgentType: TAgentType;
    SessionId: string;
    Name: string;
    IsLoading: Boolean;
    IsRestoring: Boolean;
    IsActive: Boolean;
    IsWaitForResponse: Boolean;
    IsPinned: Boolean;
    IsThoughtStreaming: Boolean;
    IsMessageStreaming: Boolean;
    LogPath: string;
    DiffsPath: string; // Directory for diff blocks
    Cwd: string; // Workspace directory
    CreatedAt: TDateTime;
    LastConversationDate: TDateTime;
    LastHistoryTick: Cardinal; // Last time a history chunk was received
    constructor Create(AAgent: TACPAgent; AType: TAgentType; const ASessionId, AName: string; const ACwd: string = '');
    procedure SaveMetadata;
    procedure LoadMetadata;
    procedure MarkActivity;
    procedure UpdateConversationDate;
  end;

  TSessionData = record
    FullThought: string;
    FullMessage: string;
    CommandsJson: string;
    ModelsJson: string;
    ModesJson: string;
    CurrentBlockText: string;
    LastChunkType: string;
    IsRestoring: Boolean;
    IsProcessing: Boolean;
  end;

  TACPAgent = class(TComponent)
  private
    FAgentName: string;
    FAgentType: TAgentType;
    FState: TAgentState;
    FWorkspace: string;
    FACPClient: TACPClient;
    FSessionMgr: TObject; // Injected Manager (Type erased to break circular reference)
    FSessions: TDictionary<string, TSessionData>;
    FMethodHandlers: TDictionary<string, TMethodHandler>;

    FOnEndTurn: TAgentEndTurnEvent;
    FOnMessageChunk: TAgentChunkEvent;
    FOnThoughtChunk: TAgentChunkEvent;
    FOnStreamingEnd: TAgentStreamingEndEvent;
    FOnFSWrite: TAgentFSWriteEvent;
    FOnRawData: TAgentRPCEvent;
    FOnPermissionRequest: TAgentPermissionRequestEvent;
    FOnSessionMetadataUpdate: TSessionMetadataUpdateEvent;
    FOnPropertyUpdate: TSessionPropertyUpdateEvent;
    FOnNewSession: TNewSessionEvent;
    FOnSessionResumed: TSessionResumedEvent;

    procedure SetState(const Value: TAgentState);
    procedure HandleInternalReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
    procedure HandleInternalRawData(Sender: TObject; Direction: TRPCDirection; const RawText: string);
    procedure HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);

    procedure HandleFSRead(const ID: string; Params: TJsonObject);
    procedure HandleFSWrite(const ID: string; Params: TJsonObject);
    procedure HandleRequestPermission(const ID: string; Params: TJsonObject);
    procedure HandleSessionUpdate(const ID: string; Params: TJsonObject);
    procedure HandleToolCall(const ID: string; Params: TJsonObject);
    
    // session/update helper methods
    procedure ProcessAvailableCommandsUpdate(const SessionId: string; UpdateObj: TJsonObject; LSession: TSessionInfo);
    procedure ProcessChunkUpdate(const SessionId: string; UpdateType: string; UpdateObj: TJsonObject; LSession: TSessionInfo);
    procedure ProcessToolCallUpdate(const SessionId: string; UpdateObj: TJsonObject);
    procedure ProcessModelsUpdate(const SessionId: string; UpdateObj: TJsonObject);
    procedure ProcessModesUpdate(const SessionId: string; UpdateObj: TJsonObject);

    procedure ResetGrouping(const ASessionId: string);
    function GetIsConnected: Boolean;
  protected
    procedure RegisterHandlers; virtual;
    function FindSessionById(const ASessionId: string): TSessionInfo;
    function GetSessionList: TArray<string>; virtual;
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); virtual;
    
    procedure DoEndTurn(const SessionId, StopReason: string); virtual;
    procedure DoMessageChunk(const SessionId, Chunk, FullText: string);
    procedure DoThoughtChunk(const SessionId, Chunk, FullText: string);
    procedure DoStreamingEnd(const SessionId, AType: string);
    procedure DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
    procedure DoNewSession(AResponse: TJsonObject); virtual;
    procedure DoSessionResumed(const SessionId: string); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Connect; virtual;
    function Start(const ACommandLine: string = ''): Boolean; virtual;
    procedure Stop; virtual;
    procedure SendPrompt(const SessionId, AText: string); virtual; abstract;
    procedure Initialize(AParams: TJsonObject = nil); virtual; abstract;
    procedure NewSession(AParams: TJsonObject; OnResponse: TACPResponseAnonCallback = nil; OnCondition: TACPResponseCondition = nil); virtual;
    procedure ResumeSession(const SessionId: string); virtual;
    procedure EndTurn(const SessionId, StopReason: string); virtual;
    procedure UpdateSession(ASession: TSessionInfo); virtual;

    procedure ReplyPermission(const ID, SessionId, OptionId: string);
    procedure SetSessionLogPath(const SessionId, APath: string);
    procedure StartRestoration(const SessionId: string);
    procedure FinalizeRestoration(const SessionId: string);
    function IsRestoringSession(const SessionId: string): Boolean;

    procedure HandleModes(const ASessionId: string; AModes: TJsonObject);
    procedure HandleModels(const ASessionId: string; AModels: TJsonObject);

    procedure LoadSession(const SessionId: string; ACallback: TProc<string>); virtual; abstract;

    property AgentName: string read FAgentName write FAgentName;
    property AgentType: TAgentType read FAgentType write FAgentType;
    property State: TAgentState read FState write SetState;
    property Workspace: string read FWorkspace write FWorkspace;
    property SessionList: TArray<string> read GetSessionList;
    property ACPClient: TACPClient read FACPClient;
    property SessionManager: TObject read FSessionMgr write FSessionMgr;
    property Sessions: TDictionary<string, TSessionData> read FSessions;
    property IsConnected: Boolean read GetIsConnected;

    property OnEndTurn: TAgentEndTurnEvent read FOnEndTurn write FOnEndTurn;
    property OnMessageChunk: TAgentChunkEvent read FOnMessageChunk write FOnMessageChunk;
    property OnThoughtChunk: TAgentChunkEvent read FOnThoughtChunk write FOnThoughtChunk;
    property OnStreamingEnd: TAgentStreamingEndEvent read FOnStreamingEnd write FOnStreamingEnd;
    property OnFSWrite: TAgentFSWriteEvent read FOnFSWrite write FOnFSWrite;
    property OnRawData: TAgentRPCEvent read FOnRawData write FOnRawData;
    property OnPermissionRequest: TAgentPermissionRequestEvent read FOnPermissionRequest write FOnPermissionRequest;
    property OnSessionMetadataUpdate: TSessionMetadataUpdateEvent read FOnSessionMetadataUpdate write FOnSessionMetadataUpdate;
    property OnPropertyUpdate: TSessionPropertyUpdateEvent read FOnPropertyUpdate write FOnPropertyUpdate;
    property OnNewSession: TNewSessionEvent read FOnNewSession write FOnNewSession;
    property OnSessionResumed: TSessionResumedEvent read FOnSessionResumed write FOnSessionResumed;
  end;

implementation

uses
  uACPProtocol, uSessionManager;

{ TSessionInfo }

constructor TSessionInfo.Create(AAgent: TACPAgent; AType: TAgentType; const ASessionId, AName: string; const ACwd: string);
begin
  Agent := AAgent;
  AgentType := AType;
  SessionId := ASessionId;
  Name := AName;
  Cwd := ACwd;
  IsLoading := False;
  IsActive := False;
  IsPinned := False;
  CreatedAt := Now;
  LastConversationDate := 0; 
  LastHistoryTick := 0;
end;

procedure TSessionInfo.MarkActivity;
begin
  LastHistoryTick := TThread.GetTickCount;
end;

procedure TSessionInfo.UpdateConversationDate;
begin
  LastConversationDate := Now;
  SaveMetadata;
end;

procedure TSessionInfo.SaveMetadata;
var
  LDir, LFile, LHome: string;
  LObj: TJsonObject;
begin
  if SessionId.StartsWith('pending-') then
    Exit;

  LHome := GetEnvironmentVariable('USERPROFILE');
  if LHome = '' then
    LHome := TPath.GetHomePath;
  LDir := TPath.Combine(TPath.Combine(LHome, '.acp-cli-manager'), 'sessions');
  LDir := TPath.Combine(LDir, Agent.AgentName.ToLower + '-cli');
  LDir := TPath.Combine(LDir, SessionId);

  if not TDirectory.Exists(LDir) then
    TDirectory.CreateDirectory(LDir);

  LFile := TPath.Combine(LDir, 'metadata.json');
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := SessionId;
    LObj.S['name'] := Name;
    LObj.S['cwd'] := Cwd;
    LObj.I['agentType'] := Ord(AgentType);
    LObj.B['pinned'] := IsPinned;
    LObj.D['createdAt'] := CreatedAt;
    if LastConversationDate > 0 then
      LObj.D['lastConversationDate'] := LastConversationDate;
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
  if SessionId.StartsWith('pending-') then
    Exit;

  LHome := GetEnvironmentVariable('USERPROFILE');
  if LHome = '' then
    LHome := TPath.GetHomePath;
  LDir := TPath.Combine(TPath.Combine(LHome, '.acp-cli-manager'), 'sessions');
  LDir := TPath.Combine(LDir, Agent.AgentName.ToLower + '-cli');
  LDir := TPath.Combine(LDir, SessionId);

  LFile := TPath.Combine(LDir, 'metadata.json');
  if not TFile.Exists(LFile) then
    Exit;

  LObj := TJsonObject.Create;
  try
    LObj.LoadFromFile(LFile);
    Name := LObj.S['name'];
    Cwd := LObj.S['cwd'];
    if LObj.Contains('agentType') then
      AgentType := TAgentType(LObj.I['agentType']);
    IsPinned := LObj.B['pinned'];
    if LObj.Contains('createdAt') then
      CreatedAt := LObj.D['createdAt'];
    if LObj.Contains('lastConversationDate') then
      LastConversationDate := LObj.D['lastConversationDate'];
  finally
    LObj.Free;
  end;
end;

{ TACPAgent }

constructor TACPAgent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FState := asDisconnected;
  FSessions := TDictionary<string, TSessionData>.Create;
  FMethodHandlers := TDictionary<string, TMethodHandler>.Create;
  FACPClient := TACPClient.Create(Self);
  FACPClient.OnReceive := HandleInternalReceive;
  FACPClient.OnRawData := HandleInternalRawData;
  FACPClient.OnTerminated := HandleInternalTerminated;

  RegisterHandlers;
end;

destructor TACPAgent.Destroy;
begin
  FMethodHandlers.Free;
  FSessions.Free;
  inherited;
end;

procedure TACPAgent.RegisterHandlers;
begin
  FMethodHandlers.Add('fs/read_text_file', HandleFSRead);
  FMethodHandlers.Add('fs/write_text_file', HandleFSWrite);
  FMethodHandlers.Add('session/update', HandleSessionUpdate);
  FMethodHandlers.Add('session/request_permission', HandleRequestPermission);
  FMethodHandlers.Add('session/tool_call', HandleToolCall);
end;

procedure TACPAgent.Connect;
begin
  Start();
end;

function TACPAgent.Start(const ACommandLine: string = ''): Boolean;
begin
  if ACommandLine <> '' then
    FACPClient.CommandLine := ACommandLine;
  Result := FACPClient.Start;
  if Result then
    State := asConnecting;
end;

procedure TACPAgent.Stop;
begin
  FACPClient.Stop;
  State := asDisconnected;
end;

procedure TACPAgent.NewSession(AParams: TJsonObject; OnResponse: TACPResponseAnonCallback; OnCondition: TACPResponseCondition);
begin
  FACPClient.Send('session/new', AParams,
    procedure(AResponse: TJsonObject)
    begin
      DoNewSession(AResponse);
      if Assigned(OnResponse) then
        OnResponse(AResponse);
      if Assigned(FOnNewSession) then
        FOnNewSession(Self, AResponse);
    end,
    OnCondition);
end;

procedure TACPAgent.DoNewSession(AResponse: TJsonObject);
begin
end;

procedure TACPAgent.ResumeSession(const SessionId: string);
var
  LSession: TSessionInfo;
begin
  LSession := FindSessionById(SessionId);
  if Assigned(LSession) then
    LSession.IsRestoring := True;
end;

procedure TACPAgent.DoSessionResumed(const SessionId: string);
begin
  if Assigned(FOnSessionResumed) then
    FOnSessionResumed(Self, SessionId);
end;

procedure TACPAgent.EndTurn(const SessionId, StopReason: string);
var
  LSession: TSessionInfo;
begin
  LSession := FindSessionById(SessionId);
  if Assigned(LSession) then
  begin
    LSession.IsWaitForResponse := False;
    UpdateSession(LSession);
  end;
  
  DoEndTurn(SessionId, StopReason);
end;

procedure TACPAgent.UpdateSession(ASession: TSessionInfo);
begin
end;

procedure TACPAgent.SetSessionLogPath(const SessionId, APath: string);
begin
end;

procedure TACPAgent.StartRestoration(const SessionId: string);
var
  Data: TSessionData;
begin
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);
  Data.IsRestoring := True;
  FSessions.AddOrSetValue(SessionId, Data);
end;

procedure TACPAgent.FinalizeRestoration(const SessionId: string);
var
  Data: TSessionData;
begin
  if FSessions.TryGetValue(SessionId, Data) then
  begin
    Data.IsRestoring := False;
    FSessions.AddOrSetValue(SessionId, Data);
  end;
end;

function TACPAgent.GetIsConnected: Boolean;
begin
  Result := FACPClient.IsRunning;
end;

function TACPAgent.IsRestoringSession(const SessionId: string): Boolean;
var
  Data: TSessionData;
begin
  if FSessions.TryGetValue(SessionId, Data) then
    Result := Data.IsRestoring
  else
    Result := False;
end;

procedure TACPAgent.HandleModes(const ASessionId: string; AModes: TJsonObject);
var
  LData: TSessionData;
begin
  if not Assigned(AModes) or (ASessionId = '') then Exit;
  
  if not FSessions.TryGetValue(ASessionId, LData) then
    LData := Default(TSessionData);
    
  LData.ModesJson := AModes.ToJSON(False);
  FSessions.AddOrSetValue(ASessionId, LData);
  
  if Assigned(FOnSessionMetadataUpdate) then
    FOnSessionMetadataUpdate(Self, ASessionId);
end;

procedure TACPAgent.HandleModels(const ASessionId: string; AModels: TJsonObject);
var
  LData: TSessionData;
begin
  if not Assigned(AModels) or (ASessionId = '') then Exit;
  
  if not FSessions.TryGetValue(ASessionId, LData) then
    LData := Default(TSessionData);
    
  LData.ModelsJson := AModels.ToJSON(False);
  FSessions.AddOrSetValue(ASessionId, LData);
  
  if Assigned(FOnSessionMetadataUpdate) then
    FOnSessionMetadataUpdate(Self, ASessionId);
end;

procedure TACPAgent.ReplyPermission(const ID, SessionId, OptionId: string);
var
  Res, Outcome: TJsonObject;
begin
  Res := TJsonObject.Create;
  try
    Outcome := Res.O['outcome'];
    if SameText(OptionId, 'cancelled') then
    begin
      Outcome.S['outcome'] := 'cancelled';
    end
    else
    begin
      Outcome.S['outcome'] := 'selected';
      Outcome.S['optionId'] := OptionId;
    end;
    FACPClient.SendResponse(ID, Res);
  finally
    Res.Free;
  end;

  if SessionId <> '' then
    ResetGrouping(SessionId);
end;

function TACPAgent.GetSessionList: TArray<string>;
var
  LBaseDir, LAgentDir, LSessionDir, LMetadataPath, LJsonText: string;
  LSessionIds: TStringList;
  LMeta: TJsonObject;
begin
  LSessionIds := TStringList.Create;
  try
    LBaseDir := TPath.Combine(GetEnvironmentVariable('USERPROFILE'), '.acp-cli-manager');
    LBaseDir := TPath.Combine(LBaseDir, 'sessions');
    LAgentDir := TPath.Combine(LBaseDir, AgentName.ToLower + '-cli');
    
    if TDirectory.Exists(LAgentDir) then
    begin
      for LSessionDir in TDirectory.GetDirectories(LAgentDir) do
      begin
        var LSid := TPath.GetFileName(LSessionDir);
        if LSid.StartsWith('pending-') then Continue;

        LMetadataPath := TPath.Combine(LSessionDir, 'metadata.json');
        var LIsValid := False;
        
        if TFile.Exists(LMetadataPath) then
        begin
          try
            LJsonText := TFile.ReadAllText(LMetadataPath, TEncoding.UTF8);
            LMeta := TJsonObject.Parse(LJsonText) as TJsonObject;
            try
              if Assigned(LMeta) and (LMeta.Contains('lastConversationDate')) then
                LIsValid := True;
            finally
              LMeta.Free;
            end;
          except
            LIsValid := False;
          end;
        end;

        if LIsValid then
          LSessionIds.Add(LSid)
        else
        begin
          try
            TDirectory.Delete(LSessionDir, True);
          except
          end;
        end;
      end;
    end;
    Result := LSessionIds.ToStringArray;
  finally
    LSessionIds.Free;
  end;
end;

procedure TACPAgent.HandleInternalReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin
  DoReceive(ID, Method, Params, ResultObj, ErrorObj);
end;

procedure TACPAgent.DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
var
  LSessionId: string;
  LHandler: TMethodHandler;
begin
  // session/new 또는 session/load 응답 처리 (메타데이터 자동 업데이트)
  if (ID <> '') and Assigned(ResultObj) and 
     ((Method = 'session/new') or (Method = 'session/load')) then
  begin
    LSessionId := ResultObj.S['sessionId'];
    
    if LSessionId <> '' then
    begin
      if ResultObj.Contains('modes') then
        HandleModes(LSessionId, ResultObj.O['modes']);
      if ResultObj.Contains('models') then
        HandleModels(LSessionId, ResultObj.O['models']);
    end;
  end;

  if (Method <> '') then
  begin
    if FMethodHandlers.TryGetValue(Method, LHandler) then
      LHandler(ID, Params);
  end;
end;

procedure TACPAgent.HandleInternalRawData(Sender: TObject; Direction: TRPCDirection; const RawText: string);
begin
  if Assigned(FOnRawData) then
  begin
    var LObj: TJsonObject := nil;
    if RawText.Trim.StartsWith('{') then
    begin
      try
        LObj := TJsonObject.Parse(RawText) as TJsonObject;
      except
        LObj := nil;
      end;
    end;
    
    try
      var LSid := '';
      if Assigned(LObj) then
      begin
         LSid := LObj.S['sessionId'];
         if LSid = '' then LSid := LObj.O['params'].S['sessionId'];
         if LSid = '' then LSid := LObj.O['result'].S['sessionId'];
      end;
      
      FOnRawData(Self, Direction, LSid, LObj, RawText);
    finally
      if Assigned(LObj) then LObj.Free;
    end;
  end;
end;

function TACPAgent.FindSessionById(const ASessionId: string): TSessionInfo;
var
  LSessions: TList<TSessionInfo>;
  LSession: TSessionInfo;
begin
  Result := nil;
  if not Assigned(FSessionMgr) then Exit;

  LSessions := TSessionManager(FSessionMgr).GetSessionListSnapshot;
  try
    for LSession in LSessions do
      if LSession.SessionId = ASessionId then begin
        Result := LSession;
        Break;
      end;
  finally
    LSessions.Free;
  end;
end;

procedure TACPAgent.ResetGrouping(const ASessionId: string);
var
  Data: TSessionData;
  LSession: TSessionInfo;
begin
  if (ASessionId <> '') and FSessions.TryGetValue(ASessionId, Data) then
  begin
    if Data.LastChunkType <> '' then DoStreamingEnd(ASessionId, Data.LastChunkType);
    
    LSession := FindSessionById(ASessionId);
    if Assigned(LSession) then begin
      LSession.IsThoughtStreaming := False;
      LSession.IsMessageStreaming := False;
    end;
    
    Data.CurrentBlockText := '';
    Data.LastChunkType := '';
    FSessions.AddOrSetValue(ASessionId, Data);
  end;
end;

procedure TACPAgent.HandleFSRead(const ID: string; Params: TJsonObject);
var
  Path, Content, LSid: string;
  Res: TJsonObject;
begin
  LSid := Params.S['sessionId'];
  if LSid <> '' then ResetGrouping(LSid);

  Path := Params.S['path'];
  Res := TJsonObject.Create;
  try
    Content := ''; 
    if TFile.Exists(Path) then
    begin
      try
        Content := TFile.ReadAllText(Path, TEncoding.UTF8);
      except
        Content := '';
      end;
    end;
    Res.S['content'] := Content;
    ACPClient.SendResponse(ID, Res);
  finally
    Res.Free;
  end;
end;

procedure TACPAgent.HandleFSWrite(const ID: string; Params: TJsonObject);
var
  Path, Content, LSid: string;
  Res: TJsonObject;
begin
  LSid := Params.S['sessionId'];
  if LSid <> '' then ResetGrouping(LSid);

  Path := Params.S['path'];
  Content := Params.S['content'];

  Res := TJsonObject.Create;
  try
    try
      TFile.WriteAllText(Path, Content, TEncoding.UTF8);
      // Empty Res will result in {"result": {}}
      ACPClient.SendResponse(ID, Res); 
    except
      on E: Exception do
        ACPClient.SendResponse(ID, nil); 
    end;
  finally Res.Free; end;
end;

procedure TACPAgent.HandleRequestPermission(const ID: string; Params: TJsonObject);
var
  LSID, LMethod: string;
  LToolCall: TJsonObject;
  LOptions: TJsonArray;
begin
  LSID := Params.S['sessionId'];
  // Do NOT reset grouping here. Let it stay in the current bubble.

  LMethod := 'session/request_permission'; // Method context
  LToolCall := Params.O['toolCall'];
  LOptions := Params.A['options'];
  
  if Assigned(FOnPermissionRequest) then
    FOnPermissionRequest(Self, ID, LMethod, LSID, LToolCall, LOptions)
  else
    ReplyPermission(ID, LSID, 'cancelled');
end;

procedure TACPAgent.HandleSessionUpdate(const ID: string; Params: TJsonObject);
var
  UpdateObj: TJsonObject;
  UpdateType, SessionId: string;
  LSession: TSessionInfo;
begin
  if not Assigned(Params) then Exit;
  
  SessionId := Params.S['sessionId'];
  if SessionId = '' then Exit;

  if (Params.IndexOf('update') < 0) or (Params.Items[Params.IndexOf('update')].Typ <> jdtObject) then Exit;
  
  UpdateObj := Params.O['update'];
  UpdateType := UpdateObj.S['sessionUpdate'];
  
  LSession := FindSessionById(SessionId);

  if UpdateType = 'available_commands_update' then
  begin
    ResetGrouping(SessionId);
    ProcessAvailableCommandsUpdate(SessionId, UpdateObj, LSession);
  end
  else if (UpdateType = 'agent_thought_chunk') or (UpdateType = 'agent_message_chunk') or (UpdateType = 'user_message_chunk') then
    ProcessChunkUpdate(SessionId, UpdateType, UpdateObj, LSession)
  else if (UpdateType = 'tool_call_update') or (UpdateType = 'tool_call') then
  begin
    ResetGrouping(SessionId);
    ProcessToolCallUpdate(SessionId, UpdateObj);
  end
  else if UpdateType = 'models_update' then
    ProcessModelsUpdate(SessionId, UpdateObj)
  else if UpdateType = 'modes_update' then
    ProcessModesUpdate(SessionId, UpdateObj);
end;

procedure TACPAgent.ProcessAvailableCommandsUpdate(const SessionId: string; UpdateObj: TJsonObject; LSession: TSessionInfo);
var Data: TSessionData; LIdx: Integer;
begin
  if not FSessions.TryGetValue(SessionId, Data) then Data := Default(TSessionData);
  LIdx := UpdateObj.IndexOf('availableCommands');
  if LIdx >= 0 then begin
    Data.CommandsJson := UpdateObj.A['availableCommands'].ToJSON(False);
    FSessions.AddOrSetValue(SessionId, Data);
  end;

  if Assigned(LSession) and LSession.IsRestoring then begin
    LSession.IsRestoring := False;
    LSession.IsWaitForResponse := False;
    DoSessionResumed(SessionId);
    TThread.Queue(nil, procedure begin UpdateSession(LSession); end);
  end;

  if Assigned(FOnSessionMetadataUpdate) then
    FOnSessionMetadataUpdate(Self, SessionId);
end;

procedure TACPAgent.ProcessChunkUpdate(const SessionId: string; UpdateType: string; UpdateObj: TJsonObject; LSession: TSessionInfo);
var
  Data: TSessionData;
  ChunkText, CleanType, LFullText: string;
  I, LIdx: Integer;
  LIsRestoring: Boolean;
begin
  LIsRestoring := Assigned(LSession) and LSession.IsRestoring;
  if not FSessions.TryGetValue(SessionId, Data) then Data := Default(TSessionData);

  ChunkText := '';
  LIdx := UpdateObj.IndexOf('content');
  if LIdx >= 0 then begin
    case UpdateObj.Items[LIdx].Typ of
      jdtObject: ChunkText := UpdateObj.O['content'].S['text'];
      jdtArray:
        for I := 0 to UpdateObj.A['content'].Count - 1 do
          if UpdateObj.A['content'].Items[I].Typ = jdtObject then
            ChunkText := ChunkText + UpdateObj.A['content'].O[I].S['text'];
    end;
  end;
  
  if ChunkText = '' then Exit;

  CleanType := '';
  if UpdateType = 'agent_thought_chunk' then CleanType := 'thought'
  else if UpdateType = 'agent_message_chunk' then CleanType := 'message'
  else if UpdateType = 'user_message_chunk' then CleanType := 'user';

  if CleanType <> '' then begin
    if Data.LastChunkType <> CleanType then begin
      if (Data.LastChunkType <> '') and (not LIsRestoring) then DoStreamingEnd(SessionId, Data.LastChunkType);
      Data.CurrentBlockText := '';
      Data.LastChunkType := CleanType;
    end;
    
    Data.CurrentBlockText := Data.CurrentBlockText + ChunkText;
    LFullText := Data.CurrentBlockText;
    
    if CleanType = 'user' then begin
      if LFullText.StartsWith('USER:') then LFullText := LFullText.Substring(5);
    end;
    
    LIdx := LFullText.ToLower.IndexOf('--- content from');
    if LIdx < 0 then LIdx := LFullText.ToLower.IndexOf('--- context from');
    if LIdx >= 0 then LFullText := LFullText.Substring(0, LIdx).Trim;

    if CleanType = 'thought' then begin
      Data.FullThought := Data.FullThought + ChunkText;
      if not LIsRestoring then DoThoughtChunk(SessionId, ChunkText, LFullText);
    end
    else begin
      if CleanType = 'message' then Data.FullMessage := Data.FullMessage + ChunkText;
      if not LIsRestoring then DoMessageChunk(SessionId, ChunkText, LFullText);
    end;
  end;
  FSessions.AddOrSetValue(SessionId, Data);
end;

procedure TACPAgent.ProcessToolCallUpdate(const SessionId: string; UpdateObj: TJsonObject);
var
  Data: TSessionData;
  ContentObj: TJsonObject;
  I, LIdx: Integer;
begin
  if not FSessions.TryGetValue(SessionId, Data) then Data := Default(TSessionData);
  if Data.LastChunkType <> '' then DoStreamingEnd(SessionId, Data.LastChunkType);
  Data.CurrentBlockText := '';
  Data.LastChunkType := '';
  
  LIdx := UpdateObj.IndexOf('content');
  if (LIdx >= 0) and (UpdateObj.Items[LIdx].Typ = jdtArray) then begin
    for I := 0 to UpdateObj.A['content'].Count - 1 do begin
      if (UpdateObj.A['content'].Items[I].Typ = jdtObject) and (UpdateObj.A['content'].O[I].S['type'] = 'diff') then begin
        ContentObj := UpdateObj.A['content'].O[I];
        DoFSWrite(SessionId, ContentObj.S['path'], ContentObj.S['oldText'], ContentObj.S['newText']);
      end;
    end;
  end;
  FSessions.AddOrSetValue(SessionId, Data);
end;

procedure TACPAgent.ProcessModelsUpdate(const SessionId: string; UpdateObj: TJsonObject);
var Data: TSessionData; LIdx: Integer;
begin
  if not FSessions.TryGetValue(SessionId, Data) then Data := Default(TSessionData);
  LIdx := UpdateObj.IndexOf('models');
  if LIdx >= 0 then begin
    Data.ModelsJson := UpdateObj.O['models'].ToJSON(False);
    FSessions.AddOrSetValue(SessionId, Data);
  end;
  if Assigned(FOnSessionMetadataUpdate) then FOnSessionMetadataUpdate(Self, SessionId);
end;

procedure TACPAgent.ProcessModesUpdate(const SessionId: string; UpdateObj: TJsonObject);
var Data: TSessionData; LIdx: Integer;
begin
  if not FSessions.TryGetValue(SessionId, Data) then Data := Default(TSessionData);
  LIdx := UpdateObj.IndexOf('modes');
  if LIdx >= 0 then begin
    Data.ModesJson := UpdateObj.O['modes'].ToJSON(False);
    FSessions.AddOrSetValue(SessionId, Data);
  end;
  if Assigned(FOnSessionMetadataUpdate) then FOnSessionMetadataUpdate(Self, SessionId);
end;

procedure TACPAgent.HandleToolCall(const ID: string; Params: TJsonObject);
begin
  // TODO: UI implementation for tool calls
end;

procedure TACPAgent.HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);
begin
  State := asDisconnected;
  FSessions.Clear;
end;

procedure TACPAgent.DoMessageChunk(const SessionId, Chunk, FullText: string);
begin
  if Assigned(FOnMessageChunk) then FOnMessageChunk(Self, SessionId, Chunk, FullText);
end;

procedure TACPAgent.DoEndTurn(const SessionId, StopReason: string);
begin
  if Assigned(FOnEndTurn) then FOnEndTurn(Self, SessionId, StopReason);
end;

procedure TACPAgent.DoThoughtChunk(const SessionId, Chunk, FullText: string);
begin
  if Assigned(FOnThoughtChunk) then FOnThoughtChunk(Self, SessionId, Chunk, FullText);
end;

procedure TACPAgent.DoStreamingEnd(const SessionId, AType: string);
begin
  if Assigned(FOnStreamingEnd) then FOnStreamingEnd(Self, SessionId, AType);
end;

procedure TACPAgent.DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
begin
  if Assigned(FOnFSWrite) then FOnFSWrite(Self, SessionId, Path, OldContent, NewContent);
end;

procedure TACPAgent.SetState(const Value: TAgentState);
var
  OldState: TAgentState;
begin
  if FState <> Value then
  begin
    OldState := FState;
    FState := Value;
  end;
end;

end.
