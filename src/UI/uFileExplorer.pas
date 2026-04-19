unit uFileExplorer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.WebBrowser,
  uExplorerControl;

type
  TfrmFileExplorer = class(TForm)
    WebBrowserMain: TWebBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
    procedure WebBrowserMainDidFinishLoad(ASender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FExplorerCtrl: TExplorerControl;
    FInitialized: Boolean;
    FInitialPath: string;
  public
    procedure Explore(const APath: string);
  end;

var
  frmFileExplorer: TfrmFileExplorer;

implementation

{$R *.fmx}

uses
  System.IOUtils;

procedure TfrmFileExplorer.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FExplorerCtrl := TExplorerControl.Create(WebBrowserMain);
end;

procedure TfrmFileExplorer.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FExplorerCtrl.Free;
end;

procedure TfrmFileExplorer.FormShow(Sender: TObject);
var
  LHtmlPath: string;
begin
  if not FInitialized then
  begin
    FInitialized := True;
    LHtmlPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'explorer.html');
    if TFile.Exists(LHtmlPath) then
      WebBrowserMain.Navigate('file://' + LHtmlPath);
  end;
end;

procedure TfrmFileExplorer.Explore(const APath: string);
begin
  FInitialPath := APath;
  if FInitialized then
    FExplorerCtrl.UpdateFileList(APath);
end;

procedure TfrmFileExplorer.WebBrowserMainDidFinishLoad(ASender: TObject);
begin
  if FInitialPath <> '' then
  begin
    FExplorerCtrl.UpdateFileList(FInitialPath);
    FInitialPath := '';
  end;
end;

procedure TfrmFileExplorer.WebBrowserMainShouldStartLoadWithRequest(ASender: TObject; const URL: string);
begin
  if FExplorerCtrl.HandleRequest(URL) then
    // 브라우저 내부 내비게이션 중단 (커스텀 액션인 경우)
    ;
end;

end.