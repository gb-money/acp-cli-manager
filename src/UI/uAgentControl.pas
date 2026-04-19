unit uAgentControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, uSessionManager, uAgent,
  System.NetEncoding, FMX.Dialogs, System.Actions, FMX.ActnList, System.IOUtils,
  System.UITypes, System.Generics.Collections, uWebACPCommandHandler;

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
    procedure HandleGetFileContent(const Params: TDictionary<string, string>);
    procedure HandleOpenFileDialog(const Params: TDictionary<string, string>);
    function IsIgnoredDir(const ADirName: string): Boolean;
    function GetWorkspaceDisplayText(const ACwd: string): string;
  public
    constructor Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    procedure UpdateSessionList;
    procedure UpdateMessageStreaming(const ASessionId, AContent: string; const ARole: string = 'ai');
    procedure UpdateThoughtStreaming(const ASessionId, AContent: string);
    procedure UpdateFileList(const ARootPath: string = '');
    procedure RequestPermissionUI(const ASessionId, AID, AMethod, AToolCallJson: string);
    procedure ShowTyping(const AShow: Boolean);
    property OnNewChat: TNewChatEvent read FOnNewChat write FOnNewChat;
  end;

implementation

uses
  JsonDataObjects, FMX.Forms, uGeminiAgent, uACPAgent, System.Types, uConversationService, uDebugRPC;

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
  else if Action = 'resume-session' then HandleResumeSession(Params)
  else if Action = 'change-model' then HandleChangeModel(Params)
  else if Action = 'permission-response' then HandlePermissionResponse(Params)
  else if Action = 'cancel-prompt' then HandleCancelPrompt(Params)
  else if Action = 'get-file-content' then HandleGetFileContent(Params)
  else if Action = 'open-file-dialog' then HandleOpenFileDialog(Params)
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
  LSessionId, LJsonStr: string;
  LTargetSession, LSession: TSessionInfo;
  LMessages: TJsonArray;
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
      
      // 비동기 실행 시 LTargetSession이 여전히 유효한지 체크 (AV 방어)
      System.Classes.TThread.Queue(nil, procedure
      var
        LInnerMsg: TJsonArray;
        LInnerJson: string;
      begin
        if not Assigned(LTargetSession) then Exit;
        
        UpdateFileList(LTargetSession.Cwd);
        LInnerMsg := TConversationService.GetConversationsBySessionId(LTargetSession);
        try
          LInnerJson := LInnerMsg.ToJSON(False);
          LInnerJson := TNetEncoding.Base64.Encode(LInnerJson).Replace(#13, '').Replace(#10, '');
          FWebBrowser.EvaluateJavaScript('window.ACP.loadHistoryBase64("' + LInnerJson + '")');
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
       if Assigned(LTargetSession.Agent) and (LTargetSession.Agent.State in [asDisconnected, asError]) then
       begin
         LTargetSession.IsLoading := True; 
         LTargetSession.Agent.Connect;
       end;
       UpdateSessionList;
    end;
  end;
end;

procedure TAgentControl.HandleAction(const Params: TDictionary<string, string>);
begin
  // Action module removed
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

procedure TAgentControl.ShowTyping(const AShow: Boolean);
begin
  System.Classes.TThread.Queue(nil, procedure
  begin
    FWebBrowser.EvaluateJavaScript(Format('window.ACP.showTyping(%s)', [BoolToStr(AShow, True).ToLower]));
  end);
end;

procedure TAgentControl.UpdateMessageStreaming(const ASessionId, AContent: string; const ARole: string);
var
  LObj: TJsonObject;
begin
  LObj := TJsonObject.Create;
  try
    LObj.S['sessionId'] := ASessionId;
    LObj.S['content'] := AContent;
    LObj.S['role'] := ARole; 
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

  LArray := TJsonArray.Create;
  try
    // 성능을 위해 재귀 스캔을 끄고 루트 파일만 먼저 보여줌 (Slowness 해결)
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

procedure TAgentControl.RequestPermissionUI(const ASessionId, AID, AMethod, AToolCallJson: string);
begin
  FWebBrowser.EvaluateJavaScript(Format('window.ACP.showPermissionRequest({sessionId: "%s", id: "%s", method: "%s", toolCall: %s})', 
    [ASessionId, AID, AMethod, AToolCallJson]));
end;

function TAgentControl.GetWorkspaceDisplayText(const ACwd: string): string;
var
  LFolderName, LOtherFolderName: string;
  LSessionInfo: TSessionInfo;
  LIsDuplicate: Boolean;
  LSessions: TList<TSessionInfo>;
begin
  if ACwd = '' then Exit('');
  LFolderName := TPath.GetFileName(ACwd);
  LIsDuplicate := False;
  
  LSessions := FSessionMgr.GetSessionListSnapshot;
  try
    for LSessionInfo in LSessions do
    begin
      if LSessionInfo.Cwd = ACwd then Continue;
      if LSessionInfo.Cwd = '' then Continue;
      LOtherFolderName := TPath.GetFileName(LSessionInfo.Cwd);
      if SameText(LFolderName, LOtherFolderName) then begin LIsDuplicate := True; Break; end;
    end;
  finally
    LSessions.Free;
  end;
  if LIsDuplicate then Result := ACwd else Result := LFolderName;
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
        LObj.B['active'] := (FSessionMgr.ActiveSession = LSessionInfo);
        LObj.B['pinned'] := LSessionInfo.IsPinned;
        LObj.B['online'] := Assigned(LSessionInfo.Agent) and (LSessionInfo.Agent.State = asReady);
        LObj.B['loading'] := LSessionInfo.IsLoading or (Assigned(LSessionInfo.Agent) and (LSessionInfo.Agent.State in [asConnecting, asInitializing]));
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
