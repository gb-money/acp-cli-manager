unit uAgent;

interface

uses
  System.Classes, System.SysUtils;

type
  TAgentState = (asDisconnected, asConnecting, asInitializing, asReady, asError);

  TAgentStatusChangeEvent = procedure(Sender: TObject; const Msg: string) of object;
  TAgentStateChangeEvent = procedure(Sender: TObject; const OldState, NewState: TAgentState) of object;
  TAgentResponseEvent = procedure(Sender: TObject; const SessionId, Text: string) of object;
  TAgentChunkEvent = procedure(Sender: TObject; const SessionId, Chunk, FullText: string) of object;
  TAgentFSWriteEvent = procedure(Sender: TObject; const SessionId, Path, OldContent, NewContent: string) of object;

  TAgent = class(TComponent)
  private
    FAgentName: string;
    FState: TAgentState;
    FWorkspace: string;
    FOnStatusChange: TAgentStatusChangeEvent;
    FOnStateChange: TAgentStateChangeEvent;
    FOnResponse: TAgentResponseEvent;
    FOnMessageChunk: TAgentChunkEvent;
    FOnThoughtChunk: TAgentChunkEvent;
    FOnFSWrite: TAgentFSWriteEvent;
    procedure SetState(const Value: TAgentState);
  protected
    procedure DoStatusChange(const Msg: string);
    procedure DoStateChange(const OldState, NewState: TAgentState);
    procedure DoResponse(const SessionId, Text: string);
    procedure DoMessageChunk(const SessionId, Chunk, FullText: string);
    procedure DoThoughtChunk(const SessionId, Chunk, FullText: string);
    procedure DoFSWrite(const SessionId, Path, OldContent, NewContent: string);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Connect; virtual; abstract;
    procedure Stop; virtual; abstract;
    procedure SendPrompt(const SessionId, AText: string); virtual; abstract;
    
    property AgentName: string read FAgentName write FAgentName;
    property State: TAgentState read FState write SetState;
    property Workspace: string read FWorkspace write FWorkspace;
    
    property OnStatusChange: TAgentStatusChangeEvent read FOnStatusChange write FOnStatusChange;
    property OnStateChange: TAgentStateChangeEvent read FOnStateChange write FOnStateChange;
    property OnResponse: TAgentResponseEvent read FOnResponse write FOnResponse;
    property OnMessageChunk: TAgentChunkEvent read FOnMessageChunk write FOnMessageChunk;
    property OnThoughtChunk: TAgentChunkEvent read FOnThoughtChunk write FOnThoughtChunk;
    property OnFSWrite: TAgentFSWriteEvent read FOnFSWrite write FOnFSWrite;
  end;

implementation

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

procedure TAgent.DoResponse(const SessionId, Text: string);
begin
  if Assigned(FOnResponse) then FOnResponse(Self, SessionId, Text);
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
