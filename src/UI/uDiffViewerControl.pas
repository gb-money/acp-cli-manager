unit uDiffViewerControl;

interface

uses
  System.SysUtils, System.Classes, System.Types, FMX.WebBrowser, System.IOUtils, System.NetEncoding,
  JsonDataObjects, uACPAgent, uSessionManager, uWebACPCommandHandler, System.Generics.Collections, 
  System.Generics.Defaults, uAgentTypes, uDiffService;

type
  TDiffViewerControl = class
  private
    FWebBrowser: TWebBrowser;
    FSessionMgr: TSessionManager;
    FCommandHandler: TWebACPCommandHandler;
    FDiffService: TDiffService;
    
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleReady(const Params: TDictionary<string, string>);
    procedure HandleSelectSession(const Params: TDictionary<string, string>);
    procedure HandleLoadDiff(const Params: TDictionary<string, string>);
    procedure HandleRollbackFile(const Params: TDictionary<string, string>);
    procedure HandlePartialRollback(const Params: TDictionary<string, string>);
    
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
  FDiffService := TDiffService.Create(FSessionMgr);
  FCommandHandler := TWebACPCommandHandler.Create;
  FCommandHandler.OnCommand := HandleInternalCommand;
end;

destructor TDiffViewerControl.Destroy;
begin
  FCommandHandler.Free;
  FDiffService.Free;
  inherited;
end;

function TDiffViewerControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := FCommandHandler.HandleUrl(AUrl, 'diff-action://');
end;

procedure TDiffViewerControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'ready' then HandleReady(Params)
  else if Action = 'select-session' then HandleSelectSession(Params)
  else if Action = 'load-diff' then HandleLoadDiff(Params)
  else if Action = 'rollback-file' then HandleRollbackFile(Params)
  else if Action = 'partial-rollback' then HandlePartialRollback(Params);
end;

