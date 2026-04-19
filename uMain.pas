unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.WebBrowser, uAgent, uGeminiAgent, uACPAgent,
  uSessionManager, uAgentControl, uDebugRPC, JsonDataObjects, uConversationService, uUIControl;

type
  TAgentType = (atGemini, atClaude, atCodex);

  TAgentTypeHelper = record helper for TAgentType
    function ToString: string;
    function AgentClass: TComponentClass;
  end;

  TS = class(TForm)
    WebBrowserMain: TWebBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormShow(Sender: TObject);
    procedure WebBrowserMainDidFinishLoad(ASender: TObject);
    procedure WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
  private
    FSessionMgr: TSessionManager;
    FUIControl: TUIControl;
    FAgentControl: TAgentControl;
    FAgents: TDictionary<TAgentType, TAgent>;
    FInitialized: Boolean;
    procedure DoStatusChange(Sender: TObject; const Msg: string);
    procedure DoResponse(Sender: TObject; const SessionId, Text: string);
    procedure DoNewChat(Sender: TObject; const AgentName: string);
    procedure DoStateChange(Sender: TObject; const OldState, NewState: TAgentState);
    procedure DoMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoRawData(Sender: TObject; const Direction, RawText: string);
    procedure DoPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
    procedure DoSessionMetadataUpdate(Sender: TObject; const SessionId: string);
    procedure DoOpenExplorer(Sender: TObject);
    procedure DoOpenFileViewer(Sender: TObject; const APath: string);
    procedure LoadSessionsFromDisk;
    function GetOrCreateAgent(AType: TAgentType): TAgent;
  public
  end;

var
  S: TS;

implementation

{$R *.fmx}

uses
  System.IOUtils, uACPClient, FMX.Dialogs, uFileExplorer, Winapi.ShellAPI, uFileViewer;

{ TAgentTypeHelper }

function TAgentTypeHelper.AgentClass: TComponentClass;
begin
  case Self of atGemini: Result := TGeminiAgent; else Result := nil; end;
end;

function TAgentTypeHelper.ToString: string;
begin
  case Self of atGemini: Result := 'Gemini'; atClaude: Result := 'Claude'; atCodex: Result := 'Codex'; else Result := ''; end;
end;

{ TS }

procedure TS.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FSessionMgr := TSessionManager.Create;
  FAgents := TDictionary<TAgentType, TAgent>.Create;
  FUIControl := TUIControl.Create;
  FUIControl.OnOpenExplorer := DoOpenExplorer;
  FUIControl.OnOpenFileViewer := DoOpenFileViewer;
  FAgentControl := TAgentControl.Create(WebBrowserMain, FSessionMgr);
  FAgentControl.OnNewChat := DoNewChat;
end;

procedure TS.DoOpenExplorer(Sender: TObject);
var
  LActive: TSessionInfo;
  LPath: string;
begin
  if not Assigned(frmFileExplorer) then
    frmFileExplorer := TfrmFileExplorer.Create(Application);
  
  LPath := '';
  LActive := FSessionMgr.ActiveSession;
  if Assigned(LActive) and (LActive.Cwd <> '') then
    LPath := LActive.Cwd;
    
  if (LPath = '') and Assigned(FAgentControl) then
    LPath := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\'));

  if LPath <> '' then
    frmFileExplorer.Explore(LPath);
    
  frmFileExplorer.Show;
end;

procedure TS.DoOpenFileViewer(Sender: TObject; const APath: string);
var
  LFullPath: string;
  LActive: TSessionInfo;
begin
  LFullPath := APath;
  if not TPath.IsPathRooted(LFullPath) then
  begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and (LActive.Cwd <> '') then
      LFullPath := TPath.Combine(LActive.Cwd, APath);
  end;

  if not Assigned(frmFileViewer) then
    frmFileViewer := TfrmFileViewer.Create(Application);
    
  frmFileViewer.ViewFile(LFullPath);
  frmFileViewer.Show;
end;

function TS.GetOrCreateAgent(AType: TAgentType): TAgent;
var
  LAgent: TAgent;
  LGemini: TGeminiAgent;
begin
  if not FAgents.TryGetValue(AType, LAgent) then
  begin
    if AType = atGemini then
    begin
      LGemini := TGeminiAgent.Create(Self);
      LGemini.OnStatusChange := DoStatusChange;
      LGemini.OnStateChange := DoStateChange;
      LGemini.OnResponse := DoResponse;
      LGemini.OnMessageChunk := DoMessageChunk;
      LGemini.OnThoughtChunk := DoThoughtChunk;
      LGemini.OnRawData := DoRawData;
      LGemini.OnPermissionRequest := DoPermissionRequest;
      LGemini.OnSessionMetadataUpdate := DoSessionMetadataUpdate;
      FAgents.Add(atGemini, LGemini);
      Result := LGemini;
    end
    else Result := nil;
  end
  else Result := LAgent;
end;

procedure TS.LoadSessionsFromDisk;
var
  LBaseDir, LAgentDir, LSessionDir, LSessionId, LAgentName: string;
  LAgent: TAgent;
  LSession: TSessionInfo;
begin
  if not Assigned(FSessionMgr) then Exit;
  LBaseDir := TPath.Combine(FSessionMgr.BaseConfigPath, 'sessions');
  if not TDirectory.Exists(LBaseDir) then Exit;

  for LAgentDir in TDirectory.GetDirectories(LBaseDir) do
  begin
    LAgentName := TPath.GetFileName(LAgentDir);
    if SameText(LAgentName, 'gemini-cli') then
    begin
      LAgent := GetOrCreateAgent(atGemini);
      for LSessionDir in TDirectory.GetDirectories(LAgentDir) do
      begin
        LSessionId := TPath.GetFileName(LSessionDir);
        if LSessionId.StartsWith('pending-') then Continue;
        LSession := FSessionMgr.AddSession(LAgent, LSessionId, 'Loading...');
        if LAgent is TACPAgent then
          TACPAgent(LAgent).SetSessionLogPath(LSessionId, LSession.LogPath);
      end;
    end;
  end;
end;

procedure TS.FormShow(Sender: TObject);
var
  LHtmlPath: string;
begin
  if not FInitialized then
  begin
    FInitialized := True;
    LoadSessionsFromDisk;
    FSessionMgr.SelectSession(nil); 
    LHtmlPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'index.html');
    if TFile.Exists(LHtmlPath) then WebBrowserMain.Navigate('file://' + LHtmlPath);
    if Assigned(frmDebugRPC) then frmDebugRPC.Show;
  end;
end;

procedure TS.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  System.Classes.TThread.ForceQueue(nil, procedure begin 
    if Assigned(WebBrowserMain) and WebBrowserMain.Visible then WebBrowserMain.SetFocus; 
    if Assigned(FAgentControl) then FAgentControl.UpdateSessionList; 
  end);
end;

procedure TS.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  // 1. Allow initial UI file
  if URL.ToLower.Contains('index.html') then Exit;

  // 2. Ignore internal Edge/WebView2 protocols
  if URL.ToLower.StartsWith('about:') or URL.ToLower.StartsWith('javascript:') then Exit;

  // 3. Handle Custom Schemas (acp-action, ui-action)
  if Assigned(FUIControl) and FUIControl.HandleRequest(URL) then Exit;
  if Assigned(FAgentControl) and FAgentControl.HandleRequest(URL) then Exit;

  // 4. Open everything else (External links, local file links) in system default app
  ShellExecute(0, 'open', PChar(URL), nil, nil, SW_SHOWNORMAL);

  // 5. Block internal navigation
  WebBrowserMain.Stop;
end;

procedure TS.DoResponse(Sender: TObject; const SessionId, Text: string);
var
  LActualText, LStopReason: string;
  LStopIdx: Integer;
begin
  LActualText := Text;
  LStopReason := 'end_turn';
  
  LStopIdx := Text.IndexOf('||STOP:');
  if LStopIdx >= 0 then
  begin
    LActualText := Text.Substring(0, LStopIdx);
    LStopReason := Text.Substring(LStopIdx + 7);
  end;

  System.Classes.TThread.Queue(nil, procedure begin 
    if Assigned(FAgentControl) then begin 
      FAgentControl.UpdateMessageStreaming(SessionId, LActualText, 'ai', LStopReason);
      FAgentControl.ShowTyping(False); 
      FAgentControl.UpdateSessionList; 
    end; 
  end);
end;

procedure TS.DoMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var
  LRole, LActualText, LStopReason: string;
  LSessionInfo, LFound: TSessionInfo;
  LSessions: TList<TSessionInfo>;
  LIdx: Integer;
begin
  LRole := 'ai'; LActualText := FullText;
  LStopReason := '';

  if LActualText.StartsWith('USER:') then 
  begin 
    LRole := 'user'; 
    LActualText := LActualText.Substring(5); 
  end;

  LIdx := LActualText.ToLower.IndexOf('--- content from');
  if LIdx < 0 then LIdx := LActualText.ToLower.IndexOf('--- context from');
  if LIdx >= 0 then
    LActualText := LActualText.Substring(0, LIdx).Trim;

  LFound := nil;
  if Assigned(FSessionMgr) then begin
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSessionInfo in LSessions do
        if LSessionInfo.SessionId = SessionId then begin
          LFound := LSessionInfo;
          Break;
        end;
    finally LSessions.Free; end;
  end;

  if Assigned(LFound) then begin
    if LFound.IsLoading or ((Sender is TACPAgent) and TACPAgent(Sender).IsRestoringSession(SessionId)) then
      LStopReason := 'history';
  end;

  System.Classes.TThread.Queue(nil, procedure begin 
    if Assigned(FAgentControl) then 
      FAgentControl.UpdateMessageStreaming(SessionId, LActualText, LRole, LStopReason); 
  end);
end;

procedure TS.DoThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
begin
  System.Classes.TThread.Queue(nil, procedure begin 
    if Assigned(FAgentControl) then 
      FAgentControl.UpdateThoughtStreaming(SessionId, FullText); 
  end);
end;

procedure TS.DoRawData(Sender: TObject; const Direction, RawText: string);
var
  LDir, LRaw: string;
begin
  LDir := Direction;
  LRaw := RawText;
  System.Classes.TThread.Queue(nil, procedure 
  var
    LBase: TJsonBaseObject;
    LObj: TJsonObject;
    LSessionId, LMethod, LUpdateType: string;
    LTargetSession, LSessionInfo: TSessionInfo;
    LDoLog: Boolean;
    LSessions: TList<TSessionInfo>;
  begin
    if Assigned(frmDebugRPC) then frmDebugRPC.AddLog(LDir, LRaw);
    if SameText(LDir, 'SYS') then Exit;
    if not Assigned(FSessionMgr) then Exit;
    
    LBase := nil;
    try
      try
        LBase := TJsonBaseObject.Parse(LRaw);
      except
        on E: Exception do Exit;
      end;
      
      if Assigned(LBase) and (LBase is TJsonObject) then
      begin
        LObj := TJsonObject(LBase);
        LSessionId := LObj.S['sessionId'];
        if LSessionId = '' then LSessionId := LObj.O['params'].S['sessionId'];
        
        if LSessionId <> '' then begin
          LTargetSession := nil;
          LSessions := FSessionMgr.GetSessionListSnapshot;
          try
            for LSessionInfo in LSessions do 
              if LSessionInfo.SessionId = LSessionId then begin
                LTargetSession := LSessionInfo;
                Break;
              end;
          finally
            LSessions.Free;
          end;
            
          if Assigned(LTargetSession) then begin
            LDoLog := True; 
            LMethod := LObj.S['method'];
            if LMethod = '' then LMethod := LObj.O['params'].S['method'];
            
            if SameText(LMethod, 'session/update') then begin
              if LObj.O['params'].Contains('update') and (LObj.O['params'].Items[LObj.O['params'].IndexOf('update')].Typ = jdtObject) then
              begin
                LUpdateType := LObj.O['params'].O['update'].S['sessionUpdate'];
                if SameText(LUpdateType, 'available_commands_update') then LDoLog := False;
              end;
            end;
            if LDoLog then TConversationService.AppendLog(LTargetSession, LDir, LRaw);
          end;
        end;
      end;
    finally LBase.Free; end;
  end);
end;

procedure TS.DoPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: TJsonObject; Options: TJsonArray);
var
  LID, LMethod, LSID, LToolCall, LOptions: string;
begin
  LID := ID; LMethod := Method; LSID := SessionId;
  LToolCall := ToolCall.ToJSON(False);
  LOptions := Options.ToJSON(False);
  System.Classes.TThread.Queue(nil, procedure begin 
    if Assigned(FAgentControl) then 
      FAgentControl.RequestPermissionUI(LSID, LID, LMethod, LToolCall, LOptions); 
  end);
end;

procedure TS.DoSessionMetadataUpdate(Sender: TObject; const SessionId: string);
begin
  System.Classes.TThread.Queue(nil, procedure begin 
    if Assigned(FAgentControl) then 
      FAgentControl.UpdateSessionList; 
  end);
end;

procedure TS.DoStatusChange(Sender: TObject; const Msg: string); 
var
  LMsg: string;
begin 
  LMsg := Msg;
  System.Classes.TThread.Queue(nil, procedure begin
    if Assigned(frmDebugRPC) then frmDebugRPC.AddACPLog('Status: ' + LMsg);
  end);
end;

procedure TS.DoStateChange(Sender: TObject; const OldState, NewState: TAgentState);
var
  LNewState: TAgentState;
  LSender: TObject;
begin
  LNewState := NewState;
  LSender := Sender;
  System.Classes.TThread.Queue(nil, procedure
  var
    LGemini: TGeminiAgent; LTargetSession, LSessionInfo: TSessionInfo;
    LSessions: TList<TSessionInfo>;
  begin
    if (LSender is TGeminiAgent) and (LNewState = asReady) then begin
      LGemini := TGeminiAgent(LSender); LTargetSession := nil;
      if Assigned(FSessionMgr) then
      begin
        LSessions := FSessionMgr.GetSessionListSnapshot;
        try
          for LSessionInfo in LSessions do 
            if (LSessionInfo.Agent = LGemini) and LSessionInfo.IsLoading then begin 
              LTargetSession := LSessionInfo; 
              Break; 
            end;
        finally
          LSessions.Free;
        end;
      end;
      
      if Assigned(LTargetSession) then begin
        LGemini.Workspace := LTargetSession.Cwd;
        if LTargetSession.SessionId.StartsWith('pending-') then begin
          LGemini.CreateNewSession(LTargetSession.Cwd, '', procedure(const SessionId: string)
          begin
            System.Classes.TThread.Queue(nil, procedure begin
              if SessionId <> '' then begin 
                FSessionMgr.FinalizeSessionId(LTargetSession, SessionId); 
                LTargetSession.IsLoading := False; 
                LGemini.SetSessionLogPath(SessionId, LTargetSession.LogPath); 
              end
              else FSessionMgr.DeleteSession(LTargetSession);
              
              if Assigned(FAgentControl) then begin 
                FAgentControl.ShowTyping(False);
                FAgentControl.UpdateSessionList; 
                FAgentControl.UpdateFileList(LTargetSession.Cwd); 
              end;
            end);
          end);
        end else begin
          TConversationService.StartRestoration(LTargetSession);
          LGemini.LoadSession(LTargetSession.SessionId, procedure(const SessionId: string)
          begin
            System.Classes.TThread.Queue(nil, procedure begin
              LTargetSession.IsLoading := False; 
              TConversationService.FinalizeRestoration(LTargetSession);
              if SessionId <> '' then LGemini.SetSessionLogPath(SessionId, LTargetSession.LogPath);
              
              if Assigned(FAgentControl) then begin 
                FAgentControl.ShowTyping(False);
                FAgentControl.UpdateSessionList; 
                FAgentControl.UpdateFileList(LTargetSession.Cwd); 
              end;
            end);
          end);
        end;
      end;
    end;
    if Assigned(FAgentControl) then FAgentControl.UpdateSessionList;
  end);
end;

procedure TS.DoNewChat(Sender: TObject; const AgentName: string);
var
  LAgent: TAgent; LGemini: TGeminiAgent; LPendingId, LSelectedDir: string; LPendingSession: TSessionInfo;
begin
  if SameText(AgentName, 'gemini') then begin
    if not SelectDirectory('Select Project Workspace for Gemini', '', LSelectedDir) then Exit;
    LPendingId := 'pending-' + TGuid.NewGuid.ToString; LAgent := GetOrCreateAgent(atGemini); LGemini := LAgent as TGeminiAgent;
    LPendingSession := FSessionMgr.AddSession(LGemini, LPendingId, FSessionMgr.GetUniqueSessionName('New Chat'), LSelectedDir);
    LPendingSession.IsLoading := True; FSessionMgr.SelectSession(LPendingSession);
    if Assigned(WebBrowserMain) then WebBrowserMain.EvaluateJavaScript('window.ACP.clearChat()');
    if Assigned(FAgentControl) then begin FAgentControl.UpdateSessionList; FAgentControl.UpdateFileList(LSelectedDir); end;
    System.Classes.TThread.Queue(nil, procedure begin
      if LGemini.State = asReady then begin
        LGemini.Workspace := LSelectedDir;
        LGemini.CreateNewSession(LSelectedDir, '', procedure(const SessionId: string)
        begin
          System.Classes.TThread.Queue(nil, procedure begin
            if SessionId <> '' then begin FSessionMgr.FinalizeSessionId(LPendingSession, SessionId); LPendingSession.IsLoading := False; LGemini.SetSessionLogPath(SessionId, LPendingSession.LogPath); end
            else FSessionMgr.DeleteSession(LPendingSession);
            if Assigned(FAgentControl) then begin FAgentControl.UpdateSessionList; FAgentControl.UpdateFileList(LSelectedDir); end;
          end);
        end);
      end else if LGemini.State in [asDisconnected, asError] then LGemini.Connect;
    end);
  end;
end;

procedure TS.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var LSession: TSessionInfo; LData: TSessionData; LSessions: TList<TSessionInfo>;
begin
  CanClose := True;
  if Assigned(FSessionMgr) then
  begin
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSession in LSessions do
        if (LSession.Agent is TACPAgent) and (LSession.SessionId <> '') then
          if TACPAgent(LSession.Agent).Sessions.TryGetValue(LSession.SessionId, LData) then
            if LData.IsProcessing then if LSession.Agent is TGeminiAgent then TGeminiAgent(LSession.Agent).CancelPrompt(LSession.SessionId);
    finally
      LSessions.Free;
    end;
  end;
end;

procedure TS.FormClose(Sender: TObject; var Action: TCloseAction);
var Agent: TAgent;
begin
  if Assigned(FAgentControl) then FreeAndNil(FAgentControl);
  if Assigned(FUIControl) then FreeAndNil(FUIControl);
  if Assigned(FSessionMgr) then FreeAndNil(FSessionMgr);
  if Assigned(FAgents) then begin
    for Agent in FAgents.Values do begin Agent.Stop; Agent.Free; end;
    FAgents.Free;
  end;
end;

end.
