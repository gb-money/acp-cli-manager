unit uACPAgent;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.IOUtils,
  JsonDataObjects, uACPClient, uAgentTypes, uACPDispatcher;

type
  TMethodHandler = procedure(const ID: string; Params: TJsonObject) of object;
  TSessionUpdateHandler = procedure(const SessionId: string; UpdateObj: TJsonObject) of object;

  TACPAgent = class(TComponent, IACPAgent)
  protected
    FAgentName: string;
    FAgentType: TAgentType;
    FState: TAgentState;
    FWorkspace: string;
    FDispatcher: TACPDispatcher;
    FSessionMgr: TObject; // Injected Manager (Type erased to break circular reference)
    FSessions: TDictionary<string, TSessionData>;
    FMethodHandlers: TDictionary<string, TMethodHandler>;
    FSessionUpdateHandlers: TDictionary<string, TSessionUpdateHandler>;
    FObservers: TList<IAgentObserver>;

    FAvailableModels: TArray<TAgentModelInfo>;
    FCurrentModelId: string;
    FAvailableModes: TArray<TAgentModeInfo>;
    FCurrentModeId: string;

    procedure SetState(const Value: TAgentState);
    procedure HandleInternalReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
    procedure HandleInternalRawData(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
    procedure HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);

    procedure HandleFSRead(const ID: string; Params: TJsonObject);
    procedure HandleFSWrite(const ID: string; Params: TJsonObject);
    procedure HandleRequestPermission(const ID: string; Params: TJsonObject);
    procedure HandleSessionUpdate(const ID: string; Params: TJsonObject);
    procedure HandleToolCall(const ID: string; Params: TJsonObject);
    
    procedure ProcessAvailableCommandsUpdate(const SessionId: string; UpdateObj: TJsonObject);
    procedure ProcessChunkUpdate(const SessionId: string; UpdateObj: TJsonObject);
    procedure ProcessToolCallUpdate(const SessionId: string; UpdateObj: TJsonObject);
    procedure ProcessModelsUpdate(const SessionId: string; UpdateObj: TJsonObject);
    procedure ProcessModesUpdate(const SessionId: string; UpdateObj: TJsonObject);

    procedure ResetGrouping(const ASessionId: string);
    
    { IACPAgent implementation helpers }
    function GetAgentName: string;
    function GetAgentType: TAgentType;
    function GetSessionList: TArray<string>;
    procedure SetWorkspace(const APath: string);
    function GetState: TAgentState;
    function GetModels: TArray<TAgentModelInfo>;
    function GetModelId: string;
    function GetModes: TArray<TAgentModeInfo>;
    function GetModeId: string;
    function GetSessionsJson(const ASessionId: string): string;
    function GetIsConnected: Boolean;
    
    procedure RegisterHandlers; virtual;
    procedure RegisterSessionUpdateHandlers; virtual;
    function FindSessionById(const ASessionId: string): TSessionInfo;
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); virtual;
    
    procedure DoEndTurn(const SessionId, StopReason: string); virtual;
    procedure DoMessageChunk(const SessionId, Chunk, FullText: string);
    procedure DoThoughtChunk(const SessionId, Chunk, FullText: string);
    procedure DoStreamingEnd(const SessionId, AType: string);
    procedure DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
    procedure DoNewSession(AResponse: TJsonObject); virtual;
    procedure DoSessionResumed(const SessionId: string); virtual;

    procedure NotifySessionMetadataUpdate(const SessionId: string);
    procedure NotifyPropertyUpdate(const SessionId, PropertyName, NewValue: string);
    
    property Dispatcher: TACPDispatcher read FDispatcher;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Connect; virtual;
    function Start(const ACommandLine: string = ''): Boolean; virtual;
    procedure Stop; virtual;
    procedure SendPrompt(const SessionId, AText: string); virtual; abstract;
    procedure Initialize(AParams: TJsonObject = nil); virtual; abstract;
    procedure NewSession(AParams: TJsonObject); virtual;
    procedure ResumeSession(const SessionId: string); virtual;
    procedure EndTurn(const SessionId, StopReason: string); virtual;
    procedure UpdateSession(ASession: TSessionInfo); virtual;

    procedure ChangeModel(const ASessionId, AModelId: string); virtual;
    procedure CancelPrompt(const ASessionId: string); virtual;

    procedure Send(const Method: string; Params: TJsonObject = nil; OnResponse: TACPResponseAnonCallback = nil; OnConditions: TArray<TACPResponseCondition> = nil; const SessionId: string = '');
    procedure SendResponse(const ID: string; ResultObj: TJsonObject = nil);
    procedure ReplyPermission(const ID, SessionId, OptionId: string); virtual;
    procedure SetSessionLogPath(const SessionId, APath: string);
    procedure SetSessionManager(AManager: TObject);
    procedure StartRestoration(const SessionId: string);
    procedure FinalizeRestoration(const SessionId: string);
    function IsRestoringSession(const SessionId: string): Boolean;

    procedure HandleModes(AModes: TJsonObject);
    procedure HandleModels(AModels: TJsonObject);

    procedure AddObserver(AObserver: IAgentObserver);
    procedure RemoveObserver(AObserver: IAgentObserver);

    property AgentName: string read FAgentName write FAgentName;
    property AgentType: TAgentType read GetAgentType;
    property State: TAgentState read GetState write SetState;
    property Workspace: string read FWorkspace write SetWorkspace;
    property SessionManager: TObject read FSessionMgr write SetSessionManager;
    property Sessions: TDictionary<string, TSessionData> read FSessions;
  end;

