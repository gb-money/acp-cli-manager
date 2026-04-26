unit uGeminiAgentHandler;

interface

uses
  System.Classes, System.SysUtils, uAgentHandler, uAgentTypes, uSessionManager, JsonDataObjects;

type
  TGeminiAgentHandler = class(TAgentHandler)
  public
    procedure CreateNewSession(const AWorkspaceDir: string); override;
    procedure Prompt(ASession: TSessionInfo; const AText: string); override;
    procedure ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray); override;
  end;

implementation

uses
  uConversationService, FMX.Forms, uACPProtocol,
  System.RegularExpressions, System.IOUtils;

procedure TGeminiAgentHandler.CreateNewSession(const AWorkspaceDir: string);
begin
  // Placeholder
end;

procedure TGeminiAgentHandler.ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
begin
  TThread.Queue(nil, TThreadProcedure(procedure
  begin
    if Assigned(FAgentControl) then
      FAgentControl.ShowPermissionUI(SessionId, ID, Method, ToolCall.ToJSON(False), Options.ToJSON(False));
  end));
end;

procedure TGeminiAgentHandler.Prompt(ASession: TSessionInfo; const AText: string);
begin
  if not Assigned(FAgent) or not Assigned(ASession) then Exit;
  FAgent.SendPrompt(ASession.SessionId, AText);
end;

end.