procedure TDiffViewerControl.InitDiffSession(const ASessionId, ATargetPath, AHashId: string);
begin
  FDiffService.SelectSession(ASessionId,
    procedure(ASession: TSessionInfo)
    begin
      System.Classes.TThread.Queue(nil, procedure
      begin
        FWebBrowser.EvaluateJavaScript('window.ACP.targetPath = "' + ATargetPath.Replace('\', '\\').Replace('"', '\"') + '"');
        FWebBrowser.EvaluateJavaScript('window.ACP.targetHashId = "' + AHashId + '"');
        FWebBrowser.EvaluateJavaScript('window.ACP.selectSession("' + ASession.SessionId + '")');
      end);
    end,
    nil // Silently fail on init if session not found
  );
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
    FDiffService.SelectSession(LSessionId,
      procedure(ASession: TSessionInfo)
      begin
        SendSessionList; 
        SendFileHistory(ASession.SessionId);
      end,
      procedure(AError: string)
      begin
        System.Classes.TThread.Queue(nil, procedure
        begin
          FWebBrowser.EvaluateJavaScript('window.ACP.showModal("error", "Session Error", "' + AError + '")');
        end);
      end);
  end;
end;

procedure TDiffViewerControl.HandleLoadDiff(const Params: TDictionary<string, string>);
var
  LSessionId, LHashId, LCompareStr: string;
  LCompareToLatest: Boolean;
begin
  if Params.TryGetValue('sessionId', LSessionId) and Params.TryGetValue('hashId', LHashId) then
  begin
    LCompareToLatest := Params.TryGetValue('compareToLatest', LCompareStr) and (LCompareStr = 'true');
    
    FDiffService.LoadDiffDetail(LSessionId, LHashId, LCompareToLatest,
      procedure(AObj: TJsonObject)
      var
        LOldContent, LNewContent, LFileName, LFilePath, LHash: string;
      begin
        try
          LOldContent := AObj.S['oldContent'];
          LNewContent := AObj.S['newContent'];
          LFileName := TPath.GetFileName(AObj.S['path']);
          LFilePath := AObj.S['path'];
          LHash := AObj.S['id'];

          System.Classes.TThread.Queue(nil, procedure
          var
            LScript: string;
            LOld64, LNew64: string;
          begin
            LOld64 := TNetEncoding.Base64.Encode(LOldContent).Replace(#13, '').Replace(#10, '');
            LNew64 := TNetEncoding.Base64.Encode(LNewContent).Replace(#13, '').Replace(#10, '');
            
            LScript := Format('var o=decodeURIComponent(escape(window.atob("%s"))); var n=decodeURIComponent(escape(window.atob("%s"))); window.ACP.loadDiffFromData("%s", "%s", o, n, "%s");',
              [LOld64, LNew64, LFileName, LFilePath.Replace('\', '\\').Replace('"', '\"'), LHash]);
            FWebBrowser.EvaluateJavaScript(LScript);
          end);
        finally
          AObj.Free;
        end;
      end,
      procedure(AError: string)
      begin
        System.Classes.TThread.Queue(nil, procedure
        begin
          FWebBrowser.EvaluateJavaScript('window.ACP.showModal("error", "Load Error", "' + AError + '")');
        end);
      end);
  end;
end;

procedure TDiffViewerControl.HandleRollbackFile(const Params: TDictionary<string, string>);
var
  LSessionId, LHashId: string;
begin
  if Params.TryGetValue('sessionId', LSessionId) and Params.TryGetValue('hashId', LHashId) then
  begin
    FDiffService.Rollback(LSessionId, LHashId,
      procedure()
      begin
        SendFileHistory(LSessionId);
      end,
      procedure(AError: string)
      begin
        System.Classes.TThread.Queue(nil, procedure
        begin
          FWebBrowser.EvaluateJavaScript('window.ACP.showModal("error", "Rollback Failed", "' + AError + '")');
        end);
      end);
  end;
end;

procedure TDiffViewerControl.HandlePartialRollback(const Params: TDictionary<string, string>);
var
  LSessionId, LHashId, LBlockIdxStr: string;
begin
  if Params.TryGetValue('sessionId', LSessionId) and Params.TryGetValue('hashId', LHashId) and 
     Params.TryGetValue('blockIndex', LBlockIdxStr) then
  begin
    FDiffService.PartialRollback(LSessionId, LHashId, StrToIntDef(LBlockIdxStr, -1),
      procedure()
      begin
        SendFileHistory(LSessionId);
      end,
      procedure(AError: string)
      begin
        System.Classes.TThread.Queue(nil, procedure
        begin
          FWebBrowser.EvaluateJavaScript('window.ACP.showModal("error", "Partial Rollback Failed", "' + AError + '")');
        end);
      end);
  end;
end;

procedure TDiffViewerControl.SendSessionList;
begin
  FDiffService.LoadAllSessions(
    procedure(ASessions: TList<TSessionInfo>)
    var
      LArray: TJsonArray;
      LObj: TJsonObject;
      LSession: TSessionInfo;
    begin
      LArray := TJsonArray.Create;
      try
        for LSession in ASessions do
        begin
          LObj := LArray.AddObject;
          LObj.S['id'] := LSession.SessionId;
          LObj.S['name'] := LSession.Name;
          LObj.S['workspace'] := TPath.GetFileName(ExcludeTrailingPathDelimiter(LSession.Cwd)); 
          LObj.B['active'] := False;
          LObj.B['online'] := True;
        end;
        
        System.Classes.TThread.Queue(nil, procedure
        begin
          FWebBrowser.EvaluateJavaScript('window.ACP.updateSessionList(' + LArray.ToJSON(False) + ')');
        end);
      finally
        LArray.Free;
        ASessions.Free;
      end;
    end);
end;

procedure TDiffViewerControl.SendFileHistory(const ASessionId: string);
begin
  FDiffService.LoadDiffsFromSession(ASessionId,
    procedure(AArray: TJsonArray)
    begin
      System.Classes.TThread.Queue(nil, procedure
      var
        LBase64: string;
      begin
        try
          LBase64 := TNetEncoding.Base64.Encode(AArray.ToJSON(False)).Replace(#13, '').Replace(#10, '');
          FWebBrowser.EvaluateJavaScript('window.ACP.updateFileHistoryBase64("' + LBase64 + '")');
        finally
          AArray.Free;
        end;
      end);
    end,
    procedure(AError: string)
    begin
      System.Classes.TThread.Queue(nil, procedure
      begin
        FWebBrowser.EvaluateJavaScript('window.ACP.updateFileHistoryBase64("")'); // Clear history on error
      end);
    end);
end;

end.