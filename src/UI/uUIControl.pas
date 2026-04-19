unit uUIControl;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uWebACPCommandHandler;

type
  TOpenExplorerEvent = procedure(Sender: TObject) of object;
  TOpenFileViewerEvent = procedure(Sender: TObject; const APath: string) of object;

  TUIControl = class
  private
    FCommandHandler: TWebACPCommandHandler;
    FOnOpenExplorer: TOpenExplorerEvent;
    FOnOpenFileViewer: TOpenFileViewerEvent;
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleOpenExplorer(const Params: TDictionary<string, string>);
    procedure HandleOpenFileViewer(const Params: TDictionary<string, string>);
  public
    constructor Create;
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    property OnOpenExplorer: TOpenExplorerEvent read FOnOpenExplorer write FOnOpenExplorer;
    property OnOpenFileViewer: TOpenFileViewerEvent read FOnOpenFileViewer write FOnOpenFileViewer;
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
  else if Action = 'open-file-viewer' then HandleOpenFileViewer(Params);
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

end.
