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
    procedure FormDestroy(Sender: TObject);
  private
    FExplorerCtrl: TExplorerControl;
    FInitialized: Boolean;
    FInitialPath: string;
    procedure DoViewFile(Sender: TObject; const APath: string);
  public
    procedure Explore(const APath: string);
  end;

var
  frmFileExplorer: TfrmFileExplorer;

implementation

{$R *.fmx}

uses
  System.IOUtils, uFileViewer, Winapi.ShellAPI, Winapi.Windows;

procedure TfrmFileExplorer.FormCreate(Sender: TObject);
begin
  FInitialized := False;
  FExplorerCtrl := TExplorerControl.Create(WebBrowserMain);
  FExplorerCtrl.OnViewFile := DoViewFile;
end;

procedure TfrmFileExplorer.DoViewFile(Sender: TObject; const APath: string);
begin
  if not Assigned(frmFileViewer) then
    frmFileViewer := TfrmFileViewer.Create(Application);
    
  frmFileViewer.ViewFile(APath);
  frmFileViewer.Show;
end;

procedure TfrmFileExplorer.FormDestroy(Sender: TObject);
begin
  FExplorerCtrl.Free;
  frmFileExplorer := nil;
end;

procedure TfrmFileExplorer.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caFree;
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
  // 1. Filter out internal browser URLs and javascript
  if URL.IsEmpty or URL.ToLower.StartsWith('about:') or URL.ToLower.StartsWith('javascript:') then
    Exit;

  // 2. Allow initial UI file
  if URL.ToLower.Contains('explorer.html') then Exit;

  // 3. Handle Custom Actions
  if FExplorerCtrl.HandleRequest(URL) then Exit;

  // 4. Open everything else (external links) in system default app
  ShellExecute(0, 'open', PChar(URL), nil, nil, SW_SHOWNORMAL);

  // 5. Block internal navigation
  WebBrowserMain.Stop;
end;

end.
