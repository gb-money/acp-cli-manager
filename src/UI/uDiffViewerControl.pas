unit uDiffViewerControl;

interface

uses
  System.SysUtils, System.Classes, System.Types, FMX.WebBrowser, System.IOUtils, System.NetEncoding,
  JsonDataObjects, uACPAgent, uSessionManager, uWebACPCommandHandler, System.Generics.Collections, System.Generics.Defaults;

type
  TDiffViewerControl = class
  private
    FWebBrowser: TWebBrowser;
    FSessionMgr: TSessionManager;
    FCommandHandler: TWebACPCommandHandler;
    
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleReady(const Params: TDictionary<string, string>);
    procedure HandleSelectSession(const Params: TDictionary<string, string>);
    procedure HandleLoadDiff(const Params: TDictionary<string, string>);
    
    procedure SendSessionList;
    procedure SendFileHistory(const ASessionId: string);
  public
    constructor Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    procedure InitDiffSession(const ASessionId, ATargetPath, AHashId: string);
  end;

implementation

{ TDiffViewerControl }

constructor TDiffViewerControl.Create(AWebBrowser: TWebBrowser; ASessionMgr: TSessionManager);
begin
  FWebBrowser := AWebBrowser;
  FSessionMgr := ASessionMgr;
  FCommandHandler := TWebACPCommandHandler.Create;
  FCommandHandler.OnCommand := HandleInternalCommand;
end;

destructor TDiffViewerControl.Destroy;
begin
  FCommandHandler.Free;
  inherited;
end;

function TDiffViewerControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := FCommandHandler.HandleUrl(AUrl, 'acp-action://');
end;

procedure TDiffViewerControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'ready' then HandleReady(Params)
  else if Action = 'select-session' then HandleSelectSession(Params)
  else if Action = 'load-diff' then HandleLoadDiff(Params);
end;

procedure TDiffViewerControl.InitDiffSession(const ASessionId, ATargetPath, AHashId: string);
var
  LTargetSession, LSession: TSessionInfo;
  LSessions: TList<TSessionInfo>;
