unit uUIControl;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uWebACPCommandHandler;

type
  TOpenExplorerEvent = procedure(Sender: TObject) of object;

  TUIControl = class
  private
    FCommandHandler: TWebACPCommandHandler;
    FOnOpenExplorer: TOpenExplorerEvent;
    procedure HandleInternalCommand(Sender: TObject; const Action: string; const Params: TDictionary<string, string>);
    procedure HandleOpenExplorer(const Params: TDictionary<string, string>);
  public
    constructor Create;
    destructor Destroy; override;
    function HandleRequest(const AUrl: string): Boolean;
    property OnOpenExplorer: TOpenExplorerEvent read FOnOpenExplorer write FOnOpenExplorer;
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
  if Action = 'open-explorer' then HandleOpenExplorer(Params);
end;

procedure TUIControl.HandleOpenExplorer(const Params: TDictionary<string, string>);
begin
  if Assigned(FOnOpenExplorer) then
    FOnOpenExplorer(Self);
end;

end.
