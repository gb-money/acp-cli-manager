unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.WebBrowser, uAgent, uGeminiAgent, uACPAgent,
  uSessionManager, uAgentControl, uDebugRPC, JsonDataObjects, uUIControl, System.SyncObjs, uAgentTypes, uACPClient;

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
    FAgents: TDictionary<TAgentType, TAgent>;
    FInitialized: Boolean;
    
    procedure DoOpenExplorer(Sender: TObject);
    procedure DoOpenFileViewer(Sender: TObject; const APath: string);
    procedure DoOpenDiffViewer(Sender: TObject; const ASessionId, APath, AHashId: string);
    procedure DoOpenFileDialogRequested(Sender: TObject);
    procedure DoUIReady(Sender: TObject);
    procedure DoRawDataForDebug(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
    function GetOrCreateAgent(AType: TAgentType): TAgent;
  public
  end;

var
  S: TS;

implementation

{$R *.fmx}

uses
  System.IOUtils, FMX.Dialogs, uFileExplorer, Winapi.ShellAPI, uFileViewer, uDiffViewer;

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
  case Self of
    atGemini: Result := 'Gemini';
    atClaude: Result := 'Claude';
    atCodex: Result := 'Codex';
  else Result := '';
  end;
end;

{ TS }

procedure TS.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FSessionMgr := TSessionManager.Create;
  FAgents := TDictionary<TAgentType, TAgent>.Create;
  
  // UI Control handles global UI actions and Search
  FUIControl := TUIControl.Create(WebBrowserMain, FSessionMgr.BaseConfigPath);
  FUIControl.OnOpenExplorer := DoOpenExplorer;
  FUIControl.OnOpenFileViewer := DoOpenFileViewer;
  FUIControl.OnOpenDiffViewer := DoOpenDiffViewer;
  FUIControl.OnOpenFileDialog := DoOpenFileDialogRequested;
  FUIControl.OnUIReady := DoUIReady;

  // Agent Control handles conversation UI logic
  FAgentControl := TAgentControl.Create(WebBrowserMain, FSessionMgr);
  FAgentControl.OnRawData := DoRawDataForDebug;

  // Register Agents
  FAgentControl.RegisterAgent(atGemini, GetOrCreateAgent(atGemini));
  FAgentControl.LoadAllSessions;

  Self.WindowState := TWindowState.wsMaximized;
end;

function TS.GetOrCreateAgent(AType: TAgentType): TAgent;
var LAgent: TAgent; LGemini: TGeminiAgent;
begin
  if not FAgents.TryGetValue(AType, LAgent) then begin
    if AType = atGemini then begin
      LGemini := TGeminiAgent.Create(Self);
      LGemini.AgentType := atGemini;
      FAgents.Add(atGemini, LGemini);
      Result := LGemini;
    end
    else Result := nil;
  end
  else Result := LAgent;
end;

procedure TS.DoUIReady(Sender: TObject);
begin
  if Assigned(FAgentControl) then
    FAgentControl.UpdateSessionList;
end;

procedure TS.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if URL.IsEmpty or URL.ToLower.Contains('index.html') or URL.ToLower.StartsWith('about:') or URL.ToLower.StartsWith('javascript:') then Exit;

  // Dispatch to controllers
  if Assigned(FUIControl) and FUIControl.HandleRequest(URL) then Exit;
  if Assigned(FAgentControl) and FAgentControl.HandleRequest(URL) then Exit;

  // External Links
  ShellExecute(0, 'open', PChar(URL), nil, nil, SW_SHOWNORMAL);
  WebBrowserMain.Stop;
end;

procedure TS.DoOpenExplorer(Sender: TObject);
var LActive: TSessionInfo; LPath: string;
begin
  if not Assigned(frmFileExplorer) then frmFileExplorer := TfrmFileExplorer.Create(Application);
  LPath := ''; LActive := FSessionMgr.ActiveSession;
  if Assigned(LActive) and (LActive.Cwd <> '') then LPath := LActive.Cwd;
  if LPath = '' then LPath := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\'));
  if LPath <> '' then frmFileExplorer.Explore(LPath);
  frmFileExplorer.Show;
end;

procedure TS.DoOpenFileViewer(Sender: TObject; const APath: string);
var LFullPath: string; LActive: TSessionInfo;
begin
  LFullPath := APath;
  if not TPath.IsPathRooted(LFullPath) then begin
    LActive := FSessionMgr.ActiveSession;
    if Assigned(LActive) and (LActive.Cwd <> '') then LFullPath := TPath.Combine(LActive.Cwd, APath);
  end;
  if not Assigned(frmFileViewer) then frmFileViewer := TfrmFileViewer.Create(Application);
  frmFileViewer.ViewFile(LFullPath);
  frmFileViewer.Show;
end;

procedure TS.DoOpenDiffViewer(Sender: TObject; const ASessionId, APath, AHashId: string);
begin
  if not Assigned(frmDiffViewer) then frmDiffViewer := TfrmDiffViewer.Create(Application);
  frmDiffViewer.ViewDiffSession(FSessionMgr, ASessionId, APath, AHashId);
  frmDiffViewer.Show;
end;

procedure TS.DoOpenFileDialogRequested(Sender: TObject);
begin
  if Assigned(FAgentControl) then
    FAgentControl.HandleOpenFileDialog(nil);
end;

procedure TS.DoRawDataForDebug(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
begin
  if Assigned(frmDebugRPC) then begin
    var LDirStr: string;
    case Direction of
      rdIncoming: LDirStr := 'IN'; rdOutgoing: LDirStr := 'OUT';
    else LDirStr := 'SYS';
    end;
    TThread.Queue(nil, TThreadProcedure(procedure begin frmDebugRPC.AddLog(LDirStr, RawText); end));
  end;
end;

procedure TS.FormShow(Sender: TObject);
var LHtmlPath: string;
begin
  if not FInitialized then begin
    FInitialized := True;
    FSessionMgr.SelectSession(nil);
    LHtmlPath := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'assets'), 'index.html');
    if TFile.Exists(LHtmlPath) then WebBrowserMain.Navigate('file://' + LHtmlPath);
    if Assigned(frmDebugRPC) then frmDebugRPC.Show;
  end;
end;

procedure TS.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  if Assigned(WebBrowserMain) and WebBrowserMain.Visible then WebBrowserMain.SetFocus;
end;

procedure TS.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
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