begin
  LTargetSession := nil;
  if ASessionId <> '' then
  begin
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSession in LSessions do
        if LSession.SessionId = ASessionId then begin
          LTargetSession := LSession;
          Break;
        end;
    finally LSessions.Free; end;
  end;

  if Assigned(LTargetSession) then
  begin
    FWebBrowser.EvaluateJavaScript('window.ACP.targetPath = "' + ATargetPath.Replace('\', '\\').Replace('"', '\"') + '"');
    FWebBrowser.EvaluateJavaScript('window.ACP.targetHashId = "' + AHashId + '"');
    FWebBrowser.EvaluateJavaScript('window.ACP.selectSession("' + LTargetSession.SessionId + '")');
  end;
end;

procedure TDiffViewerControl.HandleReady(const Params: TDictionary<string, string>);
begin
  SendSessionList;
end;

procedure TDiffViewerControl.HandleSelectSession(const Params: TDictionary<string, string>);
var
  LSessionId: string;
begin
  if Params.TryGetValue('id', LSessionId) then
  begin
    SendSessionList; 
    SendFileHistory(LSessionId);
  end;
end;

procedure TDiffViewerControl.HandleLoadDiff(const Params: TDictionary<string, string>);
var
  LSessionId, LHashId: string;
  LTargetSession, LSession: TSessionInfo;
  LDiffPath, LJsonText: string;
  LObj: TJsonObject;
  LSessions: TList<TSessionInfo>;
  LFiles: TStringDynArray;
  LFile: string;
  LFoundObj: TJsonObject;
  LOldContent, LNewContent, LFileName, LFilePath: string;
begin
  if Params.TryGetValue('sessionId', LSessionId) and Params.TryGetValue('hashId', LHashId) then
  begin
    LTargetSession := nil;
    LSessions := FSessionMgr.GetSessionListSnapshot;
    try
      for LSession in LSessions do
        if LSession.SessionId = LSessionId then begin
          LTargetSession := LSession;
          Break;
        end;
    finally LSessions.Free; end;

    if Assigned(LTargetSession) and (LTargetSession.DiffsPath <> '') then
    begin
      LFoundObj := nil;
      if TDirectory.Exists(LTargetSession.DiffsPath) then
      begin
        LFiles := TDirectory.GetFiles(LTargetSession.DiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
        for LFile in LFiles do
        begin
          try
            LJsonText := TFile.ReadAllText(LFile, TEncoding.UTF8);
            LObj := TJsonObject.Parse(LJsonText) as TJsonObject;
            if Assigned(LObj) then
            begin
              if LObj.S['id'] = LHashId then
              begin
                LFoundObj := LObj;
                Break;
              end
              else
                LObj.Free;
            end;
          except
          end;
        end;
      end;

      if Assigned(LFoundObj) then
      begin
        LOldContent := LFoundObj.S['oldContent'];
        LNewContent := LFoundObj.S['newContent'];
        LFileName := TPath.GetFileName(LFoundObj.S['path']);
        LFilePath := LFoundObj.S['path'];
        LFoundObj.Free;

        System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
        var
          LScript: string;
          LOld64, LNew64: string;
        begin
          // We use Base64 to safely pass huge strings to JS without quote escaping issues
          LOld64 := TNetEncoding.Base64.Encode(LOldContent).Replace(#13, '').Replace(#10, '');
          LNew64 := TNetEncoding.Base64.Encode(LNewContent).Replace(#13, '').Replace(#10, '');
          
          LScript := Format('var o=decodeURIComponent(escape(window.atob("%s"))); var n=decodeURIComponent(escape(window.atob("%s"))); window.ACP.loadDiffFromData("%s", "%s", o, n);',
            [LOld64, LNew64, LFileName, LFilePath.Replace('\', '\\').Replace('"', '\"')]);
          FWebBrowser.EvaluateJavaScript(LScript);
        end));
      end;
    end;
  end;
end;

procedure TDiffViewerControl.SendSessionList;
var
  LArray: TJsonArray;
  LObj: TJsonObject;
  LSessionInfo: TSessionInfo;
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
        LObj.S['workspace'] := LSessionInfo.Cwd; 
        LObj.B['active'] := False; // Handled by JS
        LObj.B['online'] := True; // Mock
      end;
    finally
      LSessions.Free;
    end;
    System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
    begin
      FWebBrowser.EvaluateJavaScript('window.ACP.updateSessionList(' + LArray.ToJSON(False) + ')');
    end));
  finally
    LArray.Free;
  end;
end;

procedure TDiffViewerControl.SendFileHistory(const ASessionId: string);
var
  LTargetSession, LSession: TSessionInfo;
  LFiles: TStringDynArray;
  LPath, LJsonText: string;
  LArray: TJsonArray;
  LObj, LItem: TJsonObject;
  LList: TList<TJsonObject>;
  LSessions: TList<TSessionInfo>;
  I: Integer;
begin
  LTargetSession := nil;
  LSessions := FSessionMgr.GetSessionListSnapshot;
  try
    for LSession in LSessions do
      if LSession.SessionId = ASessionId then begin
        LTargetSession := LSession;
        Break;
      end;
  finally LSessions.Free; end;

  if not Assigned(LTargetSession) or (LTargetSession.DiffsPath = '') then Exit;

  LArray := TJsonArray.Create;
  LList := TList<TJsonObject>.Create;
  try
    if TDirectory.Exists(LTargetSession.DiffsPath) then
    begin
      LFiles := TDirectory.GetFiles(LTargetSession.DiffsPath, '*.json', TSearchOption.soTopDirectoryOnly);
      for LPath in LFiles do
      begin
        try
          LJsonText := TFile.ReadAllText(LPath, TEncoding.UTF8);
          LObj := TJsonObject.Parse(LJsonText) as TJsonObject;
          if Assigned(LObj) then LList.Add(LObj);
        except
        end;
      end;
      
      LList.Sort(TComparer<TJsonObject>.Construct(
        function(const Left, Right: TJsonObject): Integer
        begin
          Result := CompareText(Right.S['timestamp'], Left.S['timestamp']);
        end));
        
      for I := 0 to LList.Count - 1 do
      begin
        LItem := LArray.AddObject;
        LItem.Assign(LList[I]);
        // Only need metadata, not content for the history list to save memory/speed
        LItem.Remove('oldContent');
        LItem.Remove('newContent');
      end;
    end;
    
    System.Classes.TThread.Queue(nil, TThreadProcedure(procedure
    var
      LBase64: string;
    begin
      LBase64 := TNetEncoding.Base64.Encode(LArray.ToJSON(False)).Replace(#13, '').Replace(#10, '');
      FWebBrowser.EvaluateJavaScript('window.ACP.updateFileHistoryBase64("' + LBase64 + '")');
    end));
  finally
    for I := 0 to LList.Count - 1 do LList[I].Free;
    LList.Free;
    LArray.Free;
  end;
end;

end.