unit uAgent;

interface

uses
  System.Classes, System.SysUtils, uAgentTypes, JsonDataObjects;

type
  TAgent = class;
  TSessionInfo = class;

  TAgentState = (asDisconnected, asConnecting, asInitializing, asReady, asError);

  TAgentStatusChangeEvent = procedure(Sender: TObject; const Msg: string) of object;
  TAgentStateChangeEvent = procedure(Sender: TObject; const OldState, NewState: TAgentState) of object;
  TAgentEndTurnEvent = procedure(Sender: TObject; const SessionId, StopReason: string) of object;
  TAgentChunkEvent = procedure(Sender: TObject; const SessionId, Chunk, FullText: string) of object;
  TAgentStreamingEndEvent = procedure(Sender: TObject; const SessionId, AType: string) of object;
  TAgentFSWriteEvent = procedure(Sender: TObject; const SessionId, Path, OldContent, NewContent: string) of object;

  TSessionInfo = class
  public
    Agent: TAgent;
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
    constructor Create(AAgent: TAgent; AType: TAgentType; const ASessionId, AName: string; const ACwd: string = '');
    procedure SaveMetadata;
    procedure LoadMetadata;
    procedure MarkActivity;
    procedure UpdateConversationDate;
  end;

  TAgent = class(TComponent)
  private
    FAgentName: string;
    FAgentType: TAgentType;
    FState: TAgentState;
    FWorkspace: string;
    FOnStatusChange: TAgentStatusChangeEvent;
    FOnStateChange: TAgentStateChangeEvent;
    FOnEndTurn: TAgentEndTurnEvent;
    FOnMessageChunk: TAgentChunkEvent;
    FOnThoughtChunk: TAgentChunkEvent;
    FOnStreamingEnd: TAgentStreamingEndEvent;
    FOnFSWrite: TAgentFSWriteEvent;
    procedure SetState(const Value: TAgentState);
  protected
    function GetSessionList: TArray<string>; virtual; abstract;
    procedure DoStatusChange(const Msg: string);
    procedure DoStateChange(const OldState, NewState: TAgentState);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Connect; virtual; abstract;
    procedure Initialize; virtual; abstract;
    procedure Stop; virtual; abstract;
    procedure SendPrompt(const SessionId, AText: string); virtual; abstract;
    
    procedure DoEndTurn(const SessionId, StopReason: string); virtual;
    procedure DoMessageChunk(const SessionId, Chunk, FullText: string);
    procedure DoThoughtChunk(const SessionId, Chunk, FullText: string);
    procedure DoStreamingEnd(const SessionId, AType: string);
    procedure DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
    
    property AgentName: string read FAgentName write FAgentName;
    property AgentType: TAgentType read FAgentType write FAgentType;
    property State: TAgentState read FState write SetState;
    property Workspace: string read FWorkspace write FWorkspace;
    property SessionList: TArray<string> read GetSessionList;
    
    property OnStatusChange: TAgentStatusChangeEvent read FOnStatusChange write FOnStatusChange;
    property OnStateChange: TAgentStateChangeEvent read FOnStateChange write FOnStateChange;
    property OnEndTurn: TAgentEndTurnEvent read FOnEndTurn write FOnEndTurn;
    property OnMessageChunk: TAgentChunkEvent read FOnMessageChunk write FOnMessageChunk;
    property OnThoughtChunk: TAgentChunkEvent read FOnThoughtChunk write FOnThoughtChunk;
    property OnStreamingEnd: TAgentStreamingEndEvent read FOnStreamingEnd write FOnStreamingEnd;
    property OnFSWrite: TAgentFSWriteEvent read FOnFSWrite write FOnFSWrite;
  end;

implementation

uses
  System.IOUtils;

{ TSessionInfo }

constructor TSessionInfo.Create(AAgent: TAgent; AType: TAgentType; const ASessionId, AName: string; const ACwd: string);
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
  LastConversationDate := 0; // Initialize to 0 (empty)
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

{ TAgent }

constructor TAgent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FState := asDisconnected;
end;

procedure TAgent.DoMessageChunk(const SessionId, Chunk, FullText: string);
begin
  if Assigned(FOnMessageChunk) then FOnMessageChunk(Self, SessionId, Chunk, FullText);
end;

procedure TAgent.DoEndTurn(const SessionId, StopReason: string);
begin
  if Assigned(FOnEndTurn) then FOnEndTurn(Self, SessionId, StopReason);
end;

procedure TAgent.DoStateChange(const OldState, NewState: TAgentState);
begin
  if Assigned(FOnStateChange) then FOnStateChange(Self, OldState, NewState);
end;

procedure TAgent.DoStatusChange(const Msg: string);
begin
  if Assigned(FOnStatusChange) then FOnStatusChange(Self, Msg);
end;

procedure TAgent.DoThoughtChunk(const SessionId, Chunk, FullText: string);
begin
  if Assigned(FOnThoughtChunk) then FOnThoughtChunk(Self, SessionId, Chunk, FullText);
end;

procedure TAgent.DoStreamingEnd(const SessionId, AType: string);
begin
  if Assigned(FOnStreamingEnd) then FOnStreamingEnd(Self, SessionId, AType);
end;

procedure TAgent.DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
begin
  if Assigned(FOnFSWrite) then FOnFSWrite(Self, SessionId, Path, OldContent, NewContent);
end;

procedure TAgent.SetState(const Value: TAgentState);
var
  OldState: TAgentState;
begin
  if FState <> Value then
  begin
    OldState := FState;
    FState := Value;
    DoStateChange(OldState, FState);
  end;
end;

end.
