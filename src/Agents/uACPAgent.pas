unit uACPAgent;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.IOUtils,
  JsonDataObjects, uAgent, uACPClient, uAgentTypes, uSessionManager;

type
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

  TACPAgent = class(TAgent)
  private
    FACPClient: TACPClient;
    FSessionMgr: TSessionManager; // Injected TSessionManager
    FSessions: TDictionary<string, TSessionData>;
    FOnRawData: TAgentRPCEvent;
    FOnPermissionRequest: TAgentPermissionRequestEvent;
    FOnSessionMetadataUpdate: TSessionMetadataUpdateEvent;

    procedure HandleInternalReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
    procedure HandleInternalRawData(Sender: TObject; Direction: TRPCDirection; const RawText: string);
    procedure HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);

    procedure HandleFSRead(const ID, Method: string; Params: TJsonObject);
    procedure HandleFSWrite(const ID, Method: string; Params: TJsonObject);
    procedure HandleRequestPermission(const ID, Method: string; Params: TJsonObject);
    procedure ResetGrouping(const ASessionId: string);
    function FindSessionById(const ASessionId: string): TSessionInfo;
    function GetIsConnected: Boolean;
  protected
    function GetSessionList: TArray<string>; override;
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); virtual;
    procedure HandleSessionUpdate(Params: TJsonObject); virtual;
    
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Connect; override;
    procedure Stop; override;

    procedure EndTurn(const SessionId, StopReason: string); virtual;
    procedure UpdateSession(ASession: TSessionInfo); virtual;

    function Start: Boolean; virtual; // Make virtual for subclass overrides
    procedure ReplyPermission(const ID, OptionId: string);
    procedure SetSessionLogPath(const SessionId, APath: string);
    procedure StartRestoration(const SessionId: string);
    procedure FinalizeRestoration(const SessionId: string);
    function IsRestoringSession(const SessionId: string): Boolean;

    procedure LoadSession(const SessionId: string; ACallback: TProc<string>); virtual; abstract;
    procedure CreateNewSession(const Cwd: string; const Mode: string; ACallback: TProc<string>); virtual; abstract;
    
    property ACPClient: TACPClient read FACPClient;
    property SessionManager: TSessionManager read FSessionMgr write FSessionMgr;
    property Sessions: TDictionary<string, TSessionData> read FSessions;
    property IsConnected: Boolean read GetIsConnected;

    property OnRawData: TAgentRPCEvent read FOnRawData write FOnRawData;
    property OnPermissionRequest: TAgentPermissionRequestEvent read FOnPermissionRequest write FOnPermissionRequest;
    property OnSessionMetadataUpdate: TSessionMetadataUpdateEvent read FOnSessionMetadataUpdate write FOnSessionMetadataUpdate;
  end;

implementation

uses
  uACPProtocol;

{ TACPAgent }

constructor TACPAgent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSessions := TDictionary<string, TSessionData>.Create;
  FACPClient := TACPClient.Create(Self);
  FACPClient.OnReceive := HandleInternalReceive;
  FACPClient.OnRawData := HandleInternalRawData;
  FACPClient.OnTerminated := HandleInternalTerminated;
end;

destructor TACPAgent.Destroy;
begin
  FSessions.Free;
  inherited;
end;

procedure TACPAgent.Connect;
begin
  Start;
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
  // Virtual method to be overridden by handler or UI control
end;

function TACPAgent.Start: Boolean;
begin
  Result := FACPClient.Start;
  if Result then
    State := asConnecting;
end;

procedure TACPAgent.Stop;
begin
  FACPClient.Stop;
  State := asDisconnected;
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

procedure TACPAgent.ReplyPermission(const ID, OptionId: string);
var
  Res, Outcome: TJsonObject;
begin
  Res := TJsonObject.Create;
  try
    Outcome := Res.O['outcome'];
    Outcome.S['outcome'] := 'selected';
    Outcome.S['optionId'] := OptionId;
    FACPClient.SendResponse(ID, Res);
  finally
    Res.Free;
  end;
end;

function TACPAgent.GetSessionList: TArray<string>;
var
  LBaseDir, LAgentDir, LSessionDir, LHistoryPath: string;
  LSessionIds: TStringList;
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

        LHistoryPath := TPath.Combine(LSessionDir, 'history.json');
        if TFile.Exists(LHistoryPath) and (TFile.GetSize(LHistoryPath) > 10) then
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
begin
  if (ID = '') and (Method = 'session/update') then
  begin
    if Assigned(Params) then
      HandleSessionUpdate(Params);
    Exit;
  end;

  if (Method <> '') then
  begin
    LSessionId := '';
    if Assigned(Params) then
      LSessionId := Params.S['sessionId'];
    
    if LSessionId = '' then
    begin
       if Assigned(ResultObj) then
         LSessionId := ResultObj.S['sessionId'];
    end;

    if LSessionId <> '' then
      ResetGrouping(LSessionId);

    if Method = 'fs/read_text_file' then HandleFSRead(ID, Method, Params)
    else if Method = 'fs/write_text_file' then HandleFSWrite(ID, Method, Params)
    else if Method = 'session/request_permission' then HandleRequestPermission(ID, Method, Params);
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

  LSessions := FSessionMgr.GetSessionListSnapshot;
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
begin
  if (ASessionId <> '') and FSessions.TryGetValue(ASessionId, Data) then
  begin
    if Data.LastChunkType <> '' then DoStreamingEnd(ASessionId, Data.LastChunkType);
    Data.CurrentBlockText := '';
    Data.LastChunkType := '';
    FSessions.AddOrSetValue(ASessionId, Data);
  end;
