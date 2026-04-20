unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.WebBrowser, uAgent, uGeminiAgent, uACPAgent,
  uSessionManager, uAgentControl, uDebugRPC, JsonDataObjects, uConversationService, uUIControl, uSearchService, System.SyncObjs;

type
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
    FSearchService: TSearchService;
    FAgents: TDictionary<TAgentType, TAgent>;
    FInitialized: Boolean;
    procedure DoStatusChange(Sender: TObject; const Msg: string);
    procedure DoResponse(Sender: TObject; const SessionId, Text: string);
    procedure DoNewChat(Sender: TObject; const AgentName: string);
    procedure DoStateChange(Sender: TObject; const OldState, NewState: TAgentState);
    procedure DoMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoFSWrite(Sender: TObject; const SessionId, Path, OldContent, NewContent: string);
    procedure DoRawData(Sender: TObject; const Direction, RawText: string);
    procedure DoPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: JsonDataObjects.TJsonObject; Options: JsonDataObjects.TJsonArray);
    procedure DoSessionMetadataUpdate(Sender: TObject; const SessionId: string);
    procedure DoOpenExplorer(Sender: TObject);
    procedure DoOpenFileViewer(Sender: TObject; const APath: string);
    procedure DoOpenDiffViewer(Sender: TObject; const ASessionId, APath, AHashId: string);
    procedure DoSessionRestored(Sender: TObject; ASession: TSessionInfo);
    procedure DoSearchComplete(const AResults: TArray<TSearchSessionResult>);
    procedure LoadSessionsFromDisk;
    function GetOrCreateAgent(AType: TAgentType): TAgent;
  public
    procedure StartSessionRestoration(ASession: TSessionInfo);
  end;

var
  S: TS;

implementation

{$R *.fmx}

uses
  System.IOUtils, uACPClient, FMX.Dialogs, uFileExplorer, Winapi.ShellAPI, uFileViewer, uDiffViewer, System.RegularExpressions, System.NetEncoding;

{ TAgentTypeHelper }

function TAgentTypeHelper.AgentClass: TComponentClass;
begin
  case Self of 
    atGemini: Result := TGeminiAgent; 
    else Result := nil; 
  end;
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
  FSessionMgr.OnSessionRestored := DoSessionRestored;
  FAgents := TDictionary<TAgentType, TAgent>.Create;
  FUIControl := TUIControl.Create;
  FUIControl.OnOpenExplorer := DoOpenExplorer;
  FUIControl.OnOpenFileViewer := DoOpenFileViewer;
  FUIControl.OnOpenDiffViewer := DoOpenDiffViewer;
  FAgentControl := TAgentControl.Create(WebBrowserMain, FSessionMgr);
  FAgentControl.OnNewChat := DoNewChat;

  FSearchService := TSearchService.Create;
  FSearchService.BaseConfigPath := FSessionMgr.BaseConfigPath;
  FSearchService.OnSearchComplete := DoSearchComplete;

  Self.WindowState := TWindowState.wsMaximized;
end;

procedure TS.DoSessionRestored(Sender: TObject; ASession: TSessionInfo);
begin
  System.Classes.TThread.Queue(nil, procedure 
  begin
    if Assigned(ASession) and Assigned(FAgentControl) then
    begin
      FAgentControl.UpdateFileList(ASession.Cwd);
      FAgentControl.UpdateSessionList;
    end;
  end);
end;

procedure TS.StartSessionRestoration(ASession: TSessionInfo);
var
  LACPAgent: TACPAgent;
  LSession: TSessionInfo;
begin
  if not Assigned(ASession) or not (ASession.Agent is TACPAgent) then Exit;
  LACPAgent := TACPAgent(ASession.Agent);
  LSession := ASession;
  
  LACPAgent.Workspace := LSession.Cwd;
  if LSession.SessionId.StartsWith('pending-') then begin
    LACPAgent.CreateNewSession(LSession.Cwd, '', procedure(SessionId: string)
    var LSid: string;
    begin
      LSid := SessionId;
      System.Classes.TThread.Queue(nil, procedure 
      begin
        if LSid <> '' then begin 
          FSessionMgr.FinalizeSessionId(LSession, LSid); 
          LSession.IsLoading := False; 
          LSession.IsActive := True; 
          LACPAgent.SetSessionLogPath(LSid, LSession.LogPath); 
        end
        else FSessionMgr.DeleteSession(LSession);
        
        if Assigned(FAgentControl) then begin 
          FAgentControl.ShowTyping(False);
          FAgentControl.UpdateSessionList; 
          FAgentControl.UpdateFileList(LSession.Cwd); 
        end;
      end);
    end);
  end else begin
    TConversationService.StartRestoration(LSession);
    LACPAgent.LoadSession(LSession.SessionId, procedure(SessionId: string)
    var LSid: string;
    begin
      LSid := SessionId;
      System.Classes.TThread.Queue(nil, procedure 
      begin
        if LSid = '' then
        begin
          FSessionMgr.DeleteSession(LSession);
          if Assigned(FAgentControl) then FAgentControl.UpdateSessionList;
          Exit;
        end;

        TConversationService.FinalizeRestoration(LSession);
        if LSid <> '' then LACPAgent.SetSessionLogPath(LSid, LSession.LogPath);
        
        if Assigned(FAgentControl) then begin 
          FAgentControl.UpdateSessionList; 
        end;
      end);
    end);
  end;
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

procedure TS.DoOpenDiffViewer(Sender: TObject; const ASessionId, APath, AHashId: string);
begin
  if not Assigned(frmDiffViewer) then
    frmDiffViewer := TfrmDiffViewer.Create(Application);
    
  frmDiffViewer.ViewDiffSession(FSessionMgr, ASessionId, APath, AHashId);
  frmDiffViewer.Show;
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
      LGemini.OnFSWrite := DoFSWrite;
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
  LBaseDir, LAgentDir, LSessionDir, LSessionId, LAgentName, LHistoryPath: string;
  LAgent: TAgent;
  LSession: TSessionInfo;
  LType: TAgentType;
begin
  if not Assigned(FSessionMgr) then Exit;
  LBaseDir := TPath.Combine(FSessionMgr.BaseConfigPath, 'sessions');
  if not TDirectory.Exists(LBaseDir) then Exit;

  for LAgentDir in TDirectory.GetDirectories(LBaseDir) do
  begin
    LAgentName := TPath.GetFileName(LAgentDir);
    LType := atGemini;
    if SameText(LAgentName, 'gemini-cli') then LType := atGemini
    else if SameText(LAgentName, 'claude-cli') then LType := atClaude
    else if SameText(LAgentName, 'codex-cli') then LType := atCodex
    else Continue;

    LAgent := GetOrCreateAgent(LType);
    if not Assigned(LAgent) then Continue;

    for LSessionDir in TDirectory.GetDirectories(LAgentDir) do
    begin
      LSessionId := TPath.GetFileName(LSessionDir);
      if LSessionId.StartsWith('pending-') then Continue;

      LHistoryPath := TPath.Combine(LSessionDir, 'history.json');
      if not TFile.Exists(LHistoryPath) or (TFile.GetSize(LHistoryPath) < 10) then
        Continue;

      LSession := FSessionMgr.AddSession(LAgent, LType, LSessionId, 'Loading...');
      if LAgent is TACPAgent then
        TACPAgent(LAgent).SetSessionLogPath(LSessionId, LSession.LogPath);
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
  end;
end;

procedure TS.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  System.Classes.TThread.ForceQueue(nil, procedure 
  begin 
    if Assigned(WebBrowserMain) and WebBrowserMain.Visible then WebBrowserMain.SetFocus; 
    if Assigned(FAgentControl) then FAgentControl.UpdateSessionList; 
  end);
end;

procedure TS.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if URL.IsEmpty then Exit;
  if URL.ToLower.Contains('index.html') then Exit;
  if URL.ToLower.StartsWith('about:') or URL.ToLower.StartsWith('javascript:') then Exit;

  if URL.ToLower.StartsWith('acp-action://search-conversations') then
  begin
    var LQuery := '';
    var LIdx := URL.IndexOf('query=');
    if LIdx > 0 then LQuery := System.NetEncoding.TNetEncoding.URL.Decode(URL.Substring(LIdx + 6));
    if LQuery.Contains('&') then LQuery := LQuery.Substring(0, LQuery.IndexOf('&'));
    
    var LOpts: TSearchOptions;
    LOpts.CaseSensitive := URL.Contains('case=true');
    LOpts.UseRegex := URL.Contains('regex=true');
    LOpts.IncludeActive := not URL.Contains('active=false');
    LOpts.IncludeInactive := not URL.Contains('inactive=false');
    LOpts.IncludeUser := not URL.Contains('user=false');
    LOpts.IncludeAgent := not URL.Contains('agent=false');
    LOpts.IncludeThought := URL.Contains('thought=true');
    
    LOpts.TargetSessionId := '';
    LIdx := URL.IndexOf('targetSessionId=');
    if LIdx > 0 then begin
      LOpts.TargetSessionId := URL.Substring(LIdx + 16);
      if LOpts.TargetSessionId.Contains('&') then
        LOpts.TargetSessionId := LOpts.TargetSessionId.Substring(0, LOpts.TargetSessionId.IndexOf('&'));
      LOpts.TargetSessionId := System.NetEncoding.TNetEncoding.URL.Decode(LOpts.TargetSessionId);
    end;

    FSearchService.Search(LQuery, LOpts);
    WebBrowserMain.Stop;
    Exit;
  end;

  if Assigned(FUIControl) and FUIControl.HandleRequest(URL) then Exit;
  if Assigned(FAgentControl) and FAgentControl.HandleRequest(URL) then Exit;

  Winapi.ShellAPI.ShellExecute(0, 'open', PChar(URL), nil, nil, SW_SHOWNORMAL);
  WebBrowserMain.Stop;
end;

procedure TS.DoResponse(Sender: TObject; const SessionId, Text: string);
var
  LActualText, LStopReason, LSid: string;
begin
  LActualText := Text;
  LStopReason := 'end_turn';
  LSid := SessionId;
  
  var LStopIdx := Text.IndexOf('||STOP:');
  if LStopIdx >= 0 then
  begin
    LActualText := Text.Substring(0, LStopIdx);
    LStopReason := Text.Substring(LStopIdx + 7);
  end;

  System.Classes.TThread.Queue(nil, procedure 
  begin 
    if Assigned(FAgentControl) then begin 
      FAgentControl.UpdateMessageStreaming(LSid, LActualText, 'ai', LStopReason);
      FAgentControl.ShowTyping(False); 
      FAgentControl.UpdateSessionList; 
    end; 
  end);
end;

procedure TS.DoMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var
  LRole, LActualText, LStopReason, LSid: string;
  LSessionInfo, LFound: TSessionInfo;
  LSessions: TList<TSessionInfo>;
  LIdx: Integer;
begin
  LRole := 'ai'; LActualText := FullText;
  LStopReason := ''; LSid := SessionId;
  if LActualText.StartsWith('USER:') then 
  begin 
    LRole := 'user'; 
    LActualText := LActualText.Substring(5); 
  end;
  LIdx := LActualText.ToLower.IndexOf('--- content from');
  if LIdx < 0 then LIdx := LActualText.ToLower.IndexOf('--- context from');
  if LIdx >= 0 then LActualText := LActualText.Substring(0, LIdx).Trim;

  LFound := nil;
  if Assigned(FSessionMgr) then begin
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSessionInfo in LSessions do
        if LSessionInfo.SessionId = LSid then begin LFound := LSessionInfo; Break; end;
    finally LSessions.Free; end;
  end;
  if Assigned(LFound) then begin
    if LFound.IsLoading or ((Sender is TACPAgent) and TACPAgent(Sender).IsRestoringSession(LSid)) then
    begin
      LStopReason := 'history';
      FSessionMgr.RecordActivity(LSid);
    end;
  end;
  System.Classes.TThread.Queue(nil, procedure 
  begin 
    if Assigned(FAgentControl) then 
      if LStopReason <> 'history' then
        FAgentControl.UpdateMessageStreaming(LSid, LActualText, LRole, LStopReason); 
  end);
end;

procedure TS.DoThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
var LSid, LFull: string;
begin
  LSid := SessionId; LFull := FullText;
  System.Classes.TThread.Queue(nil, procedure 
  begin 
    if Assigned(FAgentControl) then FAgentControl.UpdateThoughtStreaming(LSid, LFull); 
  end);
end;

procedure TS.DoFSWrite(Sender: TObject; const SessionId, Path, OldContent, NewContent: string);
var
  LSessionInfo, LFound: TSessionInfo;
  LSessions: TList<TSessionInfo>;
begin
  LFound := nil;
  if Assigned(FSessionMgr) then begin
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSessionInfo in LSessions do
        if LSessionInfo.SessionId = SessionId then begin LFound := LSessionInfo; Break; end;
    finally LSessions.Free; end;
  end;
  if Assigned(LFound) then TConversationService.SaveFileDiff(LFound, Path, OldContent, NewContent);
end;

procedure TS.DoRawData(Sender: TObject; const Direction, RawText: string);
var
  LDir, LRaw: string;
