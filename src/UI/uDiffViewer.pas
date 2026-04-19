unit uDiffViewer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.WebBrowser,
  uDiffViewerControl, uSessionManager;

type
  TfrmDiffViewer = class(TForm)
    WebBrowserMain: TWebBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
    procedure WebBrowserMainDidFinishLoad(ASender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
  private
    FDiffCtrl: TDiffViewerControl;
    FInitialized: Boolean;
    FPendingSessionId: string;
    FPendingTargetPath: string;
    FPendingHashId: string;
  public
    procedure ViewDiffSession(ASessionMgr: TSessionManager; const ASessionId, ATargetPath, AHashId: string);
  end;

var
  frmDiffViewer: TfrmDiffViewer;

implementation

{$R *.fmx}

uses
  System.IOUtils;

procedure TfrmDiffViewer.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FDiffCtrl := nil;
end;

procedure TfrmDiffViewer.FormDestroy(Sender: TObject);
begin
  if Assigned(FDiffCtrl) then FDiffCtrl.Free;
  frmDiffViewer := nil;
end;

procedure TfrmDiffViewer.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caFree;
end;

procedure TfrmDiffViewer.FormShow(Sender: TObject);
var
  LHtmlPath: string;
begin
  if not FInitialized then
  begin
    FInitialized := True;
    LHtmlPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'diff_view.html');
    if TFile.Exists(LHtmlPath) then
      WebBrowserMain.Navigate('file://' + LHtmlPath);
  end;
end;

procedure TfrmDiffViewer.ViewDiffSession(ASessionMgr: TSessionManager; const ASessionId, ATargetPath, AHashId: string);
begin
  if not Assigned(FDiffCtrl) then
    FDiffCtrl := TDiffViewerControl.Create(WebBrowserMain, ASessionMgr);

  if not FInitialized then
  begin
    FPendingSessionId := ASessionId;
    FPendingTargetPath := ATargetPath;
    FPendingHashId := AHashId;
  end
  else
    FDiffCtrl.InitDiffSession(ASessionId, ATargetPath, AHashId);
end;

procedure TfrmDiffViewer.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  if Assigned(FDiffCtrl) and (FPendingSessionId <> '') then
  begin
    FDiffCtrl.InitDiffSession(FPendingSessionId, FPendingTargetPath, FPendingHashId);
    FPendingSessionId := '';
    FPendingTargetPath := '';
    FPendingHashId := '';
  end;
end;

procedure TfrmDiffViewer.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if Assigned(FDiffCtrl) and FDiffCtrl.HandleRequest(URL) then
    ;
end;

end.
