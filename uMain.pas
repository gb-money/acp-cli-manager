unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.WebBrowser,
  System.IOUtils, uSessionManager, uUIControl, uAgentControl, uACPAgent,
  uAgentTypes, JsonDataObjects, System.Generics.Collections, uGeminiAgent;

type
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
    FAgents: TDictionary<TAgentType, TACPAgent>;
    FInitialized: Boolean;

    procedure DoOpenExplorer(Sender: TObject);
    procedure DoOpenFileViewer(Sender: TObject; const APath: string);
    procedure DoOpenDiffViewer(Sender: TObject; const ASessionId, APath, AHashId: string);
    procedure DoOpenFileDialogRequested(Sender: TObject);
    procedure DoUIReady(Sender: TObject);
    procedure DoRawDataForDebug(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
    function GetOrCreateAgent(AType: TAgentType): TACPAgent;
  public
  end;

var
  S: TS;

implementation

uses
  uDebugRPC, uFileExplorer, uFileViewer, uDiffViewer;

{$R *.fmx}

function GetMimeType(const AExtension: string): string;
begin
  var Ext := AExtension.ToLower;
  if Ext = '.html' then Result := 'text/html'
  else if Ext = '.css' then Result := 'text/css'
  else if Ext = '.js' then Result := 'application/javascript'
  else if Ext = '.png' then Result := 'image/png'
  else if Ext = '.jpg' then Result := 'image/jpeg'
  else if Ext = '.svg' then Result := 'image/svg+xml'
  else Result := '';
end;

{ TS }

procedure TS.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FSessionMgr := TSessionManager.Create;
  FAgents := TDictionary<TAgentType, TACPAgent>.Create;

  FUIControl := TUIControl.Create(WebBrowserMain, FSessionMgr.BaseConfigPath);
  FUIControl.OnOpenExplorer := DoOpenExplorer;
  FUIControl.OnOpenFileViewer := DoOpenFileViewer;
  FUIControl.OnOpenDiffViewer := DoOpenDiffViewer;
  FUIControl.OnOpenFileDialog := DoOpenFileDialogRequested;
  FUIControl.OnUIReady := DoUIReady;

  FAgentControl := TAgentControl.Create(WebBrowserMain, FSessionMgr);
  FAgentControl.OnRawData := DoRawDataForDebug;

  FAgentControl.RegisterAgent(atGemini, GetOrCreateAgent(atGemini));
  FAgentControl.LoadAllSessions;

  Self.WindowState := TWindowState.wsMaximized;
end;

function TS.GetOrCreateAgent(AType: TAgentType): TACPAgent;
var LAgent: TACPAgent; LGemini: TGeminiAgent;
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
  else
    Result := LAgent;
end;

procedure TS.DoOpenExplorer(Sender: TObject);
var
  LPath: string;
begin
  if not Assigned(frmFileExplorer) then
    frmFileExplorer := TfrmFileExplorer.Create(Application);

  LPath := '';
  if Assigned(FSessionMgr.ActiveSession) then
    LPath := FSessionMgr.ActiveSession.Cwd;

  if LPath = '' then
    LPath := FSessionMgr.BaseConfigPath;

  frmFileExplorer.Explore(LPath);
  frmFileExplorer.Show;
end;

procedure TS.DoOpenFileViewer(Sender: TObject; const APath: string);
begin
  if not Assigned(frmFileViewer) then
    frmFileViewer := TfrmFileViewer.Create(Application);

  frmFileViewer.ViewFile(APath);
  frmFileViewer.Show;
end;

procedure TS.DoOpenDiffViewer(Sender: TObject; const ASessionId, APath, AHashId: string);
begin
  if not Assigned(frmDiffViewer) then
    frmDiffViewer := TfrmDiffViewer.Create(Application);

  frmDiffViewer.ViewDiffSession(FSessionMgr, ASessionId, APath, AHashId);
  frmDiffViewer.Show;
end;

procedure TS.DoOpenFileDialogRequested(Sender: TObject);
begin
  if Assigned(FAgentControl) then
    FAgentControl.HandleOpenFileDialog(nil);
end;

procedure TS.DoUIReady(Sender: TObject);
begin
  if not FInitialized then
  begin
    FInitialized := True;
    if Assigned(FAgentControl) then
      FAgentControl.UpdateSessionList;
  end;
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
  // frmDebugRPC.UpdateRawData(Direction, ASessionId, RawText);
end;

procedure TS.FormShow(Sender: TObject);
var
  LHtmlPath: string;
begin
  if not Assigned(frmDebugRPC) then
    frmDebugRPC := TfrmDebugRPC.Create(Application);
  frmDebugRPC.Show;

  LHtmlPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'src/UI/assets/index.html');
  if not TFile.Exists(LHtmlPath) then
  begin
    LHtmlPath := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '../../src/UI/assets/index.html'));
  end;

  if TFile.Exists(LHtmlPath) then
    WebBrowserMain.Navigate('file://' + LHtmlPath)
  else
    ShowMessage('index.html not found: ' + LHtmlPath);
end;

procedure TS.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  if Assigned(WebBrowserMain) and WebBrowserMain.Visible then WebBrowserMain.SetFocus;
end;

procedure TS.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if URL.IsEmpty or URL.ToLower.Contains('index.html') or URL.ToLower.StartsWith('about:') or URL.ToLower.StartsWith('javascript:') then Exit;

  if FAgentControl.HandleRequest(URL) then Exit;
  if FUIControl.HandleRequest(URL) then Exit;
end;

procedure TS.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
end;

procedure TS.FormClose(Sender: TObject; var Action: TCloseAction);
var Agent: TACPAgent;
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