begin
  LDir := Direction; LRaw := RawText;
  System.Classes.TThread.Queue(nil, procedure 
  var
    LBase: JsonDataObjects.TJsonBaseObject; LObj: JsonDataObjects.TJsonObject; LSessionId, LMethod, LUpdateType: string;
    LTargetSession, LSessionInfo: TSessionInfo; LDoLog: Boolean; LSessions: TList<TSessionInfo>;
  begin
    if Assigned(frmDebugRPC) then frmDebugRPC.AddLog(LDir, LRaw);
    if SameText(LDir, 'SYS') then Exit;
    if not Assigned(FSessionMgr) then Exit;
    LBase := nil;
    try
      try LBase := JsonDataObjects.TJsonBaseObject.Parse(LRaw); except on E: Exception do Exit; end;
      if Assigned(LBase) and (LBase is JsonDataObjects.TJsonObject) then
      begin
        LObj := JsonDataObjects.TJsonObject(LBase);
        LSessionId := LObj.S['sessionId'];
        if LSessionId = '' then LSessionId := LObj.O['params'].S['sessionId'];
        if LSessionId <> '' then begin
          LTargetSession := nil; LSessions := FSessionMgr.GetSessionListSnapshot;
          try
            for LSessionInfo in LSessions do 
              if LSessionInfo.SessionId = LSessionId then begin LTargetSession := LSessionInfo; Break; end;
          finally LSessions.Free; end;
          if Assigned(LTargetSession) then begin
            LDoLog := True; LMethod := LObj.S['method'];
            if LMethod = '' then LMethod := LObj.O['params'].S['method'];
            if SameText(LMethod, 'session/update') then begin
              if LObj.O['params'].Contains('update') and (LObj.O['params'].Items[LObj.O['params'].IndexOf('update')].Typ = jdtObject) then
              begin
                LUpdateType := LObj.O['params'].O['update'].S['sessionUpdate'];
                
                // Break grouping if not a chunk to ensure new bubble for next content
                if not (SameText(LUpdateType, 'agent_message_chunk') or 
                        SameText(LUpdateType, 'user_message_chunk') or 
                        SameText(LUpdateType, 'agent_thought_chunk')) then
                begin
                   System.Classes.TThread.Queue(nil, procedure begin
                     if Assigned(FAgentControl) then FAgentControl.BreakGrouping;
                   end);
                end;

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

procedure TS.DoPermissionRequest(Sender: TObject; const ID, Method, SessionId: string; ToolCall: JsonDataObjects.TJsonObject; Options: JsonDataObjects.TJsonArray);
var
  LID, LMethod, LSID, LToolCall, LOptions: string;
begin
  LID := ID; LMethod := Method; LSID := SessionId;
  LToolCall := ToolCall.ToJSON(False); LOptions := Options.ToJSON(False);
  System.Classes.TThread.Queue(nil, procedure 
  begin 
    if Assigned(FAgentControl) then 
      FAgentControl.RequestPermissionUI(LSID, LID, LMethod, LToolCall, LOptions); 
  end);
end;

procedure TS.DoSessionMetadataUpdate(Sender: TObject; const SessionId: string);
var
  LSession, LSessionInfo: TSessionInfo; LSessions: TList<TSessionInfo>;
  LSid: string;
begin
  LSid := SessionId;
  LSession := nil;
  if Assigned(FSessionMgr) then begin
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSessionInfo in LSessions do
        if LSessionInfo.SessionId = LSid then begin LSession := LSessionInfo; Break; end;
    finally LSessions.Free; end;
  end;
  if Assigned(LSession) and LSession.IsLoading then
  begin
    LSession.IsLoading := False; LSession.IsActive := True;
    if Assigned(FAgentControl) then FAgentControl.UpdateFileList(LSession.Cwd);
  end;
  System.Classes.TThread.Queue(nil, procedure 
  begin if Assigned(FAgentControl) then FAgentControl.UpdateSessionList; end);
end;

procedure TS.DoSearchComplete(const AResults: TArray<TSearchSessionResult>);
var
  LRoot: JsonDataObjects.TJsonArray; LSessObj, LMatchObj: JsonDataObjects.TJsonObject; LMatchesArr: JsonDataObjects.TJsonArray;
  LSess: TSearchSessionResult; LMatch: TSearchMatch;
  LJsonStr: string;
begin
  LRoot := JsonDataObjects.TJsonArray.Create;
  try
    for LSess in AResults do
    begin
      LSessObj := LRoot.AddObject;
      LSessObj.S['sessionId'] := LSess.SessionId;
      LSessObj.S['agentType'] := LSess.AgentType;
      LSessObj.S['name'] := LSess.SessionName;
      LSessObj.S['workspace'] := LSess.Workspace;
      LMatchesArr := LSessObj.A['matches'];
      for LMatch in LSess.Matches do
      begin
        LMatchObj := LMatchesArr.AddObject;
        LMatchObj.S['timestamp'] := LMatch.Timestamp;
        LMatchObj.S['role'] := LMatch.Role;
        LMatchObj.S['snippet'] := LMatch.Snippet;
        LMatchObj.I['index'] := LMatch.MessageIndex;
      end;
    end;
    LJsonStr := LRoot.ToJSON(False);
    System.Classes.TThread.Queue(nil, procedure 
    var LBase64: string;
    begin
      if Assigned(FAgentControl) then
      begin
        LBase64 := System.NetEncoding.TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LJsonStr)).Replace(#13, '').Replace(#10, '');
        FAgentControl.ExecuteJS('window.ACP.updateSearchResults("' + LBase64 + '")');
      end;
    end);
  finally LRoot.Free; end;
