unit uAgentControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, uSessionManager,
  System.NetEncoding, FMX.Dialogs, System.Actions, FMX.ActnList, System.IOUtils,
  System.UITypes, System.Generics.Collections, System.Generics.Defaults, uWebACPCommandHandler,
  JsonDataObjects, uAgentTypes, uACPClient, uFileService, uAgentHandler;

type
  TNewChatEvent = procedure(Sender: TObject; const AgentName: string) of object;

  TAgentControl = class(TInterfacedObject, IAgentControl, IAgentObserver)
  protected
    { IInterface }
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    
    { IAgentObserver }
    procedure OnAgentMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure OnAgentThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure OnAgentStreamingEnd(Sender: TObject; const SessionId, AType: string);
    procedure OnAgentEndTurn(Sender: TObject; const SessionId, StopReason: string);
    procedure OnAgentPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
    procedure OnAgentSessionMetadataUpdate(Sender: TObject; const SessionId: string);
    procedure OnAgentPropertyUpdate(Sender: TObject; const SessionId, PropertyName, NewValue: string);
    procedure OnAgentRawData(Sender: TObject; Direction: TRPCDirection; const SessionId: string; AObj: TJsonObject; const RawText: string);
    procedure OnAgentNewSession(Sender: TObject; AResponse: TJsonObject);
    procedure OnAgentSessionResumed(Sender: TObject; const SessionId: string);
    procedure OnAgentFSWrite(Sender: TObject; const SessionId, Path, OldContent, NewContent: string);
    procedure OnAgentStateChange(Sender: TObject; const OldState, NewState: TAgentState);
  private
    FWebBrowser: TWebBrowser;
    FSessionMgr: TSessionManager;
    FWorkspaceRoot: string;
    FOnNewChat: TNewChatEvent;
    FCommandHandler: TWebACPCommandHandler;
    FAgentList: TDictionary<TAgentType, IACPAgent>;
    FHandlers: TDictionary<TAgentType, TAgentHandler>;
    FOnRawData: TAgentRPCEvent;
    FFileService: TFileService;
    
    FAgentFactory: TAgentFactoryFunc;
    FHandlerFactory: THandlerFactoryFunc;
    
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
    
    function GetWorkspaceDisplayText(const ACwd: string): string;
    function SessionToJSON(ASessionInfo: TSessionInfo): TJsonObject;
    function GetHandler(AType: TAgentType; AAgent: IACPAgent): TAgentHandler;
  public
    constructor Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    procedure RegisterAgent(AType: TAgentType; AAgent: IACPAgent);
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
    
    property AgentFactory: TAgentFactoryFunc read FAgentFactory write FAgentFactory;
    property HandlerFactory: THandlerFactoryFunc read FHandlerFactory write FHandlerFactory;
    property OnNewChat: TNewChatEvent read FOnNewChat write FOnNewChat;
    property OnRawData: TAgentRPCEvent read FOnRawData write FOnRawData;
    property AgentList: TDictionary<TAgentType, IACPAgent> read FAgentList;
  end;

implementation

uses
  FMX.Forms, System.Types, uConversationService, uDebugRPC, uMain, uACPProtocol;

{ TAgentControl }

function TAgentControl._AddRef: Integer; stdcall; begin Result := -1; end;
function TAgentControl._Release: Integer; stdcall; begin Result := -1; end;

