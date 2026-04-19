unit uDiffViewer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.WebBrowser,
  uDiffViewerControl;

type
  TfrmDiffViewer = class(TForm)
    WebBrowserMain: TWebBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
    procedure WebBrowserMainDidFinishLoad(ASender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FDiffCtrl: TDiffViewerControl;
    FInitialized: Boolean;
    FPendingFileName: string;
    FPendingPath: string;
    FPendingDiffData: TArray<TDiffRow>;
  public
    procedure ViewDiff(const AFileName, APath: string; const ADiffData: TArray<TDiffRow>);
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
  FDiffCtrl := TDiffViewerControl.Create(WebBrowserMain);
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
    LHtmlPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'diff_viewer.html');
    if TFile.Exists(LHtmlPath) then
      WebBrowserMain.Navigate('file://' + LHtmlPath);
  end;
end;

procedure TfrmDiffViewer.ViewDiff(const AFileName, APath: string; const ADiffData: TArray<TDiffRow>);
begin
  if not FInitialized then
  begin
    FPendingFileName := AFileName;
    FPendingPath := APath;
    FPendingDiffData := ADiffData;
  end
  else
    FDiffCtrl.LoadDiff(AFileName, APath, ADiffData);
end;

procedure TfrmDiffViewer.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  if Length(FPendingDiffData) > 0 then
  begin
    FDiffCtrl.LoadDiff(FPendingFileName, FPendingPath, FPendingDiffData);
    SetLength(FPendingDiffData, 0);
  end;
end;

procedure TfrmDiffViewer.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if FDiffCtrl.HandleRequest(URL) then
    ;
end;

end.