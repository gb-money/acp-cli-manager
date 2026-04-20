unit uAgentControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, uSessionManager, uAgent,
  System.NetEncoding, FMX.Dialogs, System.Actions, FMX.ActnList, System.IOUtils,
  System.UITypes, System.Generics.Collections, System.Generics.Defaults, uWebACPCommandHandler;

type
  TNewChatEvent = procedure(Sender: TObject; const AgentName: string) of object;

  TAgentControl = class
  private
    FWebBrowser: TWebBrowser;
    FSessionMgr: TSessionManager;
    FWorkspaceRoot: string;
    FOnNewChat: TNewChatEvent;
    FCommandHandler: TWebACPCommandHandler;
    
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleInternalLog(Sender: TObject; const LogMsg: string);
    
    procedure HandleNewChat(const Params: TDictionary<string, string>);
    procedure HandleSendMessage(const Params: TDictionary<string, string>);
    procedure HandleAction(const Params: TDictionary<string, string>);
    procedure HandleSelectSession(const Params: TDictionary<string, string>);
    procedure HandleChangeModel(const Params: TDictionary<string, string>);
    procedure HandlePermissionResponse(const Params: TDictionary<string, string>);
    procedure HandleCancelPrompt(const Params: TDictionary<string, string>);
    procedure HandleResumeSession(const Params: TDictionary<string, string>);
    procedure HandleNextPrevSession(ADir: Integer);
    procedure HandleGetFileContent(const Params: TDictionary<string, string>);
    procedure HandleOpenFileDialog(const Params: TDictionary<string, string>);
    procedure HandleGetFileHistory(const Params: TDictionary<string, string>);
    function IsIgnoredDir(const ADirName: string): Boolean;
    function GetWorkspaceDisplayText(const ACwd: string): string;
  public
    constructor Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    procedure UpdateSessionList;
    procedure UpdateMessageStreaming(const ASessionId, AContent: string; const ARole: string = 'ai'; const AStopReason: string = '');
    procedure UpdateThoughtStreaming(const ASessionId, AContent: string);
    procedure UpdateFileList(const ARootPath: string = '');
    procedure RequestPermissionUI(const ASessionId, AID, AMethod, AToolCallJson, AOptionsJson: string);
    procedure ShowTyping(const AShow: Boolean);
    procedure ExecuteJS(const AScript: string);
    property OnNewChat: TNewChatEvent read FOnNewChat write FOnNewChat;
  end;

implementation

uses
  JsonDataObjects, FMX.Forms, uGeminiAgent, uACPAgent, System.Types, uConversationService, uDebugRPC, uMain;

constructor TAgentControl.Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
var
  LExeDir: string;
begin
  FWebBrowser := AWebBrowser;
  FSessionMgr := ASessionMgr;
  
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
begin
  FCommandHandler.Free;
  inherited;
end;

procedure TAgentControl.HandleInternalLog(Sender: TObject; const LogMsg: string);
begin
  if Assigned(frmDebugRPC) then
    frmDebugRPC.AddACPLog(LogMsg);
end;

procedure TAgentControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'new-chat' then HandleNewChat(Params)
  else if Action = 'send-message' then HandleSendMessage(Params)
  else if Action = 'select-session' then HandleSelectSession(Params)
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
  LAgentName: string;
begin
  if Params.TryGetValue('agent', LAgentName) then
    if Assigned(FOnNewChat) then
      FOnNewChat(Self, LAgentName);
end;

procedure TAgentControl.HandleSendMessage(const Params: TDictionary<string, string>);
var
  LText: string;
  LActiveSession: TSessionInfo;
begin
  if Params.TryGetValue('text', LText) and (LText <> '') then
  begin
    LActiveSession := FSessionMgr.ActiveSession;
    if Assigned(LActiveSession) and Assigned(LActiveSession.Agent) then
    begin
      FWebBrowser.EvaluateJavaScript('window.ACP.lastAiMsgId = ""; window.ACP.lastAiThoughtId = ""; window.ACP.lastBlockType = "";');
      ShowTyping(True);
      LActiveSession.Agent.SendPrompt(LActiveSession.SessionId, LText);
    end;
  end;
end;

procedure TAgentControl.HandleSelectSession(const Params: TDictionary<string, string>);
var
  LSessionId: string;
  LTargetSession, LSession: TSessionInfo;
  LSessions: TList<TSessionInfo>;
begin
  if Params.TryGetValue('id', LSessionId) and (LSessionId <> '') then
  begin
    LTargetSession := nil;
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSession in LSessions do
        if LSession.SessionId = LSessionId then begin
          LTargetSession := LSession;
          Break;
        end;
    finally
      LSessions.Free;
    end;

    if Assigned(LTargetSession) then
    begin
      FSessionMgr.SelectSession(LTargetSession);
      UpdateSessionList;
      
      System.Classes.TThread.Queue(nil, procedure
      var
        LInnerMsg: TJsonArray;
        LInnerJson: string;
        LBytes: TBytes;
        LBase64: string;
      begin
        if not Assigned(LTargetSession) then Exit;
        
        UpdateFileList(LTargetSession.Cwd);
        LInnerMsg := TConversationService.GetConversationsBySessionId(LTargetSession);
        try
          LInnerJson := LInnerMsg.ToJSON(False);
          LBytes := TEncoding.UTF8.GetBytes(LInnerJson);
          LBase64 := TNetEncoding.Base64.EncodeBytesToString(LBytes).Replace(#13, '').Replace(#10, '');
          FWebBrowser.EvaluateJavaScript('window.ACP.loadHistoryBase64("' + LBase64 + '")');
          FWebBrowser.EvaluateJavaScript('if (document.getElementById("historySidebar") && !document.getElementById("historySidebar").classList.contains("hidden")) window.sendAcp("get-file-history");');
        finally
          LInnerMsg.Free;
        end;
      end);
    end;
  end;
end;

procedure TAgentControl.HandleResumeSession(const Params: TDictionary<string, string>);
var
  LSessionId: string;
  LTargetSession, LSession: TSessionInfo;
  LSessions: TList<TSessionInfo>;
begin
  if Params.TryGetValue('id', LSessionId) then
  begin
    LTargetSession := nil;
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSession in LSessions do
        if LSession.SessionId = LSessionId then begin
          LTargetSession := LSession;
          Break;
        end;
    finally
      LSessions.Free;
    end;

    if Assigned(LTargetSession) then
    begin
       // 1. Pre-load local history immediately
       HandleSelectSession(Params);

       // 2. Start connection and restoration
       LTargetSession.IsLoading := True; 
       if Assigned(LTargetSession.Agent) then
       begin
         if LTargetSession.Agent.State in [asDisconnected, asError] then
           LTargetSession.Agent.Connect
         else if LTargetSession.Agent.State = asReady then
           // Agent is already ready, trigger restoration directly
           S.StartSessionRestoration(LTargetSession);
       end;
       UpdateSessionList;
    end;
  end;
end;

procedure TAgentControl.HandleNextPrevSession(ADir: Integer);
var
  LSessions: TList<TSessionInfo>;
  LActive: TSessionInfo;
  LIdx, LNextIdx: Integer;
  LParams: TDictionary<string, string>;
begin
  LSessions := FSessionMgr.GetSessionListSnapshot;
  try
    if LSessions.Count <= 1 then Exit;
    
    LActive := FSessionMgr.ActiveSession;
    LIdx := LSessions.IndexOf(LActive);
    
    if LIdx = -1 then LNextIdx := 0
    else LNextIdx := (LIdx + ADir + LSessions.Count) mod LSessions.Count;
    
    LParams := TDictionary<string, string>.Create;
    try
      LParams.Add('id', LSessions[LNextIdx].SessionId);
      HandleSelectSession(LParams);
    finally
      LParams.Free;
    end;
  finally
    LSessions.Free;
  end;
end;

procedure TAgentControl.HandleAction(const Params: TDictionary<string, string>);
begin
end;

procedure TAgentControl.HandleChangeModel(const Params: TDictionary<string, string>);
var
  LModelId: string;
  LActiveSession: TSessionInfo;
begin
  if Params.TryGetValue('modelId', LModelId) then
  begin
    LActiveSession := FSessionMgr.ActiveSession;
    if Assigned(LActiveSession) and (LActiveSession.Agent is TGeminiAgent) then
    begin
      TGeminiAgent(LActiveSession.Agent).ChangeModel(LActiveSession.SessionId, LModelId);
      UpdateSessionList;
    end;
  end;
end;

procedure TAgentControl.HandlePermissionResponse(const Params: TDictionary<string, string>);
var
  LID, LOptionId: string;
  LActiveSession: TSessionInfo;
begin
  if Params.TryGetValue('id', LID) and Params.TryGetValue('optionId', LOptionId) then
  begin
    LActiveSession := FSessionMgr.ActiveSession;
    if Assigned(LActiveSession) and (LActiveSession.Agent is TACPAgent) then
    begin
      TACPAgent(LActiveSession.Agent).ReplyPermission(LID, LOptionId);
    end;
  end;
end;

procedure TAgentControl.HandleCancelPrompt(const Params: TDictionary<string, string>);
var
  LActiveSession: TSessionInfo;
begin
  LActiveSession := FSessionMgr.ActiveSession;
  if Assigned(LActiveSession) and (LActiveSession.Agent is TGeminiAgent) then
  begin
    TGeminiAgent(LActiveSession.Agent).CancelPrompt(LActiveSession.SessionId);
    ShowTyping(False);
  end;
end;

procedure TAgentControl.HandleGetFileContent(const Params: TDictionary<string, string>);
var
  LRelPath, LFullPath, LContent, LCallbackId: string;
  LObj: TJsonObject;
  LActiveSession: TSessionInfo;
  LTargetRoot: string;
begin
  if Params.TryGetValue('path', LRelPath) and Params.TryGetValue('callbackId', LCallbackId) then
  begin
    LActiveSession := FSessionMgr.ActiveSession;
    if Assigned(LActiveSession) and (LActiveSession.Cwd <> '') then
      LTargetRoot := LActiveSession.Cwd
    else
      LTargetRoot := FWorkspaceRoot;

    LFullPath := TPath.Combine(LTargetRoot, LRelPath);
    LContent := '';
    if TFile.Exists(LFullPath) then
      LContent := TFile.ReadAllText(LFullPath, TEncoding.UTF8);

    LObj := TJsonObject.Create;
    try
      LObj.S['path'] := LRelPath;
      LObj.S['content'] := LContent;
      LObj.S['uri'] := 'file:///' + LFullPath.Replace('\', '/');
      FWebBrowser.EvaluateJavaScript('window.ACP.onFileContentReceived("' + LCallbackId + '", ' + LObj.ToJSON(False) + ')');
    finally
      LObj.Free;
    end;
  end;
end;

procedure TAgentControl.HandleOpenFileDialog(const Params: TDictionary<string, string>);
var
  LDialog: TOpenDialog;
  LRelPath, LTargetRoot: string;
  LActiveSession: TSessionInfo;
begin
  LActiveSession := FSessionMgr.ActiveSession;
  if Assigned(LActiveSession) and (LActiveSession.Cwd <> '') then
    LTargetRoot := LActiveSession.Cwd
  else
    LTargetRoot := FWorkspaceRoot;

  LDialog := TOpenDialog.Create(nil);
  try
    LDialog.Options := LDialog.Options + [System.UITypes.TOpenOption.ofPathMustExist, System.UITypes.TOpenOption.ofFileMustExist];
    if LDialog.Execute then
    begin
      LRelPath := ExtractRelativePath(LTargetRoot, LDialog.FileName).Replace('\', '/');
      FWebBrowser.EvaluateJavaScript('window.ACP.applyFile("' + LRelPath + '")');
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TAgentControl.HandleGetFileHistory(const Params: TDictionary<string, string>);
var
  LActiveSession: TSessionInfo;
  LFiles: TStringDynArray;
  LPath, LJsonText: string;
  LArray: TJsonArray;
  LObj, LItem: TJsonObject;
  LList: TList<TJsonObject>;
  I: Integer;
begin
  LActiveSession := FSessionMgr.ActiveSession;
  if not Assigned(LActiveSession) or (LActiveSession.DiffsPath = '') then Exit;

  LArray := TJsonArray.Create;
  LList := TList<TJsonObject>.Create;
  try
    if TDirectory.Exists(LActiveSession.DiffsPath) then
    begin
      LFiles := TDirectory.GetFiles(LActiveSession.DiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
      for LPath in LFiles do
      begin
        try
          LJsonText := TFile.ReadAllText(LPath, TEncoding.UTF8);
          LObj := TJsonObject.Parse(LJsonText) as TJsonObject;
          if Assigned(LObj) then LList.Add(LObj);
        except
        end;
      end;
      
      // Sort by timestamp descending
      LList.Sort(TComparer<TJsonObject>.Construct(
        function(const Left, Right: TJsonObject): Integer
        begin
          Result := CompareText(Right.S['timestamp'], Left.S['timestamp']);
        end));
        
      for I := 0 to LList.Count - 1 do
      begin
        LItem := LArray.AddObject;
        LItem.Assign(LList[I]);
      end;
    end;
    
    // Send to UI
    LJsonText := LArray.ToJSON(False);
    System.Classes.TThread.Queue(nil, procedure
    var
      LBase64: string;
    begin
      LBase64 := TNetEncoding.Base64.Encode(LJsonText).Replace(#13, '').Replace(#10, '');
      FWebBrowser.EvaluateJavaScript('window.ACP.updateFileHistoryBase64("' + LBase64 + '")');
    end);
  finally
    for I := 0 to LList.Count - 1 do LList[I].Free;
    LList.Free;
    LArray.Free;
  end;
end;

procedure TAgentControl.ExecuteJS(const AScript: string);
begin
  if Assigned(FWebBrowser) then
    FWebBrowser.EvaluateJavaScript(AScript);
end;

procedure TAgentControl.ShowTyping(const AShow: Boolean);
begin
  System.Classes.TThread.Queue(nil, procedure
  begin
    FWebBrowser.EvaluateJavaScript(Format('window.ACP.showProcessing(%s)', [BoolToStr(AShow, True).ToLower]));
  end);
end;

procedure TAgentControl.UpdateMessageStreaming(const ASessionId, AContent: string; const ARole: string; const AStopReason: string);
var
  LObj: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := ASessionId;
    LObj.S['content'] := AContent;
    LObj.S['role'] := ARole; 
    LObj.S['timestamp'] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    if AStopReason <> '' then
      LObj.S['stopReason'] := AStopReason;
    FWebBrowser.EvaluateJavaScript('window.ACP.streamMessage(' + LObj.ToJSON(False) + ')');
  finally
    LObj.Free;
  end;
end;

procedure TAgentControl.UpdateThoughtStreaming(const ASessionId, AContent: string);
var
  LObj: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := ASessionId;
    LObj.S['content'] := AContent;
    FWebBrowser.EvaluateJavaScript('window.ACP.streamThought(' + LObj.ToJSON(False) + ')');
  finally
    LObj.Free;
  end;
end;

function TAgentControl.IsIgnoredDir(const ADirName: string): Boolean;
const
  IGNORED: array[0..5] of string = ('.git', 'node_modules', '__history', '__recovery', '.gemini', 'Win32');
var
  S: string;
begin
  Result := False;
  for S in IGNORED do
    if SameText(ADirName, S) then Exit(True);
end;

procedure TAgentControl.UpdateFileList(const ARootPath: string);
var
  LFiles: TStringDynArray;
  LArray: TJsonArray;
  LPath, LRelPath, LTargetRoot: string;
begin
  LTargetRoot := ARootPath;
  if LTargetRoot = '' then LTargetRoot := FWorkspaceRoot;
  
  if not TDirectory.Exists(LTargetRoot) then Exit;

  // Ensure trailing delimiter to get clean relative paths (filename only for root files)
  LTargetRoot := IncludeTrailingPathDelimiter(LTargetRoot);

  LArray := TJsonArray.Create;
  try
    LFiles := TDirectory.GetFiles(LTargetRoot, '*', TSearchOption.soTopDirectoryOnly);
    for LPath in LFiles do
    begin
      LRelPath := ExtractRelativePath(LTargetRoot, LPath);
      LArray.Add(LRelPath.Replace('\', '/'));
    end;
    FWebBrowser.EvaluateJavaScript('window.ACP.setWorkspaceFiles(' + LArray.ToJSON + ')');
  finally
    LArray.Free;
  end;
end;

procedure TAgentControl.RequestPermissionUI(const ASessionId, AID, AMethod, AToolCallJson, AOptionsJson: string);
var
  LData: TJsonObject;
begin
  LData := TJsonObject.Create;
  try
    LData.S['sessionId'] := ASessionId;
    LData.S['id'] := AID;
    LData.S['method'] := AMethod;
    if AToolCallJson <> '' then
      LData.O['toolCall'].FromJSON(AToolCallJson);
    if AOptionsJson <> '' then
      LData.A['options'].FromJSON(AOptionsJson);
    FWebBrowser.EvaluateJavaScript('window.ACP.renderPermissionRequest(' + LData.ToJSON(False) + ')');
  finally
    LData.Free;
  end;
end;

function TAgentControl.GetWorkspaceDisplayText(const ACwd: string): string;
begin
  if ACwd = '' then Exit('');
  // Use ExcludeTrailingPathDelimiter and TPath.GetFileName to reliably get only the folder name
  Result := TPath.GetFileName(ExcludeTrailingPathDelimiter(ACwd));
end;

procedure TAgentControl.UpdateSessionList;
var
  LArray: TJsonArray;
  LObj, LModels: TJsonObject;
  LSessionInfo: TSessionInfo;
  LData: TSessionData;
  LSessions: TList<TSessionInfo>;
begin
  LArray := TJsonArray.Create;
  try
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSessionInfo in LSessions do
      begin
        LObj := LArray.AddObject;
        LObj.S['id'] := LSessionInfo.SessionId;
        LObj.S['name'] := LSessionInfo.Name;
        LObj.S['workspace'] := GetWorkspaceDisplayText(LSessionInfo.Cwd);
        LObj.B['active'] := FSessionMgr.ActiveSession = LSessionInfo;
        LObj.B['pinned'] := LSessionInfo.IsPinned;
        LObj.B['online'] := LSessionInfo.IsActive; // Use session-specific active flag
        LObj.B['loading'] := LSessionInfo.IsLoading or (Assigned(LSessionInfo.Agent) and (LSessionInfo.Agent.State in [asConnecting, asInitializing]));
        LObj.D['createdAt'] := LSessionInfo.CreatedAt;
        LObj.D['lastConversationDate'] := LSessionInfo.LastConversationDate;
        LObj.S['icon'] := 'forum';

        LObj.S['lastMsg'] := 'Ready to chat...';
        if LSessionInfo.IsLoading then LObj.S['lastMsg'] := 'Starting process...';
        if LSessionInfo.Agent is TGeminiAgent then
        begin
          if TGeminiAgent(LSessionInfo.Agent).Sessions.TryGetValue(LSessionInfo.SessionId, LData) then
          begin
            if LData.ModelsJson <> '' then begin
              LModels := TJsonObject.Parse(LData.ModelsJson) as TJsonObject;
              try 
                LObj.O['models'].Assign(LModels); 
                LObj.S['currentModelId'] := LModels.S['currentModelId'];
              finally LModels.Free; end;
            end;
            if LData.CommandsJson <> '' then LObj.A['commands'].FromJSON(LData.CommandsJson);
          end;
        end;
      end;
    finally
      LSessions.Free;
    end;
    FWebBrowser.EvaluateJavaScript('window.ACP.updateSessionList(' + LArray.ToJSON(False) + ')');
  finally
    LArray.Free;
  end;
end;

end.