constructor TAgentControl.Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
var LExeDir: string;
begin
  FWebBrowser := AWebBrowser; FSessionMgr := ASessionMgr;
  if Assigned(FSessionMgr) then FSessionMgr.OnSessionRestored := DoSessionRestored;
  FAgentList := TDictionary<TAgentType, IACPAgent>.Create; FHandlers := TDictionary<TAgentType, TAgentHandler>.Create;
  FCommandHandler := TWebACPCommandHandler.Create; FCommandHandler.OnCommand := HandleInternalCommand; FCommandHandler.OnLog := HandleInternalLog;
  FFileService := TFileService.Create; LExeDir := ExtractFilePath(ParamStr(0));
  if LExeDir.Contains('Win32') or LExeDir.Contains('Win64') then FWorkspaceRoot := TPath.GetFullPath(TPath.Combine(LExeDir, '..\..\')) else FWorkspaceRoot := TPath.GetFullPath(LExeDir);
  if not FWorkspaceRoot.EndsWith(PathDelim) then FWorkspaceRoot := FWorkspaceRoot + PathDelim;
end;

destructor TAgentControl.Destroy;
var LHandler: TAgentHandler;
begin for LHandler in FHandlers.Values do LHandler.Free; FHandlers.Free; FAgentList.Free; FCommandHandler.Free; FFileService.Free; inherited; end;

procedure TAgentControl.RegisterAgent(AType: TAgentType; AAgent: IACPAgent);
begin if Assigned(AAgent) then begin FAgentList.AddOrSetValue(AType, AAgent); AAgent.AddObserver(Self); end; end;

procedure TAgentControl.AddSession(ASession: TSessionInfo);
var LObj: TJsonObject; LBase64: string;
begin
  if not Assigned(ASession) then Exit; LObj := SessionToJSON(ASession);
  try LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LObj.ToJSON(False))).Replace(#13, '').Replace(#10, ''); FWebBrowser.EvaluateJavaScript('window.ACP.AddSession("' + LBase64 + '")'); finally LObj.Free; end;
end;

procedure TAgentControl.DeleteSession(ASession: TSessionInfo);
begin if not Assigned(ASession) then Exit; FSessionMgr.DeleteSession(ASession); UpdateSessionList; end;

procedure TAgentControl.DeleteSessionUI(const ASessionId: string);
begin FWebBrowser.EvaluateJavaScript('window.ACP.DeleteSession("' + ASessionId + '")'); end;

procedure TAgentControl.OnAgentRawData(Sender: TObject; Direction: TRPCDirection; const SessionId: string; AObj: TJsonObject; const RawText: string);
var LSession: TSessionInfo; LDirStr, LMethod: string;
begin
  if (Direction <> rdInternal) and (SessionId <> '') then begin
    LSession := FSessionMgr.GetSessionById(SessionId);
    if Assigned(LSession) then begin
      case Direction of rdIncoming: LDirStr := 'IN'; rdOutgoing: LDirStr := 'OUT'; else LDirStr := 'SYS'; end;
      TConversationService.AppendLog(LSession, LDirStr, RawText, False);
      if Assigned(AObj) then begin
        LMethod := AObj.S['method'];
        if (Direction = rdOutgoing) and SameText(LMethod, 'session/prompt') then LSession.UpdateConversationDate
        else if (Direction = rdIncoming) then begin if LMethod.StartsWith('fs/', True) or SameText(LMethod, 'session/request_permission') then LSession.UpdateConversationDate; end;
      end;
    end;
  end;
  if Assigned(FOnRawData) then FOnRawData(Self, Direction, SessionId, AObj, RawText);
end;

procedure TAgentControl.OnAgentNewSession(Sender: TObject; AResponse: TJsonObject);
var LSid, LOldId: string; LSession: TSessionInfo; LAgent: IACPAgent;
begin
  if not Assigned(AResponse) or AResponse.Contains('error') then Exit; LSid := AResponse.O['result'].S['sessionId']; if LSid = '' then Exit;
  if Supports(Sender, IACPAgent, LAgent) then begin
    LSession := FSessionMgr.GetPendingSessionByAgent(TObject(Sender));
    if Assigned(LSession) then begin
      LOldId := LSession.SessionId; LSession.IsLoading := False; LSession.IsActive := True;
      FSessionMgr.FinalizeSessionId(LSession, LSid); LAgent.SetSessionLogPath(LSid, LSession.LogPath);
      TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS(Format('window.ACP.updateSessionId("%s", "%s")', [LOldId, LSid])); UpdateSession(LSession); HandleSelectSession(LSession); UpdateFileList(LSession.Cwd); end));
    end;
  end;
end;

procedure TAgentControl.OnAgentSessionResumed(Sender: TObject; const SessionId: string);
var LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) then begin LSession.IsLoading := False; LSession.IsRestoring := False; LSession.IsActive := True; LSession.LastHistoryTick := 0;
    TThread.Queue(nil, TThreadProcedure(procedure begin UpdateSession(LSession); UpdateFileList(LSession.Cwd); end));
  end;
