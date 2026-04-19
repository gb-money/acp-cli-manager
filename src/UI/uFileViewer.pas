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

procedure TfrmFileViewer.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // 창을 닫을 때 메모리 해제 및 액션 설정 (Free를 할지 Hide를 할지 선택 가능)
  // 여기서는 동적 생성 시나리오를 위해 Free로 설정
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
  if FViewerCtrl.HandleRequest(URL) then
    // 커스텀 액션인 경우 내비게이션 중단
    ;
end;

end.