unit uFileViewerControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, System.IOUtils, JsonDataObjects;

type
  TFileViewerControl = class
  private
    FWebBrowser: TWebBrowser;
  public
    constructor Create(AWebBrowser: TWebBrowser);
    procedure LoadFile(const APath: string);
    function HandleRequest(const AUrl: string): Boolean;
  end;

implementation

{ TFileViewerControl }

constructor TFileViewerControl.Create(AWebBrowser: TWebBrowser);
begin
  FWebBrowser := AWebBrowser;
end;

function TFileViewerControl.HandleRequest(const AUrl: string): Boolean;
begin
  // 현재 뷰어에서 JS -> Delphi로 보내는 커스텀 액션이 필요할 경우 여기에 추가
  Result := False;
end;

procedure TFileViewerControl.LoadFile(const APath: string);
var
  LContent, LFileName: string;
  LJsonContent: string;
begin
  if not TFile.Exists(APath) then Exit;

  try
    LFileName := TPath.GetFileName(APath);
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    
    // JSON 문자열로 안전하게 변환 (이스케이프 처리)
    LJsonContent := TJsonObject.Parse('"' + LContent.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '"').ToJSON;

    FWebBrowser.EvaluateJavaScript(
      Format('window.ACP_FILE_VIEWER.loadFile("%s", "%s", %s)', 
      [LFileName, APath.Replace('\', '/'), LJsonContent])
    );
  except
    on E: Exception do ;
  end;
end;

end.