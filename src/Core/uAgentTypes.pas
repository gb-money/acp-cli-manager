unit uAgentTypes;

interface

uses
  System.Classes, JsonDataObjects;

type
  TAgentType = (atGemini, atClaude, atCodex);
  
  TRPCDirection = (rdIncoming, rdOutgoing, rdInternal);

  TAgentPermissionRequestEvent = procedure(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray) of object;
  TSessionMetadataUpdateEvent = procedure(Sender: TObject; const SessionId: string) of object;
  TAgentRPCEvent = procedure(Sender: TObject; ADirection: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const ARawText: string) of object;

implementation

end.
