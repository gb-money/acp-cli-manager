unit uAgentControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, uSessionManager, uAgent, uACPAgent,
  System.NetEncoding, FMX.Dialogs, System.Actions, FMX.ActnList, System.IOUtils,
  System.UITypes, System.Generics.Collections, System.Generics.Defaults, uWebACPCommandHandler,
  uAgentHandler, JsonDataObjects, uAgentTypes, uACPClient;

type
  TNewChatEvent = procedure(Sender: TObject; const AgentName: string) of object;

  TAgentControl = class(TInterfacedObject, IAgentControl)
  protected
    { IInterface }
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  private
    FWebBrowser: TWebBrowser;
    FSessionMgr: TSessionManager;
    FWorkspaceRoot: string;
    FOnNewChat: TNewChatEvent;
    FCommandHandler: TWebACPCommandHandler;
    FAgentList: TDictionary<TAgentType, TAgent>;
    FHandlers: TDictionary<TAgentType, TAgentHandler>;
    FOnRawData: TAgentRPCEvent;
    
    // Agent Event Handlers (UI Routing & Logging)
    procedure DoAgentMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoAgentThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoAgentStreamingEnd(Sender: TObject; const SessionId, AType: string);
    procedure DoAgentEndTurn(Sender: TObject; const SessionId, StopReason: string);
    procedure DoAgentPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
    procedure DoAgentSessionMetadataUpdate(Sender: TObject; const SessionId: string);
    procedure DoAgentPropertyUpdate(Sender: TObject; const SessionId, PropertyName, NewValue: string);
    procedure DoAgentRawData(Sender: TObject; Direction: TRPCDirection; const SessionId: string; AObj: TJsonObject; const RawText: string);
    
    // Service Event Handlers
    procedure DoSessionRestored(Sender: TObject; ASession: TSessionInfo);

    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleInternalLog(Sender: TObject; const LogMsg: string);
    
    procedure HandleNewChat(const Params: TDictionary<string, string>);
    procedure HandleSendMessage(const Params: TDictionary<string, string>);
    procedure HandleAction(const Params: TDictionary<string, string>);
    procedure HandleSelectSession(const Params: TDictionary<string, string>); overload;
    procedure HandleSelectSession(ASession: TSessionInfo); overload;
    procedure HandleDeleteSession(const Params: TDictionary<string, string>);
    procedure HandleChangeModel(const Params: TDictionary<string, string>);
    procedure HandlePermissionResponse(const Params: TDictionary<string, string>);
    procedure HandleCancelPrompt(const Params: TDictionary<string, string>);
    procedure HandleResumeSession(const Params: TDictionary<string, string>);
    procedure HandleNextPrevSession(ADir: Integer);
    procedure HandleGetFileContent(const Params: TDictionary<string, string>);
    procedure HandleGetFileHistory(const Params: TDictionary<string, string>);
    
    function IsIgnoredDir(const ADirName: string): Boolean;
    function GetWorkspaceDisplayText(const ACwd: string): string;
    function SessionToJSON(ASessionInfo: TSessionInfo): TJsonObject;
    function GetHandler(AType: TAgentType): TAgentHandler;
  public
    constructor Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    procedure RegisterAgent(AType: TAgentType; AAgent: TAgent);
    procedure HandleOpenFileDialog(const Params: TDictionary<string, string>);
    procedure AddSession(ASession: TSessionInfo);
    procedure DeleteSession(ASession: TSessionInfo);
    procedure DeleteSessionUI(const ASessionId: string);
    procedure LoadAllSessions;
    procedure UpdateSessionList;
    procedure UpdateSession(ASession: TSessionInfo);
    procedure UpdateMessageStreaming(const ASessionId, AContent: string; const ARole: string = 'ai'; const AStopReason: string = '');
    procedure UpdateThoughtStreaming(const ASessionId, AContent: string);
    procedure StartStreaming(const ASessionId, AType: string);
    procedure EndStreaming(const ASessionId, AType: string);
    procedure ReceiveMessage(const ASessionId, AContent: string);
    procedure BreakGrouping;
    procedure UpdateFileList(const ARootPath: string = '');
    procedure ShowPermissionUI(const ASessionId, AID, AMethod, AToolCallJson, AOptionsJson: string);
    procedure ShowTyping(const AShow: Boolean);
    procedure ExecuteJS(const AScript: string);
    property OnNewChat: TNewChatEvent read FOnNewChat write FOnNewChat;
    property OnRawData: TAgentRPCEvent read FOnRawData write FOnRawData;
    property AgentList: TDictionary<TAgentType, TAgent> read FAgentList;
  end;