end;

procedure TAgentControl.OnAgentFSWrite(Sender: TObject; const SessionId, Path, OldContent, NewContent: string); begin end;
procedure TAgentControl.OnAgentStateChange(Sender: TObject; const OldState, NewState: TAgentState); begin end;

procedure TAgentControl.OnAgentMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) and (not LSession.IsRestoring) then begin LSession.UpdateConversationDate; if not LSession.IsMessageStreaming then StartStreaming(SessionId, 'message'); ReceiveMessage(SessionId, FullText); end;
end;

procedure TAgentControl.OnAgentThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) and (not LSession.IsRestoring) then begin LSession.UpdateConversationDate; if not LSession.IsThoughtStreaming then StartStreaming(SessionId, 'thought'); ReceiveMessage(SessionId, FullText); end;
end;

procedure TAgentControl.OnAgentStreamingEnd(Sender: TObject; const SessionId, AType: string); begin EndStreaming(SessionId, AType); end;

procedure TAgentControl.OnAgentEndTurn(Sender: TObject; const SessionId, StopReason: string);
var LSession: TSessionInfo;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) then begin if LSession.IsThoughtStreaming then EndStreaming(SessionId, 'thought'); if LSession.IsMessageStreaming then EndStreaming(SessionId, 'message'); end;
  TThread.Queue(nil, TThreadProcedure(procedure begin ShowTyping(False); if Assigned(LSession) then UpdateSession(LSession); end));
end;

procedure TAgentControl.OnAgentPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
var LSession: TSessionInfo; LHandler: TAgentHandler; LAgent: IACPAgent;
begin
  LSession := FSessionMgr.GetSessionById(SessionId);
  if Assigned(LSession) and Supports(Sender, IACPAgent, LAgent) then begin
    if LSession.IsThoughtStreaming then EndStreaming(SessionId, 'thought'); if LSession.IsMessageStreaming then EndStreaming(SessionId, 'message');
    LHandler := GetHandler(LSession.AgentType, LAgent); if Assigned(LHandler) then LHandler.ProcessRequestPermission(ID, Method, SessionId, ToolCall, Options);
  end;
end;

procedure TAgentControl.OnAgentSessionMetadataUpdate(Sender: TObject; const SessionId: string);
var LSid: string; LSession: TSessionInfo;
begin
  LSid := SessionId;
  TThread.Queue(nil, TThreadProcedure(procedure begin LSession := FSessionMgr.GetSessionById(LSid);
    if Assigned(LSession) then begin if LSession.IsLoading then begin LSession.IsLoading := False; LSession.IsActive := True; UpdateFileList(LSession.Cwd); end; UpdateSession(LSession); end;
  end));
end;

procedure TAgentControl.OnAgentPropertyUpdate(Sender: TObject; const SessionId, PropertyName, NewValue: string);
begin TThread.Queue(nil, TThreadProcedure(procedure begin if PropertyName = 'currentModelId' then ExecuteJS(Format('window.ACP.changeModel("%s", "%s")', [SessionId, NewValue])); end)); end;

procedure TAgentControl.DoSessionRestored(Sender: TObject; ASession: TSessionInfo);
var LCaptured: TSessionInfo;
begin LCaptured := ASession; TThread.Queue(nil, TThreadProcedure(procedure begin if Assigned(LCaptured) then begin UpdateFileList(LCaptured.Cwd); UpdateSessionList; end; end)); end;

function TAgentControl.GetHandler(AType: TAgentType; AAgent: IACPAgent): TAgentHandler;
begin if not FHandlers.TryGetValue(AType, Result) then begin if Assigned(FHandlerFactory) then begin Result := TAgentHandler(FHandlerFactory(AType, AAgent, Self)); if Assigned(Result) then FHandlers.Add(AType, Result); end else Result := nil; end; end;

