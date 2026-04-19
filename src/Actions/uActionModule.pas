unit uActionModule;

interface

uses
  System.SysUtils, System.Classes, System.Actions, FMX.ActnList, FMX.Types, FMX.Menus;

type
  TdmActions = class(TDataModule)
    alAgent: TActionList;
    alFile: TActionList;
    alUI: TActionList;
    procedure DataModuleCreate(Sender: TObject);
  private
    { Private declarations }
    FactNewChat: TAction;
    FactNewGemini: TAction;
    procedure actNewChatExecute(Sender: TObject);
    procedure actNewGeminiExecute(Sender: TObject);
  public
    { Public declarations }
  end;

var
  dmActions: TdmActions;

implementation

uses
  uMain;

{%CLASSGROUP 'FMX.Controls.TControl'}

{$R *.dfm}

procedure TdmActions.DataModuleCreate(Sender: TObject);
begin
  FactNewChat := TAction.Create(Self);
  FactNewChat.ActionList := alUI;
  FactNewChat.Text := 'New Chat';
  FactNewChat.ShortCut := TextToShortCut('Alt+N');
  FactNewChat.OnExecute := actNewChatExecute;

  FactNewGemini := TAction.Create(Self);
  FactNewGemini.ActionList := alAgent;
  FactNewGemini.Text := 'New Gemini Chat';
  FactNewGemini.ShortCut := TextToShortCut('Alt+G');
  FactNewGemini.OnExecute := actNewGeminiExecute;
end;

procedure TdmActions.actNewChatExecute(Sender: TObject);
begin
  if Assigned(S) and Assigned(S.WebBrowserMain) then
    S.WebBrowserMain.EvaluateJavaScript('document.getElementById("btnNewChat").click();');
end;

procedure TdmActions.actNewGeminiExecute(Sender: TObject);
begin
  if Assigned(S) and Assigned(S.WebBrowserMain) then
    S.WebBrowserMain.EvaluateJavaScript('document.getElementById("btnNewGemini").click();');
end;

end.