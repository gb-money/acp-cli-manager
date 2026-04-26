unit uAgentHandler;

interface

uses
  System.Classes, System.SysUtils, uAgentTypes, uSessionManager, JsonDataObjects;

type
  TAgentHandler = class
  public
    FSessionMgr: TSessionManager;
    FAgent: IACPAgent;
    FAgentControl: IAgentControl;
    constructor Create(ASessionMgr: TSessionManager; AAgent: IACPAgent; AAgentControl: IAgentControl); virtual;
    procedure CreateNewSession(const AWorkspaceDir: string); virtual; abstract;
    procedure Prompt(ASession: TSessionInfo; const AText: string); virtual; abstract;
    procedure ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray); virtual; abstract;
  end;

implementation

constructor TAgentHandler.Create(ASessionMgr: TSessionManager; AAgent: IACPAgent; AAgentControl: IAgentControl);
begin
  FSessionMgr := ASessionMgr;
  FAgent := AAgent;
  FAgentControl := AAgentControl;
end;

end.
