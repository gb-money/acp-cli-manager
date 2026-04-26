unit uFileService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Types, JsonDataObjects;

type
  TFileService = class
  public
    // 파일 내용 로드 (성공 시 파일명, 경로, JSON 인코딩된 내용을 콜백으로 전달)
    procedure LoadFile(const APath: string; 
      OnSuccess: TProc<string, string, string>; 
      OnError: TProc<string>);

    // 디렉토리 목록 조회 (성공 시 현재 경로와 JSON 목록을 콜백으로 전달)
    procedure GetDirectoryList(const APath: string;
      OnSuccess: TProc<string, TJsonObject>;
      OnError: TProc<string>);

    // 파일 프리뷰 내용 조회 (성공 시 내용과 확장자를 콜백으로 전달)
    procedure GetFilePreview(const APath: string;
      OnSuccess: TProc<string, string>;
      OnError: TProc<string>);
  end;

implementation

{ TFileService }

function FormatSize(ASize: Int64): string;
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

procedure TFileService.LoadFile(const APath: string; 
  OnSuccess: TProc<string, string, string>; 
  OnError: TProc<string>);
var
  LContent, LFileName, LJsonContent: string;
begin
  if not TFile.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('File not found: ' + APath);
    Exit;
  end;

  try
    LFileName := TPath.GetFileName(APath);
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    
    // JSON 문자열로 안전하게 변환 (이스케이프 처리)
    LJsonContent := TJsonObject.Parse('"' + LContent.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '"').ToJSON;

    if Assigned(OnSuccess) then
      OnSuccess(LFileName, APath, LJsonContent);
  except
    on E: Exception do
    begin
      if Assigned(OnError) then OnError('Failed to read file: ' + E.Message);
    end;
  end;
end;

procedure TFileService.GetDirectoryList(const APath: string;
  OnSuccess: TProc<string, TJsonObject>;
  OnError: TProc<string>);
var
  LRootObj, LFileObj: TJsonObject;
  LFileArray: TJsonArray;
  LDirs, LFiles: TStringDynArray;
  S: string;
  LSize: Int64;
  LTime: TDateTime;
begin
  if not TDirectory.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('Directory not found: ' + APath);
    Exit;
  end;

  LRootObj := TJsonObject.Create;
  try
    LRootObj.S['currentPath'] := APath;
    LFileArray := LRootObj.A['files'];
    
    try
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
        try
          LSize := TFile.GetSize(S);
          LFileObj.S['size'] := FormatSize(LSize);
        except
          LFileObj.S['size'] := '0 B';
        end;
      end;

      if Assigned(OnSuccess) then OnSuccess(APath, LRootObj) else LRootObj.Free;
    except
      on E: Exception do
      begin
        LRootObj.Free;
        if Assigned(OnError) then OnError('Failed to list directory: ' + E.Message);
      end;
    end;
  finally
    // LRootObj is managed by OnSuccess or freed on error
  end;
end;

procedure TFileService.GetFilePreview(const APath: string;
  OnSuccess: TProc<string, string>;
  OnError: TProc<string>);
var
  LContent, LExt: string;
begin
  if not TFile.Exists(APath) then
  begin
    if Assigned(OnError) then OnError('File not found for preview');
    Exit;
  end;

  try
    LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    LExt := TPath.GetExtension(APath).Replace('.', '').ToLower;
    if Assigned(OnSuccess) then OnSuccess(LContent, LExt);
  except
    on E: Exception do
    begin
      if Assigned(OnError) then OnError('Preview failed: ' + E.Message);
    end;
  end;
end;

end.