procedure TAgentControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'new-chat' then HandleNewChat(Params) else if Action = 'send-message' then HandleSendMessage(Params) else if Action = 'select-session' then HandleSelectSession(Params) else if Action = 'delete-session' then HandleDeleteSession(Params)
  else if Action = 'next-session' then HandleNextPrevSession(1) else if Action = 'prev-session' then HandleNextPrevSession(-1) else if Action = 'resume-session' then HandleResumeSession(Params) else if Action = 'change-model' then HandleChangeModel(Params)
  else if Action = 'permission-response' then HandlePermissionResponse(Params) else if Action = 'cancel-prompt' then HandleCancelPrompt(Params) else if Action = 'get-file-content' then HandleGetFileContent(Params)
  else if Action = 'open-file-dialog' then HandleOpenFileDialog(Params) else if Action = 'get-file-history' then HandleGetFileHistory(Params) else if Action = 'action' then HandleAction(Params);
end;

function TAgentControl.HandleRequest(const AUrl: string): Boolean; begin Result := FCommandHandler.HandleUrl(AUrl, 'acp-action://'); end;

procedure TAgentControl.HandleNewChat(const Params: TDictionary<string, string>);
var LAgentName, LSelectedDir, LPendingId: string; LType: TAgentType; LPrevActive, LPendingSession: TSessionInfo; LAgent: IACPAgent; LParams: TJsonObject;
begin
  if Params.TryGetValue('agent', LAgentName) then begin
    if Assigned(FOnNewChat) then FOnNewChat(Self, LAgentName);
    if SameText(LAgentName, 'gemini') then LType := atGemini else if SameText(LAgentName, 'claude') then LType := atClaude else if SameText(LAgentName, 'codex') then LType := atCodex else Exit;
    if Assigned(FAgentFactory) then LAgent := FAgentFactory(LType) else LAgent := nil; if not Assigned(LAgent) then Exit;
    RegisterAgent(LType, LAgent); if not SelectDirectory('Select Project Workspace for ' + LAgentName, '', LSelectedDir) then Exit;
    LPrevActive := FSessionMgr.ActiveSession; if Assigned(LPrevActive) then begin FSessionMgr.SelectSession(nil); UpdateSession(LPrevActive); end;
    LPendingId := 'pending-' + TGuid.NewGuid.ToString; LPendingSession := FSessionMgr.AddSession(LAgent, LType, LPendingId, FSessionMgr.GetUniqueSessionName('New Chat'), LSelectedDir);
    LPendingSession.IsLoading := True; FSessionMgr.SelectSession(LPendingSession);
    ExecuteJS('window.ACP.clearChat()'); AddSession(LPendingSession); UpdateFileList(LSelectedDir);
    LAgent.SetWorkspace(LSelectedDir); LParams := TACPProtocol.CreateSessionNewParams(LSelectedDir, ''); try LAgent.NewSession(LParams); finally LParams.Free; end;
  end;
end;

procedure TAgentControl.HandleResumeSession(const Params: TDictionary<string, string>);
var LSid: string; LTarget: TSessionInfo; LAgent: IACPAgent;
begin
  if Params.TryGetValue('id', LSid) then begin
    LTarget := FSessionMgr.GetSessionById(LSid);
    if Assigned(LTarget) and Assigned(LTarget.Agent) and Supports(LTarget.Agent, IACPAgent, LAgent) then begin
       LTarget.IsLoading := True; UpdateSession(LTarget); HandleSelectSession(LTarget);
       LAgent.SetWorkspace(LTarget.Cwd); LAgent.ResumeSession(LSid);
    end;
  end;
end;

