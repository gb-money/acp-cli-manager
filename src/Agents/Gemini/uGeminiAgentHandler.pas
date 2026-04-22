unit uGeminiAgentHandler;

interface

uses
  System.Classes, System.SysUtils, uAgentHandler, uACPAgent, uGeminiAgent, uSessionManager, uAgentTypes, JsonDataObjects;

type
  TGeminiAgentHandler = class(TAgentHandler)
  public
    procedure CreateNewSession(const AWorkspaceDir: string); override;
    procedure Prompt(ASession: TSessionInfo; const AText: string); override;
    procedure ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray); override;
    procedure EndTurn(ASession: TSessionInfo; const StopReason: string);
  end;

implementation

uses
  uConversationService, FMX.Forms, uAgentControl, uACPProtocol,
  System.RegularExpressions, System.IOUtils;

procedure TGeminiAgentHandler.CreateNewSession(const AWorkspaceDir: string);
var
  LPendingId: string;
  LPendingSession: TSessionInfo;
  LParams: TJsonObject;
begin
  if not Assigned(FAgent) then Exit;
  
  LPendingId := 'pending-' + TGuid.NewGuid.ToString;
  LPendingSession := FSessionMgr.AddSession(FAgent, FAgent.AgentType, LPendingId, FSessionMgr.GetUniqueSessionName('New Chat'), AWorkspaceDir);
  LPendingSession.IsLoading := True;
  FSessionMgr.SelectSession(LPendingSession);
  
  if Assigned(FAgentControl) then
  begin
    (FAgentControl as TAgentControl).ExecuteJS('window.ACP.clearChat()');
    (FAgentControl as TAgentControl).AddSession(LPendingSession); 
    (FAgentControl as TAgentControl).UpdateFileList(AWorkspaceDir);
  end;

  FAgent.Workspace := AWorkspaceDir;
  LParams := TACPProtocol.CreateSessionNewParams(AWorkspaceDir, '');
  try
    FAgent.NewSession(LParams);
  finally
    LParams.Free;
  end;
end;

procedure TGeminiAgentHandler.ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
begin
  TThread.Queue(nil, TThreadProcedure(procedure
  begin
    if Assigned(FAgentControl) then
      (FAgentControl as TAgentControl).ShowPermissionUI(SessionId, ID, Method, ToolCall.ToJSON(False), Options.ToJSON(False));
  end));
end;

procedure TGeminiAgentHandler.Prompt(ASession: TSessionInfo; const AText: string);
var
  LGemini: TGeminiAgent;
begin
  if not (FAgent is TGeminiAgent) or not Assigned(ASession) then Exit;
  LGemini := TGeminiAgent(FAgent);
  
  LGemini.SendPrompt(ASession.SessionId, AText);
end;

procedure TGeminiAgentHandler.EndTurn(ASession: TSessionInfo; const StopReason: string);
begin
  if not Assigned(ASession) then Exit;

  if FAgent is TACPAgent then
    TACPAgent(FAgent).EndTurn(ASession.SessionId, StopReason);

  if Assigned(FAgentControl) then
    (FAgentControl as TAgentControl).UpdateSession(ASession);
end;

end.
