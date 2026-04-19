unit uDebugRPC;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.ListBox, FMX.StdCtrls, FMX.Controls.Presentation, FMX.Platform, FMX.Clipboard;

type
  TfrmDebugRPC = class(TForm)
    lstLog: TListBox;
    pnlToolbar: TPanel;
    btnCopy: TButton;
    btnClear: TButton;
    procedure btnClearClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
  private
    { Private declarations }
  public
    procedure AddLog(const Direction, Text: string);
    procedure AddACPLog(const Msg: string);
  end;

var
  frmDebugRPC: TfrmDebugRPC;

implementation

{$R *.fmx}

procedure TfrmDebugRPC.btnClearClick(Sender: TObject);
begin
  lstLog.Items.Clear;
end;

procedure TfrmDebugRPC.btnCopyClick(Sender: TObject);
var
  LClipboard: IFMXClipboardService;
begin
  if (lstLog.ItemIndex >= 0) and TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, LClipboard) then
  begin
    LClipboard.SetClipboard(lstLog.Items[lstLog.ItemIndex]);
  end;
end;

procedure TfrmDebugRPC.AddLog(const Direction, Text: string);
var
  LMsg: string;
begin
  LMsg := Format('[%s] %s: %s', [FormatDateTime('HH:mm:ss', Now), Direction, Text]);
  lstLog.Items.Insert(0, LMsg);
  if lstLog.Items.Count > 1000 then
    lstLog.Items.Delete(lstLog.Items.Count - 1);
end;

procedure TfrmDebugRPC.AddACPLog(const Msg: string);
begin
  lstLog.Items.Insert(0, Format('[%s] [ACP] %s', [FormatDateTime('HH:mm:ss', Now), Msg]));
end;

end.