procedure TAgentControl.HandleSendMessage(const Params: TDictionary<string, string>);
var LText, LBase64: string; LActive: TSessionInfo; LAgent: IACPAgent;
begin
  if Params.TryGetValue('text', LText) and (LText <> '') then begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and Assigned(LActive.Agent) and Supports(LActive.Agent, IACPAgent, LAgent) then begin
     LAgent.SendPrompt(LActive.SessionId, LText); LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LText)).Replace(#13, '').Replace(#10, '');
      ExecuteJS(Format('window.ACP.addUserMessage("%s")', [LBase64])); ExecuteJS('window.ACP.lastAiMsgId = ""; window.ACP.lastAiThoughtId = ""; window.ACP.lastBlockType = "";'); ShowTyping(True);
    end;
  end;
end;

procedure TAgentControl.HandleSelectSession(const Params: TDictionary<string, string>); var LSid: string; begin if Params.TryGetValue('id', LSid) then HandleSelectSession(FSessionMgr.GetSessionById(LSid)); end;

procedure TAgentControl.HandleSelectSession(ASession: TSessionInfo);
var LPrevActive: TSessionInfo;
begin
  if Assigned(ASession) then begin
    LPrevActive := FSessionMgr.ActiveSession; FSessionMgr.SelectSession(ASession); if Assigned(LPrevActive) and (LPrevActive <> ASession) then UpdateSession(LPrevActive);
    UpdateSession(ASession); var LCaptured := ASession;
    TThread.Queue(nil, TThreadProcedure(procedure
    var LInnerMsg: TJsonArray; LInnerJson, LBase64: string; LBytes: TBytes;
    begin
      if not Assigned(LCaptured) then Exit; UpdateFileList(LCaptured.Cwd); LInnerMsg := TConversationService.GetConversationsBySessionId(LCaptured);
      try LInnerJson := LInnerMsg.ToJSON(False); LBytes := TEncoding.UTF8.GetBytes(LInnerJson); LBase64 := TNetEncoding.Base64.EncodeBytesToString(LBytes).Replace(#13, '').Replace(#10, ''); ExecuteJS('window.ACP.loadHistoryBase64("' + LBase64 + '")'); ExecuteJS('if (document.getElementById("historySidebar") && !document.getElementById("historySidebar").classList.contains("hidden")) window.sendAcp("get-file-history");'); finally LInnerMsg.Free; end;
    end));
  end;
end;

procedure TAgentControl.HandleDeleteSession(const Params: TDictionary<string, string>); var LSid: string; LTarget: TSessionInfo; begin if Params.TryGetValue('id', LSid) then begin LTarget := FSessionMgr.GetSessionById(LSid); if Assigned(LTarget) then DeleteSession(LTarget); end; end;

procedure TAgentControl.HandleNextPrevSession(ADir: Integer);
var LSessions: TList<TSessionInfo>; LActive: TSessionInfo; LIdx, LNextIdx: Integer;
begin
  LSessions := FSessionMgr.GetSessionListSnapshot; try if LSessions.Count <= 1 then Exit; LActive := FSessionMgr.ActiveSession; LIdx := LSessions.IndexOf(LActive);
    if LIdx = -1 then LNextIdx := 0 else LNextIdx := (LIdx + ADir + LSessions.Count) mod LSessions.Count; HandleSelectSession(LSessions[LNextIdx]); finally LSessions.Free; end;
end;

procedure TAgentControl.HandleAction(const Params: TDictionary<string, string>); begin end;

procedure TAgentControl.HandleChangeModel(const Params: TDictionary<string, string>);
var LModelId: string; LActive: TSessionInfo; LAgent: IACPAgent;
begin if Params.TryGetValue('modelId', LModelId) then begin LActive := FSessionMgr.ActiveSession; if Assigned(LActive) and Supports(LActive.Agent, IACPAgent, LAgent) then LAgent.ChangeModel(LActive.SessionId, LModelId); end; end;

procedure TAgentControl.HandlePermissionResponse(const Params: TDictionary<string, string>);
var LID, LOptionId: string; LActive: TSessionInfo; LAgent: IACPAgent;
begin if Params.TryGetValue('id', LID) and Params.TryGetValue('optionId', LOptionId) then begin LActive := FSessionMgr.ActiveSession; if Assigned(LActive) and Supports(LActive.Agent, IACPAgent, LAgent) then LAgent.ReplyPermission(LID, LActive.SessionId, LOptionId); end; end;

procedure TAgentControl.HandleCancelPrompt(const Params: TDictionary<string, string>);
var LActive: TSessionInfo; LAgent: IACPAgent;
begin LActive := FSessionMgr.ActiveSession; if Assigned(LActive) and Supports(LActive.Agent, IACPAgent, LAgent) then begin LAgent.CancelPrompt(LActive.SessionId); ShowTyping(False); end; end;

procedure TAgentControl.HandleGetFileContent(const Params: TDictionary<string, string>);
var LRelPath, LFullPath, LCallbackId, LTargetRoot: string; LActive: TSessionInfo;
begin
  if Params.TryGetValue('path', LRelPath) and Params.TryGetValue('callbackId', LCallbackId) then begin
    LActive := FSessionMgr.ActiveSession; if Assigned(LActive) and (LActive.Cwd <> '') then LTargetRoot := LActive.Cwd else LTargetRoot := FWorkspaceRoot;
    LFullPath := TPath.Combine(LTargetRoot, LRelPath); var LCallback := LCallbackId;
    FFileService.LoadFile(LFullPath, procedure(AFileName, APath, AJsonContent: string) begin TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS('window.ACP.onFileContentReceived("' + LCallback + '", ' + AJsonContent + ')'); end)); end, procedure(AError: string) begin end);
  end;
end;

procedure TAgentControl.HandleOpenFileDialog(const Params: TDictionary<string, string>);
var LDialog: TOpenDialog; LRelPath, LTargetRoot: string; LActive: TSessionInfo;
begin
  LActive := FSessionMgr.ActiveSession; if Assigned(LActive) and (LActive.Cwd <> '') then LTargetRoot := LActive.Cwd else LTargetRoot := FWorkspaceRoot;
  LDialog := TOpenDialog.Create(nil); try LDialog.Options := LDialog.Options + [System.UITypes.TOpenOption.ofPathMustExist, System.UITypes.TOpenOption.ofFileMustExist]; if LDialog.Execute then begin LRelPath := ExtractRelativePath(LTargetRoot, LDialog.FileName).Replace('\', '/'); ExecuteJS('window.ACP.applyFile("' + LRelPath + '")'); end; finally LDialog.Free; end;
end;

procedure TAgentControl.HandleGetFileHistory(const Params: TDictionary<string, string>);
var LActive: TSessionInfo;
begin
  LActive := FSessionMgr.ActiveSession; if not Assigned(LActive) or (LActive.DiffsPath = '') then Exit;
  FFileService.GetFileHistory(LActive.DiffsPath, procedure(AArray: TJsonArray)
    var LJsonText, LBase64: string; begin try LJsonText := AArray.ToJSON(False); LBase64 := TNetEncoding.Base64.Encode(LJsonText).Replace(#13, '').Replace(#10, ''); TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS('window.ACP.updateFileHistoryBase64("' + LBase64 + '")'); end)); finally AArray.Free; end; end, procedure(AError: string) begin end);
end;

procedure TAgentControl.HandleInternalLog(Sender: TObject; const LogMsg: string); begin if Assigned(frmDebugRPC) then frmDebugRPC.AddACPLog(LogMsg); end;

procedure TAgentControl.LoadAllSessions;
var LAgent: IACPAgent; LSessionIds: TArray<string>; LSid: string; LSession: TSessionInfo; LNewAgent: IACPAgent;
begin
  if not Assigned(FSessionMgr) then Exit;
  for LAgent in FAgentList.Values do begin
    LSessionIds := LAgent.GetSessionList;
    for LSid in LSessionIds do begin
      if Assigned(FAgentFactory) then LNewAgent := FAgentFactory(LAgent.GetAgentType) else LNewAgent := nil;
      if Assigned(LNewAgent) then RegisterAgent(LAgent.GetAgentType, LNewAgent) else LNewAgent := LAgent;
      LSession := FSessionMgr.AddSession(LNewAgent, LAgent.GetAgentType, LSid, 'Loading...');
      if Assigned(LSession) then begin LSession.LoadMetadata; if Assigned(LNewAgent) then LNewAgent.SetSessionLogPath(LSid, LSession.LogPath); end;
    end;
  end;
  FSessionMgr.SortSessions;
end;

procedure TAgentControl.UpdateSessionList;
var LArray: TJsonArray; LSession: TSessionInfo; LSessions: TList<TSessionInfo>; LJson, LBase64: string;
begin
  LArray := TJsonArray.Create; try LSessions := FSessionMgr.GetSessionListSnapshot; try for LSession in LSessions do LArray.AddObject.Assign(SessionToJSON(LSession)); finally LSessions.Free; end; LJson := LArray.ToJSON(False); LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LJson)).Replace(#13, '').Replace(#10, ''); ExecuteJS('window.ACP.updateSessionList("' + LBase64 + '")'); finally LArray.Free; end;
end;

procedure TAgentControl.UpdateSession(ASession: TSessionInfo);
var LObj: TJsonObject; LBase64: string;
begin if not Assigned(ASession) then Exit; LObj := SessionToJSON(ASession); try LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LObj.ToJSON(False))).Replace(#13, '').Replace(#10, ''); ExecuteJS('window.ACP.updateSession("' + LBase64 + '")'); finally LObj.Free; end; end;

procedure TAgentControl.UpdateMessageStreaming(const ASessionId, AContent, ARole, AStopReason: string);
var LObj: TJsonObject; begin LObj := TJsonObject.Create; try LObj.S['sessionId'] := ASessionId; LObj.S['content'] := AContent; LObj.S['role'] := ARole; LObj.S['timestamp'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now); if AStopReason <> '' then LObj.S['stopReason'] := AStopReason; ExecuteJS('window.ACP.streamMessage(' + LObj.ToJSON(False) + ')'); finally LObj.Free; end; end;

procedure TAgentControl.UpdateThoughtStreaming(const ASessionId, AContent: string);
var LObj: TJsonObject; begin LObj := TJsonObject.Create; try LObj.S['sessionId'] := ASessionId; LObj.S['content'] := AContent; LObj.S['timestamp'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now); ExecuteJS('window.ACP.streamThought(' + LObj.ToJSON(False) + ')'); finally LObj.Free; end; end;

procedure TAgentControl.StartStreaming(const ASessionId, AType: string);
var LSession: TSessionInfo; begin LSession := FSessionMgr.GetSessionById(ASessionId); if Assigned(LSession) then begin if AType = 'thought' then LSession.IsThoughtStreaming := True else LSession.IsMessageStreaming := True; if FSessionMgr.ActiveSession = LSession then ExecuteJS('window.ACP.startStreaming("' + AType + '")'); end; end;

procedure TAgentControl.EndStreaming(const ASessionId, AType: string);
var LSession: TSessionInfo; begin LSession := FSessionMgr.GetSessionById(ASessionId); if Assigned(LSession) then begin if AType = 'thought' then LSession.IsThoughtStreaming := False else LSession.IsMessageStreaming := False; if FSessionMgr.ActiveSession = LSession then ExecuteJS('window.ACP.endStreaming("' + AType + '")'); end; end;

procedure TAgentControl.ReceiveMessage(const ASessionId, AContent: string);
var LSession: TSessionInfo; LBase64: string; begin LSession := FSessionMgr.GetSessionById(ASessionId); if Assigned(LSession) and (FSessionMgr.ActiveSession = LSession) then begin LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(AContent)).Replace(#13, '').Replace(#10, ''); ExecuteJS('window.ACP.receiveMessage("' + LBase64 + '")'); end; end;

procedure TAgentControl.BreakGrouping; begin TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS('window.ACP.breakGrouping()'); end)); end;

