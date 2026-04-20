unit uUIControl;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uWebACPCommandHandler;

type
  TOpenExplorerEvent = procedure(Sender: TObject) of object;
  TOpenFileViewerEvent = procedure(Sender: TObject; const APath: string) of object;
  TOpenDiffViewerEvent = procedure(Sender: TObject; const ASessionId, APath, AHashId: string) of object;

  TUIControl = class
  private
    FCommandHandler: TWebACPCommandHandler;
    FOnOpenExplorer: TOpenExplorerEvent;
    FOnOpenFileViewer: TOpenFileViewerEvent;
    FOnOpenDiffViewer: TOpenDiffViewerEvent;
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleOpenExplorer(const Params: TDictionary<string, string>);
    procedure HandleOpenFileViewer(const Params: TDictionary<string, string>);
    procedure HandleOpenDiffViewer(const Params: TDictionary<string, string>);
  public
    constructor Create;
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    property OnOpenExplorer: TOpenExplorerEvent read FOnOpenExplorer write FOnOpenExplorer;
    property OnOpenFileViewer: TOpenFileViewerEvent read FOnOpenFileViewer write FOnOpenFileViewer;
    property OnOpenDiffViewer: TOpenDiffViewerEvent read FOnOpenDiffViewer write FOnOpenDiffViewer;
  end;

implementation

constructor TUIControl.Create;
begin
  FCommandHandler := TWebACPCommandHandler.Create;
  FCommandHandler.OnCommand := HandleInternalCommand;
end;

destructor TUIControl.Destroy;
begin
  FCommandHandler.Free;
  inherited;
end;

function TUIControl.HandleRequest(const AUrl: string): Boolean;
begin
  Result := FCommandHandler.HandleUrl(AUrl, 'ui-action://');
end;

procedure TUIControl.HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
begin
  if Action = 'open-explorer' then HandleOpenExplorer(Params)
  else if Action = 'open-file-viewer' then HandleOpenFileViewer(Params)
  else if Action = 'open-diff-viewer' then HandleOpenDiffViewer(Params);
end;

procedure TUIControl.HandleOpenExplorer(const Params: TDictionary<string, string>);
begin
  if Assigned(FOnOpenExplorer) then
    FOnOpenExplorer(Self);
end;

procedure TUIControl.HandleOpenFileViewer(const Params: TDictionary<string, string>);
var
  LPath: string;
begin
  if Params.TryGetValue('path', LPath) then
    if Assigned(FOnOpenFileViewer) then
      FOnOpenFileViewer(Self, LPath);
end;

procedure TUIControl.HandleOpenDiffViewer(const Params: TDictionary<string, string>);
var
  LSessionId, LPath, LHashId: string;
begin
  if Params.TryGetValue('sessionId', LSessionId) then
  begin
    Params.TryGetValue('path', LPath);     // Optional
    Params.TryGetValue('hashId', LHashId); // Optional
    if Assigned(FOnOpenDiffViewer) then
      FOnOpenDiffViewer(Self, LSessionId, LPath, LHashId);
  end;
end;

end.
