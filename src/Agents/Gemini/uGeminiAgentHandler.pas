unit uGeminiAgentHandler;

interface

uses
  System.Classes, System.SysUtils, uAgentHandler, uAgent, uGeminiAgent, uSessionManager, uAgentTypes;

type
  TGeminiAgentHandler = class(TAgentHandler)
  public
    procedure CreateNewSession(const AWorkspaceDir: string); override;
    procedure ResumeSession(ASession: TSessionInfo); override;
  end;

implementation

uses
  uACPAgent, uConversationService, FMX.Forms, JsonDataObjects, uAgentControl;

procedure TGeminiAgentHandler.ResumeSession(ASession: TSessionInfo);
var
  LGemini: TGeminiAgent;
begin
  if not (FAgent is TGeminiAgent) or not Assigned(ASession) then Exit;
  LGemini := TGeminiAgent(FAgent);

  ASession.IsLoading := True;
  ASession.IsRestoring := True;
  if Assigned(FAgentControl) then
    (FAgentControl as TAgentControl).UpdateSession(ASession);

  TThread.CreateAnonymousThread(procedure
  begin
    try
      // 1. Ensure Connected (Start process)
      if not LGemini.IsConnected then
      begin
        if not LGemini.Start then
        begin
           TThread.Queue(nil, TThreadProcedure(procedure begin
             ASession.IsLoading := False; ASession.IsRestoring := False;
             if Assigned(FAgentControl) then (FAgentControl as TAgentControl).UpdateSessionList;
           end));
           Exit;
        end;
      end;

      // 2. Ensure Initialized (Ready)
      if LGemini.State <> asReady then
      begin
        LGemini.Initialize;
      end;

      // 3. Proceed with LoadSession if Ready
      if LGemini.State = asReady then
      begin
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          LGemini.Workspace := ASession.Cwd;
          LGemini.LoadSession(ASession.SessionId, procedure(SessionId: string)
          var LSid: string;
          begin
            LSid := SessionId;
            TThread.Queue(nil, TThreadProcedure(procedure
            begin
              if LSid = '' then
              begin
                if Assigned(FAgentControl) then
                  (FAgentControl as TAgentControl).DeleteSession(ASession);
              end
              else
              begin
                LGemini.SetSessionLogPath(LSid, ASession.LogPath);
                ASession.IsLoading := False;
                ASession.IsRestoring := False;
                ASession.IsActive := True;
                ASession.LastHistoryTick := 0;
                if Assigned(FAgentControl) then
                begin
                  (FAgentControl as TAgentControl).UpdateSession(ASession);
                  (FAgentControl as TAgentControl).UpdateFileList(ASession.Cwd);
                end;
              end;
            end));
          end);
        end));
      end
      else
      begin
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          if Assigned(FAgentControl) then
            (FAgentControl as TAgentControl).DeleteSession(ASession);
        end));
      end;
    except
      on E: Exception do
      begin
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          if Assigned(FAgentControl) then
            (FAgentControl as TAgentControl).DeleteSession(ASession);
        end));
      end;
    end;
  end).Start;
end;

procedure TGeminiAgentHandler.CreateNewSession(const AWorkspaceDir: string);
var
  LGemini: TGeminiAgent;
  LPendingId: string;
  LPendingSession: TSessionInfo;
begin
  if not (FAgent is TGeminiAgent) then Exit;
  LGemini := TGeminiAgent(FAgent);
  
  LPendingId := 'pending-' + TGuid.NewGuid.ToString;
  LPendingSession := FSessionMgr.AddSession(LGemini, atGemini, LPendingId, FSessionMgr.GetUniqueSessionName('New Chat'), AWorkspaceDir);
  LPendingSession.IsLoading := True;
  FSessionMgr.SelectSession(LPendingSession);
  
  if Assigned(FAgentControl) then
  begin
    (FAgentControl as TAgentControl).ExecuteJS('window.ACP.clearChat()');
    (FAgentControl as TAgentControl).AddSession(LPendingSession); // Add the pending session to sidebar
    (FAgentControl as TAgentControl).UpdateFileList(AWorkspaceDir);
  end;

  TThread.CreateAnonymousThread(procedure
  begin
    try
      // 1. Ensure Connected (Start process)
      if not LGemini.IsConnected then
      begin
        if not LGemini.Start then
        begin
          TThread.Queue(nil, TThreadProcedure(procedure begin
            if Assigned(FAgentControl) then
              (FAgentControl as TAgentControl).DeleteSession(LPendingSession);
          end));
          Exit;
        end;
      end;

      // 2. Ensure Initialized (Ready)
      if LGemini.State <> asReady then
      begin
        LGemini.Initialize;
      end;

      // 3. Proceed with CreateNewSession if Ready
      if LGemini.State = asReady then
      begin
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          LGemini.Workspace := AWorkspaceDir;
          LGemini.CreateNewSession(AWorkspaceDir, '', procedure(SessionId: string)
          var LSid: string;
          begin
            LSid := SessionId;
            TThread.Queue(nil, TThreadProcedure(procedure 
            begin
              if LSid <> '' then begin 
                FSessionMgr.FinalizeSessionId(LPendingSession, LSid); 
                LPendingSession.IsLoading := False; 
                LPendingSession.IsActive := True; 
                LGemini.SetSessionLogPath(LSid, LPendingSession.LogPath); 
                
                if Assigned(FAgentControl) then begin
                  (FAgentControl as TAgentControl).UpdateSession(LPendingSession); // Use UpdateSession instead of UpdateSessionList
                  (FAgentControl as TAgentControl).UpdateFileList(AWorkspaceDir); 
                end;
              end
              else begin
                if Assigned(FAgentControl) then
                  (FAgentControl as TAgentControl).DeleteSession(LPendingSession);
              end;
            end));
          end);
        end));
      end
      else
      begin
        TThread.Queue(nil, TThreadProcedure(procedure begin
          if Assigned(FAgentControl) then
            (FAgentControl as TAgentControl).DeleteSession(LPendingSession);
        end));
      end;
    except
      on E: Exception do
      begin
        TThread.Queue(nil, TThreadProcedure(procedure begin
          if Assigned(FAgentControl) then
            (FAgentControl as TAgentControl).DeleteSession(LPendingSession);
        end));
      end;
    end;
  end).Start;
end;

end.
