unit uGeminiAgentHandler;

interface

uses
  System.Classes, System.SysUtils, uAgentHandler, uAgent, uGeminiAgent, uSessionManager, uAgentTypes, JsonDataObjects;

type
  TGeminiAgentHandler = class(TAgentHandler)
  public
    procedure CreateNewSession(const AWorkspaceDir: string); override;
    procedure ResumeSession(ASession: TSessionInfo); override;
    procedure Prompt(ASession: TSessionInfo; const AText: string); override;
    procedure ProcessRequestPermission(const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray); override;
    procedure EndTurn(ASession: TSessionInfo; const StopReason: string);
  end;

implementation

uses
  uACPAgent, uConversationService, FMX.Forms, uAgentControl,
  System.RegularExpressions, System.IOUtils;

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
        LGemini.Workspace := AWorkspaceDir;
        LGemini.CreateNewSession(AWorkspaceDir, '', procedure(SessionId: string)
        var LSid: string;
        begin
          LSid := SessionId;
          TThread.Queue(nil, TThreadProcedure(procedure 
          var
            LOldId: string;
          begin
            if LSid <> '' then begin 
              // 1. Capture old ID and Update state
              LOldId := LPendingSession.SessionId;
              LPendingSession.IsLoading := False; 
              LPendingSession.IsActive := True; 
              
              // 2. Finalize to real Session ID (Back-end)
              FSessionMgr.FinalizeSessionId(LPendingSession, LSid); 
              LGemini.SetSessionLogPath(LSid, LPendingSession.LogPath); 
              
              // 3. Sync UI: Remove old ID entry and Add new finalized one
              if Assigned(FAgentControl) then begin
                (FAgentControl as TAgentControl).DeleteSessionUI(LOldId);
                (FAgentControl as TAgentControl).AddSession(LPendingSession); 
                (FAgentControl as TAgentControl).UpdateFileList(AWorkspaceDir); 
              end;
            end
            else begin
              if Assigned(FAgentControl) then
                (FAgentControl as TAgentControl).DeleteSession(LPendingSession);
            end;
          end));
        end);
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
  Data: TSessionData;
  LParams, ItemObj: TJsonObject;
  PromptArr: TJsonArray;
  LMatchValue, LPart: string;
  LFilePath, LFileContent: string;
  LLastPos: Integer;
  LStream: TFileStream;
  LBytes: TBytes;
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LWorkspaceName: string;
  LSid: string;
begin
  if not (FAgent is TGeminiAgent) or not Assigned(ASession) then Exit;
  LGemini := TGeminiAgent(FAgent);
  LSid := ASession.SessionId;

  if not LGemini.Sessions.TryGetValue(LSid, Data) then
    Data := Default(TSessionData);

  Data.FullThought := '';
  Data.FullMessage := '';
  Data.CurrentBlockText := '';
  Data.LastChunkType := '';
  Data.IsProcessing := True; 
  LGemini.Sessions.AddOrSetValue(LSid, Data);

  LParams := TJsonObject.Create;
  try
    LParams.S['sessionId'] := LSid;
    PromptArr := LParams.A['prompt'];

    LWorkspaceName := TPath.GetFileName(ExcludeTrailingPathDelimiter(LGemini.Workspace));

    LLastPos := 1;
    LMatches := TRegEx.Matches(AText, '(@"(?:[^"]+)"|@[^\s\xa0\n]+)');
    
    for LMatch in LMatches do
    begin
      if LMatch.Index > LLastPos then
      begin
        LPart := Copy(AText, LLastPos, LMatch.Index - LLastPos);
        if LPart <> '' then
        begin
          ItemObj := PromptArr.AddObject;
          ItemObj.S['type'] := 'text';
          ItemObj.S['text'] := LPart;
        end;
      end;

      LMatchValue := LMatch.Value;
      LFilePath := Trim(LMatchValue.Substring(1)); 
      
      if LFilePath.StartsWith('"') and LFilePath.EndsWith('"') then
        LFilePath := Copy(LFilePath, 2, Length(LFilePath) - 2);

      LFilePath := LFilePath.Replace('/', PathDelim);

      if LFilePath.StartsWith(LWorkspaceName + PathDelim, True) then
        LFilePath := LFilePath.Substring(Length(LWorkspaceName) + 1);

      if not TPath.IsPathRooted(LFilePath) then
        LFilePath := TPath.GetFullPath(TPath.Combine(LGemini.Workspace, LFilePath));

      LFileContent := '';
      if TFile.Exists(LFilePath) then
      begin
        try
          LStream := TFileStream.Create(LFilePath, fmOpenRead or fmShareDenyNone);
          try
            if LStream.Size > 0 then
            begin
              SetLength(LBytes, LStream.Size);
              LStream.ReadBuffer(LBytes[0], LStream.Size);
              LFileContent := TEncoding.UTF8.GetString(LBytes);
            end;
          finally LStream.Free; end;
        except
        end;
      end;

      ItemObj := PromptArr.AddObject;
      ItemObj.S['type'] := 'resource';
      with ItemObj.O['resource'] do
      begin
        S['text'] := LFileContent;
        S['uri'] := 'file:///' + LFilePath.Replace('\', '/');
      end;

      LLastPos := LMatch.Index + LMatch.Length;
    end;

    if LLastPos <= Length(AText) then
    begin
      LPart := Copy(AText, LLastPos, MaxInt);
      if LPart <> '' then
      begin
        ItemObj := PromptArr.AddObject;
        ItemObj.S['type'] := 'text';
        ItemObj.S['text'] := LPart;
      end;
    end;
    
    if PromptArr.Count = 0 then
    begin
      ItemObj := PromptArr.AddObject;
      ItemObj.S['type'] := 'text';
      ItemObj.S['text'] := AText;
    end;

    // Use a captured session to ensure the correct session is unlocked 
    // regardless of the current ActiveSession in FSessionMgr.
    var LTargetSession := ASession;
    LGemini.ACPClient.Send('session/prompt', LParams,
      procedure(AResponse: TJsonObject)
      var
        LD_Callback: TSessionData;
        LStopReason: string;
      begin
        if LGemini.Sessions.TryGetValue(LSid, LD_Callback) then
        begin
          LD_Callback.IsProcessing := False; 
          LGemini.Sessions.AddOrSetValue(LSid, LD_Callback);
        end;

        if Assigned(AResponse) and not AResponse.Contains('error') then
        begin
          LStopReason := AResponse.O['result'].S['stopReason'];
          
          // CRITICAL: Only unlock UI if stopReason is end_turn
          if SameText(LStopReason, 'end_turn') then
          begin
            TThread.Queue(nil, TThreadProcedure(procedure
            begin
              EndTurn(LTargetSession, LStopReason);
            end));
          end;
        end;
      end);
  finally LParams.Free; end;
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