end;

procedure TS.DoStatusChange(Sender: TObject; const Msg: string); 
var LMsg: string;
begin 
  LMsg := Msg;
  System.Classes.TThread.Queue(nil, procedure 
  begin if Assigned(frmDebugRPC) then frmDebugRPC.AddACPLog('Status: ' + LMsg); end);
end;

procedure TS.DoStateChange(Sender: TObject; const OldState, NewState: TAgentState);
var LNewState: TAgentState; LSender: TObject;
begin
  LNewState := NewState; LSender := Sender;
  System.Classes.TThread.Queue(nil, procedure
  var
    LACPAgent: TACPAgent; LTargetSession, LSessionInfo: TSessionInfo; LSessions: TList<TSessionInfo>;
  begin
    if LSender is TAgent then
    begin
      if LNewState = asReady then
      begin
        LSessions := FSessionMgr.GetSessionListSnapshot;
        try
          for LSessionInfo in LSessions do
            if LSessionInfo.Agent = LSender then LSessionInfo.IsActive := False;
        finally LSessions.Free; end;
      end;
    end;
    if (LSender is TACPAgent) and (LNewState = asReady) then begin
      LACPAgent := TACPAgent(LSender); LTargetSession := nil;
      if Assigned(FSessionMgr) then
      begin
        LSessions := FSessionMgr.GetSessionListSnapshot;
        try
          for LSessionInfo in LSessions do 
            if (LSessionInfo.Agent = LACPAgent) and LSessionInfo.IsLoading then begin LTargetSession := LSessionInfo; Break; end;
        finally LSessions.Free; end;
      end;
      if Assigned(LTargetSession) then StartSessionRestoration(LTargetSession);
    end;
    if Assigned(FAgentControl) then FAgentControl.UpdateSessionList;
  end);
end;

procedure TS.DoNewChat(Sender: TObject; const AgentName: string);
var
  LAgent: TAgent; LGemini: TGeminiAgent; LPendingId, LSelectedDir, LAgentName: string; LPendingSession: TSessionInfo;
begin
  LAgentName := AgentName;
  if SameText(LAgentName, 'gemini') then begin
    if not SelectDirectory('Select Project Workspace for Gemini', '', LSelectedDir) then Exit;
    LPendingId := 'pending-' + TGuid.NewGuid.ToString; LAgent := GetOrCreateAgent(atGemini); LGemini := LAgent as TGeminiAgent;
    LPendingSession := FSessionMgr.AddSession(LGemini, atGemini, LPendingId, FSessionMgr.GetUniqueSessionName('New Chat'), LSelectedDir);
    LPendingSession.IsLoading := True; FSessionMgr.SelectSession(LPendingSession);
    if Assigned(WebBrowserMain) then WebBrowserMain.EvaluateJavaScript('window.ACP.clearChat()');
    if Assigned(FAgentControl) then begin FAgentControl.UpdateSessionList; FAgentControl.UpdateFileList(LSelectedDir); end;
    System.Classes.TThread.Queue(nil, procedure 
    begin
      if LGemini.State = asReady then begin
        LGemini.Workspace := LSelectedDir;
        LGemini.CreateNewSession(LSelectedDir, '', procedure(SessionId: string)
        var LSid: string;
        begin
          LSid := SessionId;
          System.Classes.TThread.Queue(nil, procedure 
          begin
            if LSid <> '' then begin FSessionMgr.FinalizeSessionId(LPendingSession, LSid); LPendingSession.IsLoading := False; LGemini.SetSessionLogPath(LSid, LPendingSession.LogPath); end
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
    finally LSessions.Free; end;
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