implementation

uses
  uACPProtocol, uSessionManager;

{ TACPAgent }

constructor TACPAgent.Create(AOwner: TComponent);
var
  LClient: TACPClient;
begin
  inherited Create(AOwner);
  FState := asDisconnected;
  FSessions := TDictionary<string, TSessionData>.Create;
  FMethodHandlers := TDictionary<string, TMethodHandler>.Create;
  FObservers := TList<IAgentObserver>.Create;
  
  LClient := TACPClient.Create(Self);
  FDispatcher := TACPDispatcher.Create(LClient);
  FDispatcher.OnReceive := HandleInternalReceive;
  FDispatcher.OnRawData := HandleInternalRawData;
  FDispatcher.OnTerminated := HandleInternalTerminated;
  
  RegisterHandlers;
end;

destructor TACPAgent.Destroy;
begin
  FSessionUpdateHandlers.Free;
  FMethodHandlers.Free;
  FSessions.Free;
  FObservers.Free;
  FDispatcher.Free;
  inherited;
end;

procedure TACPAgent.RegisterHandlers;
begin
  FMethodHandlers.Add('fs/read_text_file', HandleFSRead);
  FMethodHandlers.Add('fs/write_text_file', HandleFSWrite);
  FMethodHandlers.Add('session/update', HandleSessionUpdate);
  FMethodHandlers.Add('session/request_permission', HandleRequestPermission);
  FMethodHandlers.Add('session/tool_call', HandleToolCall);
  
  RegisterSessionUpdateHandlers;
end;

procedure TACPAgent.RegisterSessionUpdateHandlers;
begin
  FSessionUpdateHandlers := TDictionary<string, TSessionUpdateHandler>.Create;
  FSessionUpdateHandlers.Add('available_commands_update', ProcessAvailableCommandsUpdate);
  FSessionUpdateHandlers.Add('agent_thought_chunk', ProcessChunkUpdate);
  FSessionUpdateHandlers.Add('agent_message_chunk', ProcessChunkUpdate);
  FSessionUpdateHandlers.Add('user_message_chunk', ProcessChunkUpdate);
  FSessionUpdateHandlers.Add('tool_call_update', ProcessToolCallUpdate);
  FSessionUpdateHandlers.Add('tool_call', ProcessToolCallUpdate);
  FSessionUpdateHandlers.Add('models_update', ProcessModelsUpdate);
  FSessionUpdateHandlers.Add('modes_update', ProcessModesUpdate);
end;

procedure TACPAgent.Connect;
begin
  Start();
end;

function TACPAgent.Start(const ACommandLine: string = ''): Boolean;
begin
  if ACommandLine <> '' then
    Dispatcher.CommandLine := ACommandLine;
    
  Result := Dispatcher.Start;
  if Result then
    State := asConnecting;
end;

procedure TACPAgent.Stop;
begin
  Dispatcher.Stop;
  State := asDisconnected;
end;

procedure TACPAgent.NewSession(AParams: TJsonObject);
begin
  FDispatcher.CreateSession(FWorkspace, 
    procedure(ASid: string; AResponse: TJsonObject)
    begin
      DoNewSession(AResponse);
    end);
end;

procedure TACPAgent.DoNewSession(AResponse: TJsonObject);
var
  LObs: IAgentObserver;
begin
  for LObs in FObservers do
    LObs.OnAgentNewSession(Self, AResponse);
end;

procedure TACPAgent.ResumeSession(const SessionId: string);
var
  LSession: TSessionInfo;
begin
  LSession := FindSessionById(SessionId);
  if Assigned(LSession) then
    LSession.IsRestoring := True;
    
  StartRestoration(SessionId);
  
  FDispatcher.LoadSession(SessionId, FWorkspace,
    procedure(ASuccess: Boolean)
    var
      LSessionCallback: TSessionInfo;
    begin
      LSessionCallback := FindSessionById(SessionId);
      if Assigned(LSessionCallback) then
      begin
        LSessionCallback.IsRestoring := False;
        LSessionCallback.IsWaitForResponse := False;
        DoSessionResumed(SessionId);
        System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
        begin
          UpdateSession(LSessionCallback);
        end));
      end;
      FinalizeRestoration(SessionId);
    end
  );
end;

procedure TACPAgent.DoSessionResumed(const SessionId: string);
var
  LObs: IAgentObserver;
begin
  for LObs in FObservers do
    LObs.OnAgentSessionResumed(Self, SessionId);
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

procedure TACPAgent.ChangeModel(const ASessionId, AModelId: string);
begin
end;

procedure TACPAgent.CancelPrompt(const ASessionId: string);
begin
end;

procedure TACPAgent.DoEndTurn(const SessionId, StopReason: string);
var
  LObs: IAgentObserver;
begin
  for LObs in FObservers do
    LObs.OnAgentEndTurn(Self, SessionId, StopReason);
end;

procedure TACPAgent.UpdateSession(ASession: TSessionInfo);
begin
end;

procedure TACPAgent.Send(const Method: string; Params: TJsonObject; OnResponse: TACPResponseAnonCallback; OnConditions: TArray<TACPResponseCondition>; const SessionId: string);
begin
  FDispatcher.Send(Method, Params, OnResponse, OnConditions, SessionId);
end;

procedure TACPAgent.SendResponse(const ID: string; ResultObj: TJsonObject);
begin
  FDispatcher.SendResponse(ID, ResultObj);
end;

procedure TACPAgent.SetSessionLogPath(const SessionId, APath: string);
begin
end;

procedure TACPAgent.SetSessionManager(AManager: TObject);
begin
  FSessionMgr := AManager;
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

function TACPAgent.GetAgentName: string;
begin
  Result := FAgentName;
end;

function TACPAgent.GetAgentType: TAgentType;
begin
  Result := FAgentType;
end;

function TACPAgent.GetState: TAgentState;
begin
  Result := FState;
end;

function TACPAgent.GetModels: TArray<TAgentModelInfo>;
begin
  Result := FAvailableModels;
end;

function TACPAgent.GetModelId: string;
begin
  Result := FCurrentModelId;
end;

function TACPAgent.GetModes: TArray<TAgentModeInfo>;
begin
  Result := FAvailableModes;
end;

function TACPAgent.GetModeId: string;
begin
  Result := FCurrentModeId;
end;

procedure TACPAgent.SetWorkspace(const APath: string);
begin
  FWorkspace := APath;
end;

function TACPAgent.GetSessionsJson(const ASessionId: string): string;
var
  Data: TSessionData;
begin
  if FSessions.TryGetValue(ASessionId, Data) then
    Result := Data.CommandsJson
  else
    Result := '';
end;

function TACPAgent.GetIsConnected: Boolean;
begin
  Result := Assigned(FDispatcher) and FDispatcher.IsRunning;
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

procedure TACPAgent.HandleModes(AModes: TJsonObject);
var
  LArr: TJsonArray;
  LI: Integer;
  LK: string;
  LNewModes: TArray<TAgentModeInfo>;
  LObs: IAgentObserver;
begin
  if not Assigned(AModes) then Exit;
  
  if AModes.Contains('currentModeId') then
    FCurrentModeId := AModes.S['currentModeId'];
    
  LArr := AModes.A['availableModes'];
  SetLength(LNewModes, LArr.Count);
  for LI := 0 to LArr.Count - 1 do
  begin
    LNewModes[LI].ModeId := LArr.O[LI].S['id'];
    LNewModes[LI].Name := LArr.O[LI].S['name'];
    if LArr.O[LI].Contains('description') then
      LNewModes[LI].Description := LArr.O[LI].S['description']
    else
      LNewModes[LI].Description := '';
  end;
  FAvailableModes := LNewModes;
  
  for LK in FSessions.Keys do
    for LObs in FObservers do
      LObs.OnAgentSessionMetadataUpdate(Self, LK);
end;

procedure TACPAgent.HandleModels(AModels: TJsonObject);
var
  LArr: TJsonArray;
  LI: Integer;
  LK: string;
  LNewModels: TArray<TAgentModelInfo>;
  LObs: IAgentObserver;
begin
  if not Assigned(AModels) then Exit;
  
  if AModels.Contains('currentModelId') then
    FCurrentModelId := AModels.S['currentModelId'];
    
  LArr := AModels.A['availableModels'];
  SetLength(LNewModels, LArr.Count);
  for LI := 0 to LArr.Count - 1 do
  begin
    LNewModels[LI].ModelId := LArr.O[LI].S['modelId'];
    LNewModels[LI].Name := LArr.O[LI].S['name'];
    if LArr.O[LI].Contains('description') then
      LNewModels[LI].Description := LArr.O[LI].S['description']
    else
      LNewModels[LI].Description := '';
  end;
  FAvailableModels := LNewModels;
  
  for LK in FSessions.Keys do
    for LObs in FObservers do
      LObs.OnAgentSessionMetadataUpdate(Self, LK);
end;

procedure TACPAgent.ReplyPermission(const ID, SessionId, OptionId: string);
var
  Res, Outcome: TJsonObject;
begin
  Res := TJsonObject.Create;
  try
    Outcome := Res.O['outcome'];
    if SameText(OptionId, 'cancelled') then
      Outcome.S['outcome'] := 'cancelled'
    else
    begin
      Outcome.S['outcome'] := 'selected';
      Outcome.S['optionId'] := OptionId;
    end;
    FDispatcher.SendResponse(ID, Res);
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
  LIsValid: Boolean;
  LSid: string;
begin
  LSessionIds := TStringList.Create;
  try
    LBaseDir := TPath.Combine(GetEnvironmentVariable('USERPROFILE'), '.acp-cli-manager');
    LBaseDir := TPath.Combine(LBaseDir, 'sessions');
    LAgentDir := TPath.Combine(LBaseDir, FAgentName.ToLower + '-cli');
    
    if TDirectory.Exists(LAgentDir) then
    begin
      for LSessionDir in TDirectory.GetDirectories(LAgentDir) do
      begin
        LSid := TPath.GetFileName(LSessionDir);
        if LSid.StartsWith('pending-') then Continue;
        
        LMetadataPath := TPath.Combine(LSessionDir, 'metadata.json');
        LIsValid := False;
        
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
  LHandler: TMethodHandler;
begin
  if (ID <> '') and Assigned(ResultObj) and ((Method = 'session/new') or (Method = 'session/load')) then
  begin
    if ResultObj.Contains('modes') then HandleModes(ResultObj.O['modes']);
    if ResultObj.Contains('models') then HandleModels(ResultObj.O['models']);
  end;
  
  if (Method <> '') then
    if FMethodHandlers.TryGetValue(Method, LHandler) then
      LHandler(ID, Params);
end;

procedure TACPAgent.HandleInternalRawData(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
var
  LObs: IAgentObserver;
begin
  for LObs in FObservers do
    LObs.OnAgentRawData(Self, Direction, ASessionId, AObj, RawText);
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
      if SameText(LSession.SessionId, ASessionId) then
      begin
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
    if Data.LastChunkType <> '' then
      DoStreamingEnd(ASessionId, Data.LastChunkType);
      
    LSession := FindSessionById(ASessionId);
    if Assigned(LSession) then
    begin
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
    Dispatcher.SendResponse(ID, Res);
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
      Dispatcher.SendResponse(ID, Res);
    except
      on E: Exception do
        Dispatcher.SendResponse(ID, nil);
    end;
  finally
    Res.Free;
  end;
end;

procedure TACPAgent.HandleRequestPermission(const ID: string; Params: TJsonObject);
var
  LSID, LMethod: string;
  LToolCall: TJsonObject;
  LOptions: TJsonArray;
  LObs: IAgentObserver;
begin
  LSID := Params.S['sessionId'];
  LMethod := 'session/request_permission';
  LToolCall := Params.O['toolCall'];
  LOptions := Params.A['options'];
  
  if FObservers.Count > 0 then
  begin
    for LObs in FObservers do
      LObs.OnAgentPermissionRequest(Self, ID, LMethod, LSID, LToolCall, LOptions);
  end
  else
    ReplyPermission(ID, LSID, 'cancelled');
end;

procedure TACPAgent.HandleSessionUpdate(const ID: string; Params: TJsonObject);
var
  UpdateObj: TJsonObject;
  UpdateType, SessionId: string;
  LHandler: TSessionUpdateHandler;
begin
  if not Assigned(Params) then Exit;
  
  SessionId := Params.S['sessionId'];
  if SessionId = '' then Exit;
  
  if (Params.IndexOf('update') < 0) or (Params.Items[Params.IndexOf('update')].Typ <> jdtObject) then
    Exit;
    
  UpdateObj := Params.O['update'];
  UpdateType := UpdateObj.S['sessionUpdate'];
  
  if FSessionUpdateHandlers.TryGetValue(UpdateType, LHandler) then
    LHandler(SessionId, UpdateObj);
end;

procedure TACPAgent.ProcessAvailableCommandsUpdate(const SessionId: string; UpdateObj: TJsonObject);
var
  Data: TSessionData;
  LIdx: Integer;
  LObs: IAgentObserver;
begin
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);
    
  LIdx := UpdateObj.IndexOf('availableCommands');
  if LIdx >= 0 then
  begin
    Data.CommandsJson := UpdateObj.A['availableCommands'].ToJSON(False);
    FSessions.AddOrSetValue(SessionId, Data);
  end;
  
  for LObs in FObservers do
    LObs.OnAgentSessionMetadataUpdate(Self, SessionId);
end;

procedure TACPAgent.ProcessChunkUpdate(const SessionId: string; UpdateObj: TJsonObject);
var
  Data: TSessionData;
  ChunkText, CleanType, LFullText: string;
  I, LIdx: Integer;
  LSession: TSessionInfo;
  LIsRestoring: Boolean;
  UpdateType: string;
begin
  UpdateType := UpdateObj.S['sessionUpdate'];
  LSession := FindSessionById(SessionId);
  LIsRestoring := Assigned(LSession) and LSession.IsRestoring;
  
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);
    
  ChunkText := '';
  LIdx := UpdateObj.IndexOf('content');
  if LIdx >= 0 then
  begin
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
  
  if CleanType <> '' then
  begin
    if Data.LastChunkType <> CleanType then
    begin
      if (Data.LastChunkType <> '') and (not LIsRestoring) then
        DoStreamingEnd(SessionId, Data.LastChunkType);
        
      Data.CurrentBlockText := '';
      Data.LastChunkType := CleanType;
    end;
    
    Data.CurrentBlockText := Data.CurrentBlockText + ChunkText;
    LFullText := Data.CurrentBlockText;
    
    if CleanType = 'thought' then
    begin
      Data.FullThought := Data.FullThought + ChunkText;
      if not LIsRestoring then DoThoughtChunk(SessionId, ChunkText, LFullText);
    end
    else
    begin
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
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);
    
  if Data.LastChunkType <> '' then
    DoStreamingEnd(SessionId, Data.LastChunkType);
    
  Data.CurrentBlockText := '';
  Data.LastChunkType := '';
  
  LIdx := UpdateObj.IndexOf('content');
  if (LIdx >= 0) and (UpdateObj.Items[LIdx].Typ = jdtArray) then
  begin
    for I := 0 to UpdateObj.A['content'].Count - 1 do
    begin
      if (UpdateObj.A['content'].Items[I].Typ = jdtObject) and (UpdateObj.A['content'].O[I].S['type'] = 'diff') then
      begin
        ContentObj := UpdateObj.A['content'].O[I];
        DoFSWrite(SessionId, ContentObj.S['path'], ContentObj.S['oldText'], ContentObj.S['newText']);
      end;
    end;
  end;
  FSessions.AddOrSetValue(SessionId, Data);
end;

procedure TACPAgent.ProcessModelsUpdate(const SessionId: string; UpdateObj: TJsonObject);
begin
  if UpdateObj.Contains('models') then HandleModels(UpdateObj.O['models']);
end;

procedure TACPAgent.ProcessModesUpdate(const SessionId: string; UpdateObj: TJsonObject);
begin
  if UpdateObj.Contains('modes') then HandleModes(UpdateObj.O['modes']);
end;

procedure TACPAgent.HandleToolCall(const ID: string; Params: TJsonObject); begin end;
procedure TACPAgent.HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal); begin State := asDisconnected; FSessions.Clear; end;

procedure TACPAgent.DoMessageChunk(const SessionId, Chunk, FullText: string);
var LObs: IAgentObserver; begin for LObs in FObservers do LObs.OnAgentMessageChunk(Self, SessionId, Chunk, FullText); end;

procedure TACPAgent.DoThoughtChunk(const SessionId, Chunk, FullText: string);
var LObs: IAgentObserver; begin for LObs in FObservers do LObs.OnAgentThoughtChunk(Self, SessionId, Chunk, FullText); end;

procedure TACPAgent.DoStreamingEnd(const SessionId, AType: string);
var LObs: IAgentObserver; begin for LObs in FObservers do LObs.OnAgentStreamingEnd(Self, SessionId, AType); end;

procedure TACPAgent.DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
var LObs: IAgentObserver; begin for LObs in FObservers do LObs.OnAgentFSWrite(Self, SessionId, Path, OldContent, NewContent); end;

procedure TACPAgent.AddObserver(AObserver: IAgentObserver);
begin if not FObservers.Contains(AObserver) then FObservers.Add(AObserver); end;

procedure TACPAgent.RemoveObserver(AObserver: IAgentObserver);
begin FObservers.Remove(AObserver); end;

procedure TACPAgent.NotifySessionMetadataUpdate(const SessionId: string);
var LObs: IAgentObserver; begin for LObs in FObservers do LObs.OnAgentSessionMetadataUpdate(Self, SessionId); end;

procedure TACPAgent.NotifyPropertyUpdate(const SessionId, PropertyName, NewValue: string);
var LObs: IAgentObserver; begin for LObs in FObservers do LObs.OnAgentPropertyUpdate(Self, SessionId, PropertyName, NewValue); end;

procedure TACPAgent.SetState(const Value: TAgentState);
var
  OldState: TAgentState;
  LObs: IAgentObserver;
begin
  if FState <> Value then
  begin
    OldState := FState;
    FState := Value;
    for LObs in FObservers do
      LObs.OnAgentStateChange(Self, OldState, FState);
  end;
end;

end.
