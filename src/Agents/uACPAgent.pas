unit uACPAgent;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.IOUtils,
  JsonDataObjects, uAgent, uACPClient, uACPProtocol;

type
  TSessionData = record
    FullThought: string;
    FullMessage: string;
    ModesJson: string;
    ModelsJson: string;
    CommandsJson: string;
    LastChunkType: string;    // 'thought', 'message', or 'user'
    CurrentBlockText: string; // Text for the current block only
    LogPath: string;          // Persistent history path
    IsProcessing: Boolean;    // True if generating response
    IsRestoring: Boolean;     // True if replaying history (session/load)
  end;

  TAgentPermissionRequestEvent = procedure(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject) of object;
  TSessionMetadataUpdateEvent = procedure(Sender: TObject; const SessionId: string) of object;

  TACPAgent = class(TAgent)
  private
    FACPClient: TACPClient;
    FSessions: TDictionary<string, TSessionData>;
    FOnRawData: TACPRawDataEvent;
    FOnPermissionRequest: TAgentPermissionRequestEvent;
    FOnSessionMetadataUpdate: TSessionMetadataUpdateEvent;
    
    procedure HandleInternalReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
    procedure HandleInternalRawData(Sender: TObject; const Direction, RawText: string);
    procedure HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);
    
    procedure HandleFSRead(const ID, Method: string; Params: TJsonObject);
    procedure HandleFSWrite(const ID, Method: string; Params: TJsonObject);
    procedure HandleRequestPermission(const ID, Method: string; Params: TJsonObject);
  protected
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); virtual;
    procedure HandleSessionUpdate(Params: TJsonObject); virtual;
    
    property ACPClient: TACPClient read FACPClient;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Connect; override;
    procedure Stop; override;
    
    procedure ReplyPermission(const ID, OptionId: string);
    procedure SetSessionLogPath(const SessionId, APath: string);
    procedure StartRestoration(const SessionId: string);
    procedure FinalizeRestoration(const SessionId: string);
    
    property OnRawData: TACPRawDataEvent read FOnRawData write FOnRawData;
    property OnPermissionRequest: TAgentPermissionRequestEvent read FOnPermissionRequest write FOnPermissionRequest;
    property OnSessionMetadataUpdate: TSessionMetadataUpdateEvent read FOnSessionMetadataUpdate write FOnSessionMetadataUpdate;
    property Sessions: TDictionary<string, TSessionData> read FSessions;
  end;

implementation

uses
  uConversationService, uMain, uSessionManager;

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
  FSessions.Clear;
end;

procedure TACPAgent.Stop;
begin
  if Assigned(FACPClient) then
    FACPClient.Stop;
end;

procedure TACPAgent.SetSessionLogPath(const SessionId, APath: string);
var
  Data: TSessionData;
begin
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);
  Data.LogPath := APath;
  FSessions.AddOrSetValue(SessionId, Data);
end;

procedure TACPAgent.StartRestoration(const SessionId: string);
var
  Data: TSessionData;
begin
  if FSessions.TryGetValue(SessionId, Data) then
  begin
    Data.IsRestoring := True;
    FSessions.AddOrSetValue(SessionId, Data);
  end;
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

procedure TACPAgent.HandleInternalReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin
  DoReceive(ID, Method, Params, ResultObj, ErrorObj);
end;

procedure TACPAgent.DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin
  if (ID = '') and (Method = 'session/update') then
  begin
    HandleSessionUpdate(Params);
    Exit;
  end;

  if (ID <> '') and (Method <> '') then
  begin
    if Method = 'fs/read_text_file' then HandleFSRead(ID, Method, Params)
    else if Method = 'fs/write_text_file' then HandleFSWrite(ID, Method, Params)
    else if Method = 'session/request_permission' then HandleRequestPermission(ID, Method, Params);
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
begin
  LSID := Params.S['sessionId'];
  LToolCall := Params.O['toolCall'];
  
  if Assigned(FOnPermissionRequest) then
    FOnPermissionRequest(Self, ID, Method, LSID, LToolCall)
  else
    ReplyPermission(ID, 'cancel');
end;

procedure TACPAgent.HandleSessionUpdate(Params: TJsonObject);
var
  UpdateObj, ContentObj: TJsonObject;
  UpdateType, ChunkText, SessionId, CleanType: string;
  Data: TSessionData;
  I: Integer;
begin
  if not Assigned(Params) or not Params.Contains('update') then Exit;
  
  SessionId := Params.S['sessionId'];
  if SessionId = '' then Exit;

  if Params.Items[Params.IndexOf('update')].Typ <> jdtObject then Exit;
  UpdateObj := Params.O['update'];
  UpdateType := UpdateObj.S['sessionUpdate'];
  
  if not FSessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);

  if UpdateType = 'available_commands_update' then
  begin
    if UpdateObj.Contains('availableCommands') then
    begin
      Data.CommandsJson := UpdateObj.A['availableCommands'].ToJSON(False);
      FSessions.AddOrSetValue(SessionId, Data);
      if Assigned(FOnSessionMetadataUpdate) then
        FOnSessionMetadataUpdate(Self, SessionId);
    end;
    Exit;
  end;

  if UpdateObj.Contains('content') then
  begin
    ChunkText := '';
    I := UpdateObj.IndexOf('content');
    case UpdateObj.Items[I].Typ of
      jdtObject: 
        begin
          ContentObj := UpdateObj.O['content'];
          ChunkText := ContentObj.S['text'];
        end;
      jdtArray:
        begin
          for I := 0 to UpdateObj.A['content'].Count - 1 do
            if UpdateObj.A['content'].Items[I].Typ = jdtObject then
              ChunkText := ChunkText + UpdateObj.A['content'].O[I].S['text'];
        end;
    end;
    
    CleanType := '';
    if UpdateType = 'agent_thought_chunk' then CleanType := 'thought'
    else if UpdateType = 'agent_message_chunk' then CleanType := 'message'
    else if UpdateType = 'user_message_chunk' then CleanType := 'user';

    if CleanType <> '' then
    begin
      if Data.LastChunkType <> CleanType then
      begin
        Data.CurrentBlockText := '';
        Data.LastChunkType := CleanType;
      end;
      
      Data.CurrentBlockText := Data.CurrentBlockText + ChunkText;
      
      if CleanType = 'thought' then
      begin
        Data.FullThought := Data.FullThought + ChunkText;
        FSessions.AddOrSetValue(SessionId, Data);
        DoThoughtChunk(SessionId, ChunkText, Data.CurrentBlockText);
      end
      else if CleanType = 'message' then
      begin
        Data.FullMessage := Data.FullMessage + ChunkText;
        FSessions.AddOrSetValue(SessionId, Data);
        DoMessageChunk(SessionId, ChunkText, Data.CurrentBlockText);
      end
      else if CleanType = 'user' then
      begin
        FSessions.AddOrSetValue(SessionId, Data);
        DoMessageChunk(SessionId, ChunkText, 'USER:' + Data.CurrentBlockText);
      end;
    end;
  end;
end;

procedure TACPAgent.HandleInternalRawData(Sender: TObject; const Direction, RawText: string);
begin
  if Assigned(FOnRawData) then 
    FOnRawData(Self, Direction, RawText);
end;

procedure TACPAgent.HandleInternalTerminated(Sender: TObject; ExitCode: Cardinal);
begin
  State := asDisconnected;
  FSessions.Clear;
  DoStatusChange('Process Terminated. Code: ' + IntToStr(ExitCode));
end;

end.
