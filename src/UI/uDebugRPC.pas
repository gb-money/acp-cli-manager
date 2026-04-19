unit uDebugRPC;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.ListBox, FMX.StdCtrls, FMX.Controls.Presentation, FMX.Menus, System.Actions,
  FMX.ActnList, FMX.Platform;

type
  TfrmDebugRPC = class(TForm)
    lstLogs: TListBox;
    pnlHeader: TPanel;
    lblTitle: TLabel;
    btnClear: TButton;
    pmLogs: TPopupMenu;
    miCopy: TMenuItem;
    alDebug: TActionList;
    actCopy: TAction;
    procedure btnClearClick(Sender: TObject);
    procedure actCopyExecute(Sender: TObject);
  private
    { Private declarations }
  public
    procedure AddLog(const Direction, RawText: string);
    procedure AddACPLog(const Msg: string);
  end;

var
  frmDebugRPC: TfrmDebugRPC;

implementation

{$R *.fmx}

procedure TfrmDebugRPC.actCopyExecute(Sender: TObject);
var
  Svc: IFMXClipboardService;
begin
  if (lstLogs.ItemIndex >= 0) and TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Svc.SetClipboard(lstLogs.Items[lstLogs.ItemIndex]);
end;

procedure TfrmDebugRPC.AddLog(const Direction, RawText: string);
begin
  TThread.Queue(nil, procedure
  var
    Item: TListBoxItem;
    TimeStr: string;
  begin
    TimeStr := FormatDateTime('HH:mm:ss.zzz', Now);
    Item := TListBoxItem.Create(lstLogs);
    Item.Text := Format('[%s] [%s] %s', [TimeStr, Direction, RawText]);
    
    if Direction = 'IN' then Item.FontColor := $FF00FF00 // Green
    else if Direction = 'OUT' then Item.FontColor := $FF3FFF8B // Primary Greenish
    else if Direction = 'ERR' then Item.FontColor := $FFFF716C; // Error Red
    
    lstLogs.AddObject(Item);
    lstLogs.ItemIndex := lstLogs.Count - 1;
    lstLogs.ScrollToItem(Item);
  end);
end;

procedure TfrmDebugRPC.AddACPLog(const Msg: string);
begin
  TThread.Queue(nil, procedure
  var
    Item: TListBoxItem;
    TimeStr: string;
  begin
    TimeStr := FormatDateTime('HH:mm:ss.zzz', Now);
    Item := TListBoxItem.Create(lstLogs);
    Item.Text := Format('[%s] [ACP] %s', [TimeStr, Msg]);
    Item.FontColor := $FF00FFFF; // Cyan
    lstLogs.AddObject(Item);
    lstLogs.ItemIndex := lstLogs.Count - 1;
    lstLogs.ScrollToItem(Item);
  end);
end;

procedure TfrmDebugRPC.btnClearClick(Sender: TObject);
begin
  lstLogs.Clear;
end;

end.
