unit uUIControl;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uWebACPCommandHandler,
  uSearchService, FMX.WebBrowser, JsonDataObjects, System.NetEncoding;

type
  TOpenExplorerEvent = procedure(Sender: TObject) of object;
  TOpenFileViewerEvent = procedure(Sender: TObject; const APath: string) of object;
  TOpenDiffViewerEvent = procedure(Sender: TObject; const ASessionId, APath, AHashId: string) of object;
  TOpenFileDialogEvent = procedure(Sender: TObject) of object;
  TUIReadyEvent = procedure(Sender: TObject) of object;

  TUIControl = class
  private
    FWebBrowser: TWebBrowser;
    FCommandHandler: TWebACPCommandHandler;
    FSearchService: TSearchService;
    FOnOpenExplorer: TOpenExplorerEvent;
    FOnOpenFileViewer: TOpenFileViewerEvent;
    FOnOpenDiffViewer: TOpenDiffViewerEvent;
    FOnOpenFileDialog: TOpenFileDialogEvent;
    FOnUIReady: TUIReadyEvent;
    
    procedure DoSearchComplete(const AResults: TArray<TSearchSessionResult>);
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleOpenExplorer(const Params: TDictionary<string, string>);
    procedure HandleOpenFileViewer(const Params: TDictionary<string, string>);
    procedure HandleOpenDiffViewer(const Params: TDictionary<string, string>);
    procedure HandleOpenFileDialog(const Params: TDictionary<string, string>);
    procedure HandleUIReady(const Params: TDictionary<string, string>);
    procedure HandleSearchConversations(const Params: TDictionary<string, string>);
  public
    constructor Create(AWebBrowser: TWebBrowser; const ABaseConfigPath: string);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    property OnOpenExplorer: TOpenExplorerEvent read FOnOpenExplorer write FOnOpenExplorer;
    property OnOpenFileViewer: TOpenFileViewerEvent read FOnOpenFileViewer write FOnOpenFileViewer;
    property OnOpenDiffViewer: TOpenDiffViewerEvent read FOnOpenDiffViewer write FOnOpenDiffViewer;
    property OnOpenFileDialog: TOpenFileDialogEvent read FOnOpenFileDialog write FOnOpenFileDialog;
    property OnUIReady: TUIReadyEvent read FOnUIReady write FOnUIReady;
  end;

implementation

constructor TUIControl.Create(AWebBrowser: TWebBrowser; const ABaseConfigPath: string);
begin
  FWebBrowser := AWebBrowser;
  FCommandHandler := TWebACPCommandHandler.Create;
  FCommandHandler.OnCommand := HandleInternalCommand;

  FSearchService := TSearchService.Create;
  FSearchService.BaseConfigPath := ABaseConfigPath;
  FSearchService.OnSearchComplete := DoSearchComplete;
end;

destructor TUIControl.Destroy;
begin
  FSearchService.Free;
  FCommandHandler.Free;
  inherited;
end;

function TUIControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := FCommandHandler.HandleUrl(AUrl, 'ui-action://');
end;

procedure TUIControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'open-explorer' then HandleOpenExplorer(Params)
  else if Action = 'open-file-viewer' then HandleOpenFileViewer(Params)
  else if Action = 'open-diff-viewer' then HandleOpenDiffViewer(Params)
  else if Action = 'open-file-dialog' then HandleOpenFileDialog(Params)
  else if Action = 'ready' then HandleUIReady(Params)
  else if Action = 'search-conversations' then HandleSearchConversations(Params);
end;

procedure TUIControl.HandleOpenFileDialog(const Params: TDictionary<string, string>);
begin
  if Assigned(FOnOpenFileDialog) then FOnOpenFileDialog(Self);
end;

procedure TUIControl.HandleSearchConversations(const Params: TDictionary<string, string>);
var LQuery, LVal: string; LOpts: TSearchOptions;
begin
  if not Params.TryGetValue('query', LQuery) then Exit;
  LOpts.CaseSensitive := Params.TryGetValue('case', LVal) and SameText(LVal, 'true');
  LOpts.UseRegex := Params.TryGetValue('regex', LVal) and SameText(LVal, 'true');
  LOpts.IncludeActive := not (Params.TryGetValue('active', LVal) and SameText(LVal, 'false'));
  LOpts.IncludeInactive := not (Params.TryGetValue('inactive', LVal) and SameText(LVal, 'false'));
  LOpts.IncludeUser := not (Params.TryGetValue('user', LVal) and SameText(LVal, 'false'));
  LOpts.IncludeAgent := not (Params.TryGetValue('agent', LVal) and SameText(LVal, 'false'));
  LOpts.IncludeThought := Params.TryGetValue('thought', LVal) and SameText(LVal, 'true');
  LOpts.TargetSessionId := ''; Params.TryGetValue('targetSessionId', LOpts.TargetSessionId);
  FSearchService.Search(LQuery, LOpts);
end;

procedure TUIControl.DoSearchComplete(const AResults: TArray<TSearchSessionResult>);
var LRoot: TJsonArray; LSessObj, LMatchObj: TJsonObject; LMatchesArr: TJsonArray; LSess: TSearchSessionResult; LMatch: TSearchMatch; LJsonStr: string;
begin
  LRoot := TJsonArray.Create;
  try
    for LSess in AResults do begin
      LSessObj := LRoot.AddObject; LSessObj.S['sessionId'] := LSess.SessionId; LSessObj.S['agentType'] := LSess.AgentType;
      LSessObj.S['name'] := LSess.SessionName; LSessObj.S['workspace'] := LSess.Workspace; LMatchesArr := LSessObj.A['matches'];
      for LMatch in LSess.Matches do begin
        LMatchObj := LMatchesArr.AddObject; LMatchObj.S['timestamp'] := LMatch.Timestamp; LMatchObj.S['role'] := LMatch.Role;
        LMatchObj.S['snippet'] := LMatch.Snippet; LMatchObj.I['index'] := LMatch.MessageIndex;
      end;
    end;
    LJsonStr := LRoot.ToJSON(False);
    System.Classes.TThread.Queue(nil, procedure
      var LBase64: string;
      begin
        if Assigned(FWebBrowser) then begin
          LBase64 := TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes(LJsonStr)).Replace(#13, '').Replace(#10, '');
          FWebBrowser.EvaluateJavaScript('window.ACP.updateSearchResults("' + LBase64 + '")');
        end;
      end);
  finally LRoot.Free; end;
end;

procedure TUIControl.HandleOpenExplorer(const Params: TDictionary<string, string>);
begin
  if Assigned(FOnOpenExplorer) then FOnOpenExplorer(Self);
end;

procedure TUIControl.HandleUIReady(const Params: TDictionary<string, string>);
begin
  if Assigned(FOnUIReady) then FOnUIReady(Self);
end;

procedure TUIControl.HandleOpenFileViewer(const Params: TDictionary<string, string>);
var LPath: string; begin if Params.TryGetValue('path', LPath) then if Assigned(FOnOpenFileViewer) then FOnOpenFileViewer(Self, LPath); end;

procedure TUIControl.HandleOpenDiffViewer(const Params: TDictionary<string, string>);
var LSid, LPath, LHashId: string;
begin
  if Params.TryGetValue('sessionId', LSid) then begin
    Params.TryGetValue('path', LPath); Params.TryGetValue('hashId', LHashId);
    if Assigned(FOnOpenDiffViewer) then FOnOpenDiffViewer(Self, LSid, LPath, LHashId);
  end;
end;

end.
