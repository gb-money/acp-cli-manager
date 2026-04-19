unit uFileViewer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.WebBrowser,
  uFileViewerControl;

type
  TfrmFileViewer = class(TForm)
    WebBrowserMain: TWebBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
    procedure WebBrowserMainDidFinishLoad(ASender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
  private
    FViewerCtrl: TFileViewerControl;
    FInitialized: Boolean;
    FPendingFilePath: string;
  public
    procedure ViewFile(const APath: string);
  end;

var
  frmFileViewer: TfrmFileViewer;

implementation

{$R *.fmx}

uses
  System.IOUtils;

procedure TfrmFileViewer.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FViewerCtrl := TFileViewerControl.Create(WebBrowserMain);
end;

procedure TfrmFileViewer.FormDestroy(Sender: TObject);
begin
  FViewerCtrl.Free;
  frmFileViewer := nil;
end;

procedure TfrmFileViewer.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caFree;
end;

procedure TfrmFileViewer.FormShow(Sender: TObject);
var
  LHtmlPath: string;
begin
  if not FInitialized then
  begin
    FInitialized := True;
    LHtmlPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'file_viewer.html');
    if TFile.Exists(LHtmlPath) then
      WebBrowserMain.Navigate('file://' + LHtmlPath);
  end;
end;

procedure TfrmFileViewer.ViewFile(const APath: string);
begin
  if not FInitialized then
    FPendingFilePath := APath
  else
    FViewerCtrl.LoadFile(APath);
end;

procedure TfrmFileViewer.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  if FPendingFilePath <> '' then
  begin
    FViewerCtrl.LoadFile(FPendingFilePath);
    FPendingFilePath := '';
  end;
end;

procedure TfrmFileViewer.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if URL.StartsWith('file://', True) then Exit;
  
  if FViewerCtrl.HandleRequest(URL) then
    Exit;

  // Block any external navigation (http, https, etc.)
  WebBrowserMain.Stop;
end;

end.
