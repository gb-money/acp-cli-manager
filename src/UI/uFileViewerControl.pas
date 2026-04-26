unit uFileViewerControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, System.IOUtils, JsonDataObjects,
  uFileService;

type
  TFileViewerControl = class
  private
    FWebBrowser: TWebBrowser;
    FFileService: TFileService;
  public
    constructor Create(AWebBrowser: TWebBrowser);
    destructor Destroy; override;
    procedure LoadFile(const APath: string);
    function HandleRequest(const AUrl: string): Boolean;
  end;

implementation

{ TFileViewerControl }

constructor TFileViewerControl.Create(AWebBrowser: TWebBrowser);
begin
  FWebBrowser := AWebBrowser;
  FFileService := TFileService.Create;
end;

destructor TFileViewerControl.Destroy;
begin
  FFileService.Free;
  inherited;
end;

function TFileViewerControl.HandleRequest(const AUrl: string): Boolean;
begin
  // 현재 뷰어에서 JS -> Delphi로 보내는 커스텀 액션이 필요할 경우 여기에 추가
  Result := False;
end;

procedure TFileViewerControl.LoadFile(const APath: string);
begin
  FFileService.LoadFile(APath,
    procedure(AFileName, APath, AJsonContent: string)
    begin
      System.Classes.TThread.Queue(nil, procedure
      begin
        FWebBrowser.EvaluateJavaScript(
          Format('window.ACP_FILE_VIEWER.loadFile("%s", "%s", %s)', 
          [AFileName, APath.Replace('\', '/'), AJsonContent])
        );
      end);
    end,
    procedure(AError: string)
    begin
      // Handle error (e.g. show in UI via acp.shared.js)
    end
  );
end;

end.