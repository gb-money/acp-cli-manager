unit uExplorerControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, System.IOUtils, System.Types,
  System.NetEncoding, JsonDataObjects;

type
  TExplorerControl = class
  private
    FWebBrowser: TWebBrowser;
    FCurrentPath: string;
    procedure HandleOpen(const AParams: string);
    procedure HandleGetPreview(const AParams: string);
    procedure HandleViewExternal(const AParams: string);
    procedure HandleRefresh;
    function GetParamValue(const AParams, AKey: string): string;
    function FormatSize(ASize: Int64): string;
  public
    constructor Create(AWebBrowser: TWebBrowser);
    function HandleRequest(const AUrl: string): Boolean;
    procedure UpdateFileList(const APath: string);
    property CurrentPath: string read FCurrentPath write FCurrentPath;
  end;

implementation

{ TExplorerControl }

constructor TExplorerControl.Create(AWebBrowser: TWebBrowser);
begin
  FWebBrowser := AWebBrowser;
end;

function TExplorerControl.FormatSize(ASize: Int64): string;
const
  K = 1024;
  M = K * K;
  G = M * K;
begin
  if ASize >= G then Result := Format('%.2f GB', [ASize / G])
  else if ASize >= M then Result := Format('%.2f MB', [ASize / M])
  else if ASize >= K then Result := Format('%.2f KB', [ASize / K])
  else Result := Format('%d B', [ASize]);
end;

function TExplorerControl.GetParamValue(const AParams, AKey: string): string;
var
  LKeyWithEq: string;
  LStart: Integer;
  LValue: string;
begin
  Result := '';
  LKeyWithEq := AKey + '=';
  LStart := AParams.IndexOf(LKeyWithEq);
  if LStart >= 0 then
  begin
    LValue := AParams.Substring(LStart + LKeyWithEq.Length);
    if LValue.Contains('&') then
      LValue := LValue.Split(['&'])[0];
    Result := TNetEncoding.URL.Decode(LValue);
  end;
end;

function TExplorerControl.HandleRequest(const AUrl: string): Boolean;
const
  SCHEMA = 'explorer-action://';
var
  LRequest: string;
begin
  Result := False;
  if AUrl.ToLower.StartsWith(SCHEMA) then
  begin
    LRequest := AUrl.Substring(SCHEMA.Length);
    
    if LRequest.StartsWith('open') then
    begin
      HandleOpen(LRequest);
      Result := True;
    end
    else if LRequest.StartsWith('get-preview') then
    begin
      HandleGetPreview(LRequest);
      Result := True;
    end
    else if LRequest.StartsWith('view-external') then
    begin
      HandleViewExternal(LRequest);
      Result := True;
    end
    else if LRequest.StartsWith('refresh') then
    begin
      HandleRefresh;
      Result := True;
    end;
  end;
end;

procedure TExplorerControl.HandleOpen(const AParams: string);
var
  LPath: string;
  LIsDir: Boolean;
begin
  LPath := GetParamValue(AParams, 'path');
  LIsDir := SameText(GetParamValue(AParams, 'isDir'), 'true');

  if LIsDir then
    UpdateFileList(LPath);
end;

procedure TExplorerControl.HandleGetPreview(const AParams: string);
var
  LPath, LContent, LExt: string;
begin
  LPath := GetParamValue(AParams, 'path');
  if TFile.Exists(LPath) then
  begin
    try
      LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
      LExt := TPath.GetExtension(LPath).Replace('.', '').ToLower;
      // JS로 내용 전달 (Escape 처리 필요할 수 있음 - 여기서는 ToJSON 활용 권장하나 단순 텍스트로 전달)
      FWebBrowser.EvaluateJavaScript(Format('window.ACP_EXPLORER.setPreviewContent(%s, "%s")', 
        [TJsonObject.Parse('"' + LContent.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '"').ToJSON, LExt]));
    except
      on E: Exception do ;
    end;
  end;
end;

procedure TExplorerControl.HandleViewExternal(const AParams: string);
var
  LPath: string;
begin
  LPath := GetParamValue(AParams, 'path');
  // TODO: 외부 폼 오픈 로직 호출 (이벤트 등을 통해 처리)
end;

procedure TExplorerControl.HandleRefresh;
begin
  UpdateFileList(FCurrentPath);
end;

procedure TExplorerControl.UpdateFileList(const APath: string);
var
  LRootObj, LFileObj: TJsonObject;
  LFileArray: TJsonArray;
  LDirs, LFiles: TStringDynArray;
  S: string;
  LAttr: TFileAttributes;
  LSize: Int64;
  LTime: TDateTime;
begin
  if not TDirectory.Exists(APath) then Exit;
  FCurrentPath := APath;

  LRootObj := TJsonObject.Create;
  try
    LFileArray := LRootObj.A['files'];
    
    // 디렉토리 목록
    LDirs := TDirectory.GetDirectories(APath);
    for S in LDirs do
    begin
      LFileObj := LFileArray.AddObject;
      LFileObj.S['name'] := TPath.GetFileName(S);
      LFileObj.S['path'] := S;
      LFileObj.B['isDir'] := True;
      LFileObj.S['date'] := DateTimeToStr(TDirectory.GetLastWriteTime(S));
      LFileObj.S['type'] := 'File folder';
    end;

    // 파일 목록
    LFiles := TDirectory.GetFiles(APath);
    for S in LFiles do
    begin
      LFileObj := LFileArray.AddObject;
      LFileObj.S['name'] := TPath.GetFileName(S);
      LFileObj.S['path'] := S;
      LFileObj.B['isDir'] := False;
      
      LTime := TFile.GetLastWriteTime(S);
      LFileObj.S['date'] := DateTimeToStr(LTime);
      LFileObj.S['type'] := TPath.GetExtension(S).ToUpper.Replace('.', '') + ' File';
      
      // 파일 크기 계산
      try
        LSize := TFile.GetSize(S);
        LFileObj.S['size'] := FormatSize(LSize);
      except
        LFileObj.S['size'] := '0 B';
      end;
    end;

    FWebBrowser.EvaluateJavaScript(Format('window.ACP_EXPLORER.updateFileList(%s)', [LRootObj.ToJSON(False)]));
  finally
    LRootObj.Free;
  end;
end;

end.