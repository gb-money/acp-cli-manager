unit uAgentTypes;

interface

uses
  System.Classes, JsonDataObjects;

type
  TAgentType = (atGemini, atClaude, atCodex);
  TAgentState = (asDisconnected, asConnecting, asInitializing, asReady, asError);
  TRPCDirection = (rdIncoming, rdOutgoing, rdInternal);

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

implementation

end.
