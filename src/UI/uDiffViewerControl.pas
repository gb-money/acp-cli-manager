unit uDiffViewerControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, System.IOUtils, JsonDataObjects;

type
  TDiffRow = record
    OldLine: string;
    NewLine: string;
    LineType: string; // 'added', 'removed', 'unchanged'
    Content: string;
  end;

  TDiffViewerControl = class
  private
    FWebBrowser: TWebBrowser;
  public
    constructor Create(AWebBrowser: TWebBrowser);
    procedure LoadDiff(const AFileName, APath: string; const ADiffData: TArray<TDiffRow>);
    function HandleRequest(const AUrl: string): Boolean;
  end;

implementation

{ TDiffViewerControl }

constructor TDiffViewerControl.Create(AWebBrowser: TWebBrowser);
begin
  FWebBrowser := AWebBrowser;
end;

function TDiffViewerControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := False;
end;

procedure TDiffViewerControl.LoadDiff(const AFileName, APath: string; const ADiffData: TArray<TDiffRow>);
var
  LRoot: TJsonArray;
  LRowObj: TJsonObject;
  LRow: TDiffRow;
begin
  LRoot := TJsonArray.Create;
  try
    for LRow in ADiffData do
    begin
      LRowObj := LRoot.AddObject;
      LRowObj.S['oldLine'] := LRow.OldLine;
      LRowObj.S['newLine'] := LRow.NewLine;
      LRowObj.S['type'] := LRow.LineType;
      LRowObj.S['content'] := LRow.Content;
    end;

    FWebBrowser.EvaluateJavaScript(
      Format('window.ACP_DIFF_VIEWER.loadDiff("%s", "%s", %s)', 
      [AFileName, APath.Replace('\', '/'), LRoot.ToJSON(False)])
    );
  finally
    LRoot.Free;
  end;
end;

end.