end;

procedure TACPAgent.HandleFSRead(const ID, Method: string; Params: TJsonObject);
var
  Path, Content: string;
  Res: TJsonObject;
begin
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

procedure TACPAgent.HandleFSWrite(const ID, Method: string; Params: TJsonObject);
var
  Path, Content: string;
begin
  Path := Params.S['path'];
  Content := Params.S['content'];

  try
    TFile.WriteAllText(Path, Content, TEncoding.UTF8);
    ACPClient.SendResponse(ID, nil); 
  except
    on E: Exception do
      ACPClient.SendResponse(ID, nil);
  end;
end;

procedure TACPAgent.HandleRequestPermission(const ID, Method: string; Params: TJsonObject);
var
  LSID: string;
  LToolCall: TJsonObject;
  LOptions: TJsonArray;
begin
  LSID := Params.S['sessionId'];
  LToolCall := Params.O['toolCall'];
  LOptions := Params.A['options'];
  
  if Assigned(FOnPermissionRequest) then
    FOnPermissionRequest(Self, ID, Method, LSID, LToolCall, LOptions)
  else
    ReplyPermission(ID, 'cancel');
end;

procedure TACPAgent.HandleSessionUpdate(Params: TJsonObject);
var
  UpdateObj, ContentObj: TJsonObject;
  UpdateType, ChunkText, SessionId, CleanType, LFullText: string;
  Data: TSessionData;
  I, LIdx: Integer;
  Changed: Boolean;
  LSession: TSessionInfo;
  LIsRestoring: Boolean;
begin
  if not Assigned(Params) then Exit;
  
  SessionId := Params.S['sessionId'];
  if SessionId = '' then Exit;

  LIdx := Params.IndexOf('update');
  if (LIdx < 0) or (Params.Items[LIdx].Typ <> jdtObject) then Exit;
  
  UpdateObj := Params.O['update'];
  UpdateType := UpdateObj.S['sessionUpdate'];
  
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);

  LSession := FindSessionById(SessionId);
  LIsRestoring := Assigned(LSession) and LSession.IsRestoring;
  Changed := False;

  // --- Strict Dispatch based on UpdateType ---

  if UpdateType = 'available_commands_update' then
  begin
    LIdx := UpdateObj.IndexOf('availableCommands');
    if LIdx >= 0 then
    begin
      Data.CommandsJson := UpdateObj.A['availableCommands'].ToJSON(False);
      Changed := True;
    end;

    if LIsRestoring then
    begin
      if Assigned(LSession) then
      begin
        LSession.IsRestoring := False;
        LSession.IsWaitForResponse := False;
        TThread.Queue(nil, procedure begin UpdateSession(LSession); end);
      end;
      LIsRestoring := False;
    end;

    if (Data.LastChunkType <> '') and (not LIsRestoring) then DoStreamingEnd(SessionId, Data.LastChunkType);
    Data.CurrentBlockText := '';
    Data.LastChunkType := '';
    Changed := True;
  end

  else if (UpdateType = 'agent_thought_chunk') or (UpdateType = 'agent_message_chunk') or (UpdateType = 'user_message_chunk') then
  begin
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
  end

  else if (UpdateType = 'tool_call_update') or (UpdateType = 'tool_call') then
  begin
    if (Data.LastChunkType <> '') and (not LIsRestoring) then DoStreamingEnd(SessionId, Data.LastChunkType);
    Data.CurrentBlockText := '';
    Data.LastChunkType := '';
    
    LIdx := UpdateObj.IndexOf('content');
    if (UpdateType = 'tool_call_update') and (LIdx >= 0) and (UpdateObj.Items[LIdx].Typ = jdtArray) then
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
  end

  else if UpdateType = 'models_update' then
  begin
    LIdx := UpdateObj.IndexOf('models');
    if LIdx >= 0 then
    begin
      Data.ModelsJson := UpdateObj.O['models'].ToJSON(False);
      Changed := True;
    end;
  end

  else if UpdateType = 'modes_update' then
  begin
    LIdx := UpdateObj.IndexOf('modes');
    if LIdx >= 0 then
    begin
      Data.ModesJson := UpdateObj.O['modes'].ToJSON(False);
      Changed := True;
    end;
  end

  else
  begin
    // Unknown UpdateType
    DoStatusChange('Unknown session update type: ' + UpdateType);
  end;

  FSessions.AddOrSetValue(SessionId, Data);
  if Changed and Assigned(FOnSessionMetadataUpdate) then
    FOnSessionMetadataUpdate(Self, SessionId);
end;

procedure TACPAgent.HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);
begin
  State := asDisconnected;
  FSessions.Clear;
  DoStatusChange('Process Terminated. Code: ' + IntToStr(ExitCode));
end;

end.