procedure TAgentControl.UpdateFileList(const ARootPath: string);
var LTargetRoot: string;
begin
  LTargetRoot := ARootPath; if LTargetRoot = '' then LTargetRoot := FWorkspaceRoot;
  FFileService.GetWorkspaceFiles(LTargetRoot, procedure(AArray: TJsonArray) begin TThread.Queue(nil, TThreadProcedure(procedure begin try ExecuteJS('window.ACP.setWorkspaceFiles(' + AArray.ToJSON + ')'); finally AArray.Free; end; end)); end, procedure(AError: string) begin end);
end;

procedure TAgentControl.ShowPermissionUI(const ASessionId, AID, AMethod, AToolCallJson, AOptionsJson: string);
var LData: TJsonObject; LJson, LBase64: string;
begin
  LData := TJsonObject.Create; try LData.S['sessionId'] := ASessionId; LData.S['id'] := AID; LData.S['id_method'] := AMethod; if AToolCallJson <> '' then LData.O['toolCall'].FromJSON(AToolCallJson); if AOptionsJson <> '' then LData.A['options'].FromJSON(AOptionsJson); LJson := LData.ToJSON(False); LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LJson)).Replace(#13, '').Replace(#10, ''); ExecuteJS('window.ACP.ShowPermissionUI("' + LBase64 + '")'); finally LData.Free; end;
end;

procedure TAgentControl.ShowTyping(const AShow: Boolean); begin TThread.Queue(nil, TThreadProcedure(procedure begin ExecuteJS(Format('window.ACP.showProcessing(%s)', [BoolToStr(AShow, True).ToLower])); end)); end;

procedure TAgentControl.ExecuteJS(const AScript: string); begin if Assigned(FWebBrowser) then FWebBrowser.EvaluateJavaScript(AScript); end;

function TAgentControl.GetWorkspaceDisplayText(const ACwd: string): string; begin if ACwd = '' then Exit(''); Result := TPath.GetFileName(ExcludeTrailingPathDelimiter(ACwd)); end;

function TAgentControl.SessionToJSON(ASessionInfo: TSessionInfo): TJsonObject;
var LData: TSessionData; LAgent: IACPAgent;
begin
  Result := TJsonObject.Create; if not Assigned(ASessionInfo) then Exit; Result.S['id'] := ASessionInfo.SessionId; Result.S['name'] := ASessionInfo.Name; Result.S['workspace'] := GetWorkspaceDisplayText(ASessionInfo.Cwd); Result.B['active'] := FSessionMgr.ActiveSession = ASessionInfo; Result.B['pinned'] := ASessionInfo.IsPinned; Result.B['isActive'] := ASessionInfo.IsActive; Result.B['isWaitForResponse'] := ASessionInfo.IsWaitForResponse; Result.B['online'] := ASessionInfo.IsActive; 
  Result.B['loading'] := ASessionInfo.IsLoading or (Assigned(ASessionInfo.Agent) and Supports(ASessionInfo.Agent, IACPAgent, LAgent) and (LAgent.State in [asConnecting, asInitializing]));
  Result.D['createdAt'] := ASessionInfo.CreatedAt; if ASessionInfo.LastConversationDate > 0 then Result.D['lastConversationDate'] := ASessionInfo.LastConversationDate;
  Result.S['icon'] := 'forum';  Result.S['lastMsg'] := 'Ready to chat...'; if ASessionInfo.IsLoading then Result.S['lastMsg'] := 'Starting process...';
  if Assigned(ASessionInfo.Agent) and Supports(ASessionInfo.Agent, IACPAgent, LAgent) then begin
    var LJsonStr := LAgent.GetSessionsJson(ASessionInfo.SessionId);
    if LJsonStr <> '' then begin
      var LModels := LAgent.GetModels; if Length(LModels) > 0 then begin var LModelsObj := Result.O['models']; LModelsObj.S['currentModelId'] := LAgent.ModelId; var LArr := LModelsObj.A['availableModels']; for var i := 0 to High(LModels) do begin var LItem := LArr.AddObject; LItem.S['modelId'] := LModels[i].ModelId; LItem.S['name'] := LModels[i].Name; if LModels[i].Description <> '' then LItem.S['description'] := LModels[i].Description; end; Result.S['currentModelId'] := LAgent.ModelId; end;
      var LModes := LAgent.GetModes; if Length(LModes) > 0 then begin var LModesObj := Result.O['modes']; LModesObj.S['currentModeId'] := LAgent.ModeId; var LArr := LModesObj.A['availableModes']; for var i := 0 to High(LModes) do begin var LItem := LArr.AddObject; LItem.S['id'] := LModes[i].ModeId; LItem.S['name'] := LModes[i].Name; if LModes[i].Description <> '' then LItem.S['description'] := LModes[i].Description; end; Result.S['currentModelId'] := LAgent.ModeId; end;
      try Result.A['commands'].FromJSON(LJsonStr); except end;
    end;
  end;
end;

end.
