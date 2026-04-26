unit uExplorerControl;

interface

uses
  System.SysUtils, System.Classes, FMX.WebBrowser, System.IOUtils, System.Types,
  System.NetEncoding, JsonDataObjects, uFileService, uWebACPCommandHandler,
  System.Generics.Collections;

type
  TViewFileEvent = procedure(Sender: TObject; const APath: string) of object;

  TExplorerControl = class
  private
    FWebBrowser: TWebBrowser;
    FCurrentPath: string;
    FOnViewFile: TViewFileEvent;
    FFileService: TFileService;
    FCommandHandler: TWebACPCommandHandler;

    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleOpen(const Params: TDictionary<string, string>);
    procedure HandleGetPreview(const Params: TDictionary<string, string>);
    procedure HandleViewExternal(const Params: TDictionary<string, string>);
    procedure HandleRefresh(const Params: TDictionary<string, string>);
    procedure HandleReady(const Params: TDictionary<string, string>);
  public
    constructor Create(AWebBrowser: TWebBrowser);
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    procedure UpdateFileList(const APath: string);
    
    property CurrentPath: string read FCurrentPath write FCurrentPath;
    property OnViewFile: TViewFileEvent read FOnViewFile write FOnViewFile;
  end;

implementation

{ TExplorerControl }

constructor TExplorerControl.Create(AWebBrowser: TWebBrowser);
begin
  FWebBrowser := AWebBrowser;
  FFileService := TFileService.Create;
  FCommandHandler := TWebACPCommandHandler.Create;
  FCommandHandler.OnCommand := HandleInternalCommand;
end;

destructor TExplorerControl.Destroy;
begin
  FCommandHandler.Free;
  FFileService.Free;
  inherited;
end;

function TExplorerControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := FCommandHandler.HandleUrl(AUrl, 'explorer-action://');
end;

procedure TExplorerControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'open' then HandleOpen(Params)
  else if Action = 'get-preview' then HandleGetPreview(Params)
  else if Action = 'view-external' then HandleViewExternal(Params)
  else if Action = 'refresh' then HandleRefresh(Params)
  else if Action = 'ready' then HandleReady(Params);
end;

procedure TExplorerControl.HandleReady(const Params: TDictionary<string, string>);
begin
  if FCurrentPath <> '' then
    UpdateFileList(FCurrentPath);
end;

procedure TExplorerControl.HandleOpen(const Params: TDictionary<string, string>);
var
  LPath, LIsDirStr: string;
  LIsDir: Boolean;
begin
  if Params.TryGetValue('path', LPath) then
  begin
    LIsDir := False;
    if Params.TryGetValue('isDir', LIsDirStr) then
      LIsDir := SameText(LIsDirStr, 'true');

    if LIsDir then
      UpdateFileList(LPath);
  end;
end;

procedure TExplorerControl.HandleGetPreview(const Params: TDictionary<string, string>);
var
  LPath: string;
begin
  if Params.TryGetValue('path', LPath) then
  begin
    FFileService.GetFilePreview(LPath,
      procedure(AContent, AExt: string)
      begin
        System.Classes.TThread.Queue(nil, procedure
        var
          LJsonContent: string;
        begin
          try
            // JSON 문자열로 안전하게 변환 (이스케이프 처리)
            LJsonContent := TJsonObject.Parse('"' + AContent.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '"').ToJSON;
            FWebBrowser.EvaluateJavaScript(Format('window.ACP_EXPLORER.setPreviewContent(%s, "%s")', 
              [LJsonContent, AExt]));
          except
            // Ignore format errors
          end;
        end);
      end,
      procedure(AError: string)
      begin
        // Silence or log preview error
      end
    );
  end;
end;

procedure TExplorerControl.HandleViewExternal(const Params: TDictionary<string, string>);
var
  LPath: string;
begin
  if Params.TryGetValue('path', LPath) then
  begin
    if Assigned(FOnViewFile) then
      FOnViewFile(Self, LPath);
  end;
end;

procedure TExplorerControl.HandleRefresh(const Params: TDictionary<string, string>);
begin
  if FCurrentPath <> '' then
    UpdateFileList(FCurrentPath);
end;

procedure TExplorerControl.UpdateFileList(const APath: string);
begin
  FCurrentPath := APath;
  
  FFileService.GetDirectoryList(APath,
    procedure(AReturnedPath: string; ADataObj: TJsonObject)
    begin
      System.Classes.TThread.Queue(nil, procedure
      begin
        try
          FWebBrowser.EvaluateJavaScript(Format('window.ACP_EXPLORER.updateFileList(%s)', [ADataObj.ToJSON(False)]));
        finally
          ADataObj.Free;
        end;
      end);
    end,
    procedure(AError: string)
    begin
      System.Classes.TThread.Queue(nil, procedure
      begin
        FWebBrowser.EvaluateJavaScript('if (window.ACP && window.ACP.showModal) window.ACP.showModal("error", "Explorer Error", "' + AError.Replace('\', '\\').Replace('"', '\"') + '")');
      end);
    end
  );
end;

end.