implementation

uses
  FMX.Forms, uGeminiAgent, System.Types, uConversationService, uDebugRPC, uMain,
  uGeminiAgentHandler;

{ TAgentControl }

function TAgentControl._AddRef: Integer; stdcall;
begin
  Result := -1;
end;

function TAgentControl._Release: Integer; stdcall;
begin
  Result := -1;
end;

constructor TAgentControl.Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
var
  LExeDir: string;
begin
  FWebBrowser := AWebBrowser;
  FSessionMgr := ASessionMgr;
  if Assigned(FSessionMgr) then
    FSessionMgr.OnSessionRestored := DoSessionRestored;

  FAgentList := TDictionary<TAgentType, TAgent>.Create;
  FHandlers := TDictionary<TAgentType, TAgentHandler>.Create;
  
  FCommandHandler := TWebACPCommandHandler.Create;
  FCommandHandler.OnCommand := HandleInternalCommand;
  FCommandHandler.OnLog := HandleInternalLog;

  LExeDir := ExtractFilePath(ParamStr(0));
  if LExeDir.Contains('Win32') or LExeDir.Contains('Win64') then
    FWorkspaceRoot := TPath.GetFullPath(TPath.Combine(LExeDir, '..\..\'))
  else
    FWorkspaceRoot := TPath.GetFullPath(LExeDir);
    
  if not FWorkspaceRoot.EndsWith(PathDelim) then
    FWorkspaceRoot := FWorkspaceRoot + PathDelim;
end;

destructor TAgentControl.Destroy;
var
  LHandler: TAgentHandler;
begin
  for LHandler in FHandlers.Values do LHandler.Free;
  FHandlers.Free;
  FAgentList.Free;
  FCommandHandler.Free;
  inherited;
end;

procedure TAgentControl.RegisterAgent(AType: TAgentType; AAgent: TAgent);
begin
  if Assigned(AAgent) then
  begin
    FAgentList.AddOrSetValue(AType, AAgent);
    AAgent.OnMessageChunk := DoAgentMessageChunk;
    AAgent.OnThoughtChunk := DoAgentThoughtChunk;
    AAgent.OnStreamingEnd := DoAgentStreamingEnd;
    AAgent.OnEndTurn := DoAgentEndTurn;
    if AAgent is TACPAgent then
    begin
      TACPAgent(AAgent).SessionManager := FSessionMgr;
      TACPAgent(AAgent).OnRawData := DoAgentRawData;
      TACPAgent(AAgent).OnPermissionRequest := DoAgentPermissionRequest;
      TACPAgent(AAgent).OnSessionMetadataUpdate := DoAgentSessionMetadataUpdate;
      TACPAgent(AAgent).OnPropertyUpdate := DoAgentPropertyUpdate;
    end;
  end;
end;

procedure TAgentControl.AddSession(ASession: TSessionInfo);
var
  LObj: TJsonObject;
  LBase64: string;
begin
  if not Assigned(ASession) then Exit;
  LObj := SessionToJSON(ASession);
  try
    LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LObj.ToJSON(False))).Replace(#13, '').Replace(#10, '');
    FWebBrowser.EvaluateJavaScript('window.ACP.AddSession("' + LBase64 + '")');
  finally
    LObj.Free;
  end;
end;

procedure TAgentControl.DeleteSession(ASession: TSessionInfo);
begin
  if not Assigned(ASession) then Exit;
  FSessionMgr.DeleteSession(ASession);
  UpdateSessionList; // Refresh the entire list to ensure UI is in sync
end;

procedure TAgentControl.DeleteSessionUI(const ASessionId: string);
begin
  FWebBrowser.EvaluateJavaScript('window.ACP.DeleteSession("' + ASessionId + '")');
end;

procedure TAgentControl.DoAgentRawData(Sender: TObject; Direction: TRPCDirection; const SessionId: string; AObj: TJsonObject; const RawText: string);
var
  LSession: TSessionInfo;
  LDirStr, LMethod: string;
begin
  // 1. Logging Persistence (only if we have a valid session)
  if (Direction <> rdInternal) and (SessionId <> '') then
  begin
    LSession := FSessionMgr.GetSessionById(SessionId);
    if Assigned(LSession) then
    begin
      case Direction of
        rdIncoming: LDirStr := 'IN';
        rdOutgoing: LDirStr := 'OUT';
      else LDirStr := 'SYS';
      end;
      TConversationService.AppendLog(LSession, LDirStr, RawText, False);

      // --- Conditional Conversation Date Update ---
      if Assigned(AObj) then
      begin
        LMethod := AObj.S['method'];
        if (Direction = rdOutgoing) and SameText(LMethod, 'session/prompt') then
          LSession.UpdateConversationDate
        else if (Direction = rdIncoming) then
        begin
           if LMethod.StartsWith('fs/', True) or SameText(LMethod, 'session/request_permission') then
             LSession.UpdateConversationDate;
        end;
      end;
    end;
  end;

  // 2. Relay to subscribers (uMain.DoRawDataForDebug)
  if Assigned(FOnRawData) then
    FOnRawData(Self, Direction, SessionId, AObj, RawText);
end;

procedure TAgentControl.DoAgentMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) and (not LSession.IsRestoring) then
  begin
    LSession.UpdateConversationDate;
    if not LSession.IsMessageStreaming then
      StartStreaming(SessionId, 'message');
      
    ReceiveMessage(SessionId, FullText);
  end;
end;

procedure TAgentControl.DoAgentThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) and (not LSession.IsRestoring) then
  begin
    LSession.UpdateConversationDate;
    if not LSession.IsThoughtStreaming then
      StartStreaming(SessionId, 'thought');
      
    ReceiveMessage(SessionId, FullText);
  end;
end;

procedure TAgentControl.DoAgentStreamingEnd(Sender: TObject; const SessionId, AType: string);
begin
  EndStreaming(SessionId, AType);
end;

procedure TAgentControl.DoAgentEndTurn(Sender: TObject; const SessionId, StopReason: string);
var
  LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) then
  begin
    if LSession.IsThoughtStreaming then EndStreaming(SessionId, 'thought');
    if LSession.IsMessageStreaming then EndStreaming(SessionId, 'message');
  end;
  
  System.Classes.TThread.Queue(nil, TThreadProcedure(procedure 
  begin 
    ShowTyping(False); 
    if Assigned(LSession) then UpdateSession(LSession); 
  end));
end;

procedure TAgentControl.DoAgentPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
var
  LSession: TSessionInfo;
  LHandler: TAgentHandler;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) then
  begin
    // Interrupt streaming if active
    if LSession.IsThoughtStreaming then EndStreaming(SessionId, 'thought');
    if LSession.IsMessageStreaming then EndStreaming(SessionId, 'message');

    LHandler := GetHandler(LSession.AgentType);
    if Assigned(LHandler) then
      LHandler.ProcessRequestPermission(ID, Method, SessionId, ToolCall, Options);
  end;
end;

procedure TAgentControl.DoAgentSessionMetadataUpdate(Sender: TObject; const SessionId: string);
var LSid: string; LSession: TSessionInfo;
begin
  LSid := SessionId;
  System.Classes.TThread.Queue(nil, TThreadProcedure(procedure begin
    LSession := FSessionMgr.GetSessionById(LSid);
    if Assigned(LSession) then begin
      if LSession.IsLoading then begin LSession.IsLoading := False; LSession.IsActive := True; UpdateFileList(LSession.Cwd); end;
      UpdateSession(LSession);
    end;
  end));
end;

procedure TAgentControl.DoAgentPropertyUpdate(Sender: TObject; const SessionId, PropertyName, NewValue: string);
begin
  System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
  begin
    if PropertyName = 'currentModelId' then
      ExecuteJS(Format('window.ACP.changeModel("%s", "%s")', [SessionId, NewValue]));
  end));
end;

procedure TAgentControl.DoSessionRestored(Sender: TObject; ASession: TSessionInfo);
var LCaptured: TSessionInfo;
begin
  LCaptured := ASession;
  System.Classes.TThread.Queue(nil, TThreadProcedure(procedure begin
    if Assigned(LCaptured) then begin UpdateFileList(LCaptured.Cwd); UpdateSessionList; end;
  end));
end;

function TAgentControl.GetHandler(AType: TAgentType): TAgentHandler;
var
  LAgent: TAgent;
begin
  if not FHandlers.TryGetValue(AType, Result) then
  begin
    if FAgentList.TryGetValue(AType, LAgent) then
    begin
      case AType of
        atGemini: Result := TGeminiAgentHandler.Create(FSessionMgr, LAgent, Self);
        else Result := nil;
      end;
      if Assigned(Result) then
        FHandlers.Add(AType, Result);
    end
    else Result := nil;
  end;
end;

procedure TAgentControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'new-chat' then HandleNewChat(Params)
  else if Action = 'send-message' then HandleSendMessage(Params)
  else if Action = 'select-session' then HandleSelectSession(Params)
  else if Action = 'delete-session' then HandleDeleteSession(Params)
  else if Action = 'next-session' then HandleNextPrevSession(1)
  else if Action = 'prev-session' then HandleNextPrevSession(-1)
  else if Action = 'resume-session' then HandleResumeSession(Params)
  else if Action = 'change-model' then HandleChangeModel(Params)
  else if Action = 'permission-response' then HandlePermissionResponse(Params)
  else if Action = 'cancel-prompt' then HandleCancelPrompt(Params)
  else if Action = 'get-file-content' then HandleGetFileContent(Params)
  else if Action = 'open-file-dialog' then HandleOpenFileDialog(Params)
  else if Action = 'get-file-history' then HandleGetFileHistory(Params)
  else if Action = 'action' then HandleAction(Params);
end;

function TAgentControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := FCommandHandler.HandleUrl(AUrl, 'acp-action://');
end;

procedure TAgentControl.HandleNewChat(const Params: TDictionary<string, string>);
var 
  LAgentName, LSelectedDir: string; 
  LType: TAgentType; 
  LHandler: TAgentHandler;
  LPrevActive: TSessionInfo;
  LAgent: TAgent;
begin
  if Params.TryGetValue('agent', LAgentName) then begin
    if Assigned(FOnNewChat) then FOnNewChat(Self, LAgentName);
    if SameText(LAgentName, 'gemini') then LType := atGemini
    else if SameText(LAgentName, 'claude') then LType := atClaude
    else if SameText(LAgentName, 'codex') then LType := atCodex
    else Exit;
    
    // Guard: Prevent creating new chat while agent is initializing
    if FAgentList.TryGetValue(LType, LAgent) then
    begin
      if LAgent.State in [asConnecting, asInitializing] then
      begin
        ExecuteJS(Format('window.ACP.showModal("warning", "%s Initializing", ' +
          '"The agent is currently starting up. Please wait until the initialization is complete before creating a new chat.")', [LAgentName]));
        Exit;
      end;
    end;

    if not SelectDirectory('Select Project Workspace for ' + LAgentName, '', LSelectedDir) then Exit;

    // Deselect current active session to prevent dual-selection UI bug
    LPrevActive := FSessionMgr.ActiveSession;
    if Assigned(LPrevActive) then
    begin
      FSessionMgr.SelectSession(nil);
      UpdateSession(LPrevActive);
    end;

    LHandler := GetHandler(LType);
    if Assigned(LHandler) then LHandler.CreateNewSession(LSelectedDir);
  end;
end;

procedure TAgentControl.HandleResumeSession(const Params: TDictionary<string, string>);
var LSid: string; LTarget: TSessionInfo; LHandler: TAgentHandler;
begin
  if Params.TryGetValue('id', LSid) then begin
    LTarget := FSessionMgr.GetSessionById(LSid);
    if Assigned(LTarget) then begin
       HandleSelectSession(LTarget);
       LHandler := GetHandler(LTarget.AgentType);
       if Assigned(LHandler) then LHandler.ResumeSession(LTarget);
    end;
  end;
end;

procedure TAgentControl.HandleSendMessage(const Params: TDictionary<string, string>);
var LText, LBase64: string; LActive: TSessionInfo; LHandler: TAgentHandler;
begin
  if Params.TryGetValue('text', LText) and (LText <> '') then begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and Assigned(LActive.Agent) then begin
      LActive.IsWaitForResponse := True; UpdateSession(LActive);
      
      LHandler := GetHandler(LActive.AgentType);
      if Assigned(LHandler) then
        LHandler.Prompt(LActive, LText)
      else
        LActive.Agent.SendPrompt(LActive.SessionId, LText);

      // Render user message in UI immediately via JS
      LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LText)).Replace(#13, '').Replace(#10, '');
      ExecuteJS(Format('window.ACP.addUserMessage("%s")', [LBase64]));
      
      ExecuteJS('window.ACP.lastAiMsgId = ""; window.ACP.lastAiThoughtId = ""; window.ACP.lastBlockType = "";');
      ShowTyping(True);
    end;
  end;
end;

procedure TAgentControl.HandleSelectSession(const Params: TDictionary<string, string>);
var LSid: string; begin if Params.TryGetValue('id', LSid) then HandleSelectSession(FSessionMgr.GetSessionById(LSid)); end;

procedure TAgentControl.HandleSelectSession(ASession: TSessionInfo);
var
  LPrevActive: TSessionInfo;
begin
  if Assigned(ASession) then begin
    LPrevActive := FSessionMgr.ActiveSession;
    FSessionMgr.SelectSession(ASession); 
    
    // UI 부분 갱신: 이전 세션의 포커스 해제 및 새 세션의 포커스 설정
    if Assigned(LPrevActive) and (LPrevActive <> ASession) then
      UpdateSession(LPrevActive);
    UpdateSession(ASession);

    var LCaptured := ASession;
    System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
    var LInnerMsg: TJsonArray; LInnerJson, LBase64: string; LBytes: TBytes;
    begin
      if not Assigned(LCaptured) then Exit;
      UpdateFileList(LCaptured.Cwd);
      LInnerMsg := TConversationService.GetConversationsBySessionId(LCaptured);
      try
        LInnerJson := LInnerMsg.ToJSON(False);
        LBytes := TEncoding.UTF8.GetBytes(LInnerJson);
        LBase64 := TNetEncoding.Base64.EncodeBytesToString(LBytes).Replace(#13, '').Replace(#10, '');
        ExecuteJS('window.ACP.loadHistoryBase64("' + LBase64 + '")');
        ExecuteJS('if (document.getElementById("historySidebar") && !document.getElementById("historySidebar").classList.contains("hidden")) window.sendAcp("get-file-history");');
      finally LInnerMsg.Free; end;
    end));
  end;
end;

procedure TAgentControl.HandleDeleteSession(const Params: TDictionary<string, string>);
var LSid: string; LTarget: TSessionInfo;
begin
  if Params.TryGetValue('id', LSid) then begin
    LTarget := FSessionMgr.GetSessionById(LSid);
    if Assigned(LTarget) then DeleteSession(LTarget);
  end;
end;

procedure TAgentControl.HandleNextPrevSession(ADir: Integer);
var LSessions: TList<TSessionInfo>; LActive: TSessionInfo; LIdx, LNextIdx: Integer;
begin
  LSessions := FSessionMgr.GetSessionListSnapshot;
  try
    if LSessions.Count <= 1 then Exit;
    LActive := FSessionMgr.ActiveSession; LIdx := LSessions.IndexOf(LActive);
    if LIdx = -1 then LNextIdx := 0 else LNextIdx := (LIdx + ADir + LSessions.Count) mod LSessions.Count;
    HandleSelectSession(LSessions[LNextIdx]);
  finally LSessions.Free; end;
end;

procedure TAgentControl.HandleAction(const Params: TDictionary<string, string>); begin end;

procedure TAgentControl.HandleChangeModel(const Params: TDictionary<string, string>);
var LModelId: string; LActive: TSessionInfo;
begin
  if Params.TryGetValue('modelId', LModelId) then begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and (LActive.Agent is TGeminiAgent) then begin
      TGeminiAgent(LActive.Agent).ChangeModel(LActive.SessionId, LModelId);
    end;
  end;
end;

procedure TAgentControl.HandlePermissionResponse(const Params: TDictionary<string, string>);
var LID, LOptionId: string; LActive: TSessionInfo;
begin
  if Params.TryGetValue('id', LID) and Params.TryGetValue('optionId', LOptionId) then begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and (LActive.Agent is TACPAgent) then TACPAgent(LActive.Agent).ReplyPermission(LID, LOptionId);
  end;
end;

procedure TAgentControl.HandleCancelPrompt(const Params: TDictionary<string, string>);
var LActive: TSessionInfo;
begin
  LActive := FSessionMgr.ActiveSession;
  if Assigned(LActive) and (LActive.Agent is TGeminiAgent) then begin
    TGeminiAgent(LActive.Agent).CancelPrompt(LActive.SessionId); ShowTyping(False);
  end;
end;

procedure TAgentControl.HandleGetFileContent(const Params: TDictionary<string, string>);
var LRelPath, LFullPath, LContent, LCallbackId, LTargetRoot: string; LObj: TJsonObject; LActive: TSessionInfo;
begin
  if Params.TryGetValue('path', LRelPath) and Params.TryGetValue('callbackId', LCallbackId) then begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and (LActive.Cwd <> '') then LTargetRoot := LActive.Cwd else LTargetRoot := FWorkspaceRoot;
    LFullPath := TPath.Combine(LTargetRoot, LRelPath); LContent := '';
    if TFile.Exists(LFullPath) then LContent := TFile.ReadAllText(LFullPath, TEncoding.UTF8);
    LObj := TJsonObject.Create;
    try
      LObj.S['path'] := LRelPath; LObj.S['content'] := LContent; LObj.S['uri'] := 'file:///' + LFullPath.Replace('\', '/');
      ExecuteJS('window.ACP.onFileContentReceived("' + LCallbackId + '", ' + LObj.ToJSON(False) + ')');
    finally LObj.Free; end;
  end;
end;

procedure TAgentControl.HandleOpenFileDialog(const Params: TDictionary<string, string>);
var LDialog: TOpenDialog; LRelPath, LTargetRoot: string; LActive: TSessionInfo;
begin
  LActive := FSessionMgr.ActiveSession;
  if Assigned(LActive) and (LActive.Cwd <> '') then LTargetRoot := LActive.Cwd else LTargetRoot := FWorkspaceRoot;
  LDialog := TOpenDialog.Create(nil);
  try
    LDialog.Options := LDialog.Options + [System.UITypes.TOpenOption.ofPathMustExist, System.UITypes.TOpenOption.ofFileMustExist];
    if LDialog.Execute then begin
      LRelPath := ExtractRelativePath(LTargetRoot, LDialog.FileName).Replace('\', '/');
      ExecuteJS('window.ACP.applyFile("' + LRelPath + '")');
    end;
  finally LDialog.Free; end;
end;

procedure TAgentControl.HandleGetFileHistory(const Params: TDictionary<string, string>);
var LActive: TSessionInfo; LFiles: TStringDynArray; LPath, LJsonText: string; LArray: TJsonArray; LObj, LItem: TJsonObject; LList: TList<TJsonObject>; I: Integer;
begin
  LActive := FSessionMgr.ActiveSession; if not Assigned(LActive) or (LActive.DiffsPath = '') then Exit;
  LArray := TJsonArray.Create; LList := TList<TJsonObject>.Create;
  try
    if TDirectory.Exists(LActive.DiffsPath) then begin
      LFiles := TDirectory.GetFiles(LActive.DiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
      for LPath in LFiles do begin
        try LJsonText := TFile.ReadAllText(LPath, TEncoding.UTF8); LObj := TJsonObject.Parse(LJsonText) as TJsonObject; if Assigned(LObj) then LList.Add(LObj); except end;
      end;
      LList.Sort(TComparer<TJsonObject>.Construct(function(const Left, Right: TJsonObject): Integer begin Result := CompareText(Right.S['timestamp'], Left.S['timestamp']); end));
      for I := 0 to LList.Count - 1 do begin LItem := LArray.AddObject; LItem.Assign(LList[I]); end;
    end;
    LJsonText := LArray.ToJSON(False);
    System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
    var LBase64: string;
    begin
      LBase64 := TNetEncoding.Base64.Encode(LJsonText).Replace(#13, '').Replace(#10, '');
      ExecuteJS('window.ACP.updateFileHistoryBase64("' + LBase64 + '")');
    end));
  finally for I := 0 to LList.Count - 1 do LList[I].Free; LList.Free; LArray.Free; end;
end;

procedure TAgentControl.HandleInternalLog(Sender: TObject; const LogMsg: string); begin if Assigned(frmDebugRPC) then frmDebugRPC.AddACPLog(LogMsg); end;

procedure TAgentControl.LoadAllSessions;
var LAgent: TAgent; LSessionIds: TArray<string>; LSid: string; LSession: TSessionInfo;
begin
  if not Assigned(FSessionMgr) then Exit;
  for LAgent in FAgentList.Values do begin
    LSessionIds := LAgent.SessionList;
    for LSid in LSessionIds do begin
      LSession := FSessionMgr.AddSession(LAgent, LAgent.AgentType, LSid, 'Loading...');
      if Assigned(LSession) then begin
        LSession.LoadMetadata; if LAgent is TACPAgent then TACPAgent(LAgent).SetSessionLogPath(LSid, LSession.LogPath);
      end;
    end;
  end;
  FSessionMgr.SortSessions;
end;

procedure TAgentControl.UpdateSessionList;
var LArray: TJsonArray; LSession: TSessionInfo; LSessions: TList<TSessionInfo>; LJson, LBase64: string;
begin
  LArray := TJsonArray.Create;
  try
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try for LSession in LSessions do LArray.AddObject.Assign(SessionToJSON(LSession)); finally LSessions.Free; end;
    LJson := LArray.ToJSON(False); LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LJson)).Replace(#13, '').Replace(#10, '');
    ExecuteJS('window.ACP.updateSessionList("' + LBase64 + '")');
  finally LArray.Free; end;
end;

procedure TAgentControl.UpdateSession(ASession: TSessionInfo);
var LObj: TJsonObject; LBase64: string;
begin
  if not Assigned(ASession) then Exit; LObj := SessionToJSON(ASession);
  try LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LObj.ToJSON(False))).Replace(#13, '').Replace(#10, ''); ExecuteJS('window.ACP.updateSession("' + LBase64 + '")'); finally LObj.Free; end;
end;

procedure TAgentControl.UpdateMessageStreaming(const ASessionId, AContent, ARole, AStopReason: string);
var LObj: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := ASessionId; LObj.S['content'] := AContent; LObj.S['role'] := ARole; LObj.S['timestamp'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    if AStopReason <> '' then LObj.S['stopReason'] := AStopReason; ExecuteJS('window.ACP.streamMessage(' + LObj.ToJSON(False) + ')');
  finally LObj.Free; end;
end;

procedure TAgentControl.UpdateThoughtStreaming(const ASessionId, AContent: string);
var LObj: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := ASessionId; LObj.S['content'] := AContent; LObj.S['timestamp'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now); ExecuteJS('window.ACP.streamThought(' + LObj.ToJSON(False) + ')');
  finally LObj.Free; end;
end;

procedure TAgentControl.StartStreaming(const ASessionId, AType: string);
var
  LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(ASessionId);
  if Assigned(LSession) then
  begin
    if AType = 'thought' then LSession.IsThoughtStreaming := True
    else LSession.IsMessageStreaming := True;

    if FSessionMgr.ActiveSession = LSession then
      ExecuteJS('window.ACP.startStreaming("' + AType + '")');
  end;
end;

procedure TAgentControl.EndStreaming(const ASessionId, AType: string);
var
  LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(ASessionId);
  if Assigned(LSession) then
  begin
    if AType = 'thought' then LSession.IsThoughtStreaming := False
    else LSession.IsMessageStreaming := False;

    if FSessionMgr.ActiveSession = LSession then
      ExecuteJS('window.ACP.endStreaming("' + AType + '")');
  end;
end;

procedure TAgentControl.ReceiveMessage(const ASessionId, AContent: string);
var
  LSession: TSessionInfo;
  LBase64: string;
begin
  LSession := FSessionMgr.GetSessionById(ASessionId);
  if Assigned(LSession) and (FSessionMgr.ActiveSession = LSession) then
  begin
    LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(AContent)).Replace(#13, '').Replace(#10, '');
    ExecuteJS('window.ACP.receiveMessage("' + LBase64 + '")');
  end;
end;

procedure TAgentControl.BreakGrouping; begin System.Classes.TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS('window.ACP.breakGrouping()'); end)); end;

procedure TAgentControl.UpdateFileList(const ARootPath: string);
var
  LArray: TJsonArray;
  LTargetRoot: string;

  procedure ScanDir(const ADir: string);
  var
    LFile, LSubDir: string;
    LRelPath: string;
  begin
    try
      // Collect files in current dir
      for LFile in TDirectory.GetFiles(ADir) do
      begin
        LRelPath := ExtractRelativePath(LTargetRoot, LFile);
        LArray.Add(LRelPath.Replace('\', '/'));
      end;

      // Recurse into subdirs
      for LSubDir in TDirectory.GetDirectories(ADir) do
      begin
        if not IsIgnoredDir(TPath.GetFileName(LSubDir)) then
          ScanDir(LSubDir);
      end;
    except
      // Skip inaccessible directories
    end;
  end;

begin
  LTargetRoot := ARootPath;
  if LTargetRoot = '' then LTargetRoot := FWorkspaceRoot;
  if not TDirectory.Exists(LTargetRoot) then Exit;

  LTargetRoot := IncludeTrailingPathDelimiter(LTargetRoot);
  LArray := TJsonArray.Create;
  try
    ScanDir(ExcludeTrailingPathDelimiter(LTargetRoot));
    ExecuteJS('window.ACP.setWorkspaceFiles(' + LArray.ToJSON + ')');
  finally
    LArray.Free;
  end;
end;

procedure TAgentControl.ShowPermissionUI(const ASessionId, AID, AMethod, AToolCallJson, AOptionsJson: string);
var
  LData: TJsonObject;
  LJson, LBase64: string;
begin
  LData := TJsonObject.Create;
  try
    LData.S['sessionId'] := ASessionId; LData.S['id'] := AID; LData.S['method'] := AMethod;
    if AToolCallJson <> '' then LData.O['toolCall'].FromJSON(AToolCallJson); if AOptionsJson <> '' then LData.A['options'].FromJSON(AOptionsJson);
    LJson := LData.ToJSON(False);
    LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LJson)).Replace(#13, '').Replace(#10, '');
    ExecuteJS('window.ACP.ShowPermissionUI("' + LBase64 + '")');
  finally LData.Free; end;
end;

procedure TAgentControl.ShowTyping(const AShow: Boolean); begin System.Classes.TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS(Format('window.ACP.showProcessing(%s)', [BoolToStr(AShow, True).ToLower])); end)); end;

procedure TAgentControl.ExecuteJS(const AScript: string); begin if Assigned(FWebBrowser) then FWebBrowser.EvaluateJavaScript(AScript); end;

function TAgentControl.IsIgnoredDir(const ADirName: string): Boolean;
const IGNORED: array[0..5] of string = ('.git', 'node_modules', '__history', '__recovery', '.gemini', 'Win32');
var S: string; begin Result := False; for S in IGNORED do if SameText(ADirName, S) then Exit(True); end;

function TAgentControl.GetWorkspaceDisplayText(const ACwd: string): string; begin if ACwd = '' then Exit(''); Result := TPath.GetFileName(ExcludeTrailingPathDelimiter(ACwd)); end;

function TAgentControl.SessionToJSON(ASessionInfo: TSessionInfo): TJsonObject;
var LData: TSessionData; LModels: TJsonObject;
begin
  Result := TJsonObject.Create; if not Assigned(ASessionInfo) then Exit;
  Result.S['id'] := ASessionInfo.SessionId; Result.S['name'] := ASessionInfo.Name; Result.S['workspace'] := GetWorkspaceDisplayText(ASessionInfo.Cwd);
  Result.B['active'] := FSessionMgr.ActiveSession = ASessionInfo; Result.B['pinned'] := ASessionInfo.IsPinned; Result.B['isActive'] := ASessionInfo.IsActive;
  Result.B['isWaitForResponse'] := ASessionInfo.IsWaitForResponse; Result.B['online'] := ASessionInfo.IsActive; 
  Result.B['loading'] := ASessionInfo.IsLoading or (Assigned(ASessionInfo.Agent) and (ASessionInfo.Agent.State in [asConnecting, asInitializing]));
  Result.D['createdAt'] := ASessionInfo.CreatedAt;
  if ASessionInfo.LastConversationDate > 0 then
    Result.D['lastConversationDate'] := ASessionInfo.LastConversationDate;

  Result.S['icon'] := 'forum';  Result.S['lastMsg'] := 'Ready to chat...'; if ASessionInfo.IsLoading then Result.S['lastMsg'] := 'Starting process...';
  if Assigned(ASessionInfo.Agent) and (ASessionInfo.Agent is TACPAgent) then begin
    if TACPAgent(ASessionInfo.Agent).Sessions.TryGetValue(ASessionInfo.SessionId, LData) then begin
      if LData.ModelsJson <> '' then begin
        try
          LModels := TJsonObject.Parse(LData.ModelsJson) as TJsonObject;
          try 
            if Assigned(LModels) then begin
              Result.O['models'].Assign(LModels); 
              Result.S['currentModelId'] := LModels.S['currentModelId'];
            end;
          finally LModels.Free; end;
        except
        end;
      end;
      if LData.ModesJson <> '' then begin
        try
          LModels := TJsonObject.Parse(LData.ModesJson) as TJsonObject;
          try 
            if Assigned(LModels) then begin
              Result.O['modes'].Assign(LModels); 
              Result.S['currentModeId'] := LModels.S['currentModeId'];
            end;
          finally LModels.Free; end;
        except
        end;
      end;
      if LData.CommandsJson <> '' then begin
        try
          Result.A['commands'].FromJSON(LData.CommandsJson);
        except
          // If not a valid array string, ignore to prevent UI crash
        end;
      end;
    end;
  end;
end;

end.
