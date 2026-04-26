unit uAgentTypes;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, JsonDataObjects;

type
  TAgentType = (atGemini, atClaude, atCodex);
  TAgentState = (asDisconnected, asConnecting, asInitializing, asReady, asError);
  TRPCDirection = (rdIncoming, rdOutgoing, rdInternal);

  TAgentModelInfo = record
    ModelId: string;
    Name: string;
    Description: string;
  end;

  TAgentModeInfo = record
    ModeId: string;
    Name: string;
    Description: string;
  end;

  TSessionInfo = class
  private
    FAgent: TObject;
    FAgentName: string;
    FAgentType: TAgentType;
    FSessionId: string;
    FName: string;
    FIsLoading: Boolean;
    FIsRestoring: Boolean;
    FIsActive: Boolean;
    FIsWaitForResponse: Boolean;
    FIsPinned: Boolean;
    FIsThoughtStreaming: Boolean;
    FIsMessageStreaming: Boolean;
    FLogPath: string;
    FDiffsPath: string;
    FCwd: string;
    FCreatedAt: TDateTime;
    FLastConversationDate: TDateTime;
    FLastHistoryTick: Cardinal;
  public
    constructor Create(AAgent: TObject; const AAgentName: string; AType: TAgentType; const ASessionId, AName: string; const ACwd: string = '');
    procedure SaveMetadata;
    procedure LoadMetadata;
    procedure MarkActivity;
    procedure UpdateConversationDate;

    property Agent: TObject read FAgent write FAgent;
    property AgentName: string read FAgentName write FAgentName;
    property AgentType: TAgentType read FAgentType write FAgentType;
    property SessionId: string read FSessionId write FSessionId;
    property Name: string read FName write FName;
    property IsLoading: Boolean read FIsLoading write FIsLoading;
    property IsRestoring: Boolean read FIsRestoring write FIsRestoring;
    property IsActive: Boolean read FIsActive write FIsActive;
    property IsWaitForResponse: Boolean read FIsWaitForResponse write FIsWaitForResponse;
    property IsPinned: Boolean read FIsPinned write FIsPinned;
    property IsThoughtStreaming: Boolean read FIsThoughtStreaming write FIsThoughtStreaming;
    property IsMessageStreaming: Boolean read FIsMessageStreaming write FIsMessageStreaming;
    property LogPath: string read FLogPath write FLogPath;
    property DiffsPath: string read FDiffsPath write FDiffsPath;
    property Cwd: string read FCwd write FCwd;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property LastConversationDate: TDateTime read FLastConversationDate write FLastConversationDate;
    property LastHistoryTick: Cardinal read FLastHistoryTick write FLastHistoryTick;
  end;

  // Agent Events
  TAgentStatusChangeEvent = procedure(Sender: TObject; const Msg: string) of object;
  TAgentStateChangeEvent = procedure(Sender: TObject; const OldState, NewState: TAgentState) of object;
  TAgentEndTurnEvent = procedure(Sender: TObject; const SessionId, StopReason: string) of object;
  TAgentChunkEvent = procedure(Sender: TObject; const SessionId, Chunk, FullText: string) of object;
  TAgentStreamingEndEvent = procedure(Sender: TObject; const SessionId, AType: string) of object;
  TAgentFSWriteEvent = procedure(Sender: TObject; const SessionId, Path, OldContent, NewContent: string) of object;

  TAgentPermissionRequestEvent = procedure(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray) of object;
  TSessionMetadataUpdateEvent = procedure(Sender: TObject; const SessionId: string) of object;
  TSessionPropertyUpdateEvent = procedure(Sender: TObject; const SessionId, PropertyName, NewValue: string) of object;
  TAgentRPCEvent = procedure(Sender: TObject; ADirection: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const ARawText: string) of object;
  
  // ACP Specific Events
  TNewSessionEvent = procedure(Sender: TObject; AResponse: TJsonObject) of object;
  TSessionResumedEvent = procedure(Sender: TObject; const SessionId: string) of object;

  IAgentObserver = interface
    ['{7E1D8A21-5B3E-4B7E-A79B-8902A9E58A4F}']
    procedure OnAgentMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure OnAgentThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure OnAgentStreamingEnd(Sender: TObject; const SessionId, AType: string);
    procedure OnAgentEndTurn(Sender: TObject; const SessionId, StopReason: string);
    procedure OnAgentPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
    procedure OnAgentSessionMetadataUpdate(Sender: TObject; const SessionId: string);
    procedure OnAgentPropertyUpdate(Sender: TObject; const SessionId, PropertyName, NewValue: string);
    procedure OnAgentRawData(Sender: TObject; Direction: TRPCDirection; const SessionId: string; AObj: TJsonObject; const RawText: string);
    procedure OnAgentNewSession(Sender: TObject; AResponse: TJsonObject);
    procedure OnAgentSessionResumed(Sender: TObject; const SessionId: string);
    procedure OnAgentFSWrite(Sender: TObject; const SessionId, Path, OldContent, NewContent: string);
    procedure OnAgentStateChange(Sender: TObject; const OldState, NewState: TAgentState);
  end;

implementation

{ TSessionInfo }

constructor TSessionInfo.Create(AAgent: TObject; const AAgentName: string; AType: TAgentType; const ASessionId, AName: string; const ACwd: string);
begin
  Agent := AAgent;
  AgentName := AAgentName;
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
  LDir := TPath.Combine(LDir, AgentName.ToLower + '-cli');
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
  LDir := TPath.Combine(LDir, AgentName.ToLower + '-cli');
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

end.
