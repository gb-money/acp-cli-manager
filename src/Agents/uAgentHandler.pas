unit uAgentHandler;

interface

uses
  System.Classes, System.SysUtils, uAgent, uSessionManager, JsonDataObjects;

type
  IAgentControl = interface
    ['{B7E7B6C4-3D3C-4C8B-8F7E-9C8B7E7B6C4B}']
    procedure UpdateSession(ASession: TSessionInfo);
    procedure UpdateSessionList;
    procedure UpdateFileList(const ARootPath: string = '');
    procedure ShowPermissionUI(const ASessionId, AID, AMethod, AToolCallJson, AOptionsJson: string);
    procedure StartStreaming(const ASessionId, AType: string);
    procedure EndStreaming(const ASessionId, AType: string);
    procedure ReceiveMessage(const ASessionId, AContent: string);
    procedure ExecuteJS(const AScript: string);
  end;

  TAgentHandler = class
  protected
    FSessionMgr: TSessionManager;
    FAgent: TAgent;
    FAgentControl: IAgentControl;
  public
    constructor Create(ASessionMgr: TSessionManager; AAgent: TAgent; AAgentControl: IAgentControl); virtual;
    procedure CreateNewSession(const AWorkspaceDir: string); virtual; abstract;
    procedure ResumeSession(ASession: TSessionInfo); virtual; abstract;
    procedure Prompt(ASession: TSessionInfo; const AText: string); virtual; abstract;
    procedure ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray); virtual; abstract;
  end;

implementation

constructor TAgentHandler.Create(ASessionMgr: TSessionManager; AAgent: TAgent; AAgentControl: IAgentControl);
begin
  FSessionMgr := ASessionMgr;
  FAgent := AAgent;
  FAgentControl := AAgentControl;
end;

end.
