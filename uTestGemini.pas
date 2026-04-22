unit uTestGemini;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Layouts, FMX.ListBox, FMX.StdCtrls, FMX.Controls.Presentation, FMX.Edit,
  uGeminiAgent, uAgent, uACPAgent, JsonDataObjects, System.NetEncoding;

type
  TfrmTestGemini = class(TForm)
    PanelTop: TPanel;
    btnConnect: TButton;
    btnDisconnect: TButton;
    EditPrompt: TEdit;
    btnSend: TButton;
    ListChat: TListBox;
    lblStatus: TLabel;
    procedure btnConnectClick(Sender: TObject);
    procedure btnDisconnectClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FAgent: TGeminiAgent;
    FCurrentSessionId: string;
    procedure DoStatusChange(Sender: TObject; const Msg: string);
    procedure DoStateChange(Sender: TObject; const OldState, NewState: TAgentState);
    procedure DoEndTurn(Sender: TObject; const SessionId, StopReason: string);
    procedure DoThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
    procedure DoRawData(Sender: TObject; const Direction, RawText: string);
    procedure AddLogLine(const ATxt: string);
  public
  end;

var
  frmTestGemini: TfrmTestGemini;

implementation

{$R *.fmx}

procedure TfrmTestGemini.FormCreate(Sender: TObject);
begin
  FAgent := TGeminiAgent.Create(Self);
  FAgent.OnEndTurn := DoEndTurn;
  FAgent.OnThoughtChunk := DoThoughtChunk;
  FAgent.OnMessageChunk := DoMessageChunk;
  FAgent.OnRawData := DoRawData;
end;

procedure TfrmTestGemini.FormDestroy(Sender: TObject);
begin
  FAgent.Free;
end;

procedure TfrmTestGemini.AddLogLine(const ATxt: string);
begin
  TThread.Queue(nil, procedure
  begin
    ListChat.Items.Add(ATxt);
    ListChat.ItemIndex := ListChat.Count - 1;
  end);
end;

procedure TfrmTestGemini.DoRawData(Sender: TObject; const Direction, RawText: string);
begin
  AddLogLine(Format('[%s] %s', [Direction, RawText]));
end;

procedure TfrmTestGemini.btnConnectClick(Sender: TObject);
begin
  FCurrentSessionId := '';
  btnSend.Enabled := False;
  lblStatus.Text := 'Connecting to Gemini...';
  FAgent.Connect;
end;

procedure TfrmTestGemini.btnDisconnectClick(Sender: TObject);
begin
  FAgent.Stop;
  FCurrentSessionId := '';
  btnSend.Enabled := False;
  lblStatus.Text := 'Disconnected.';
  AddLogLine('>>> Agent process stopped.');
end;

procedure TfrmTestGemini.DoStateChange(Sender: TObject; const OldState, NewState: TAgentState);
begin
  if NewState = asReady then
  begin
    TThread.Queue(nil, procedure
    begin
      lblStatus.Text := 'Requesting new session...';
      FAgent.CreateNewSession('', procedure(const SessionId: string)
        begin
          TThread.Queue(nil, procedure
          begin
            FCurrentSessionId := SessionId;
            if FCurrentSessionId <> '' then
            begin
              AddLogLine('>>> SESSION READY: ' + FCurrentSessionId);
              btnSend.Enabled := True;
              btnSend.Repaint;
              EditPrompt.SetFocus;
              lblStatus.Text := 'Session Ready.';
            end
            else
            begin
              AddLogLine('>>> Session Creation Failed (Empty ID)');
              ShowMessage('Failed to create session.');
            end;
          end);
        end);
    end);
  end;
end;

procedure TfrmTestGemini.btnSendClick(Sender: TObject);
begin
  if (FCurrentSessionId <> '') and (EditPrompt.Text <> '') then
  begin
    AddLogLine('ME: ' + EditPrompt.Text);
    FAgent.SendPrompt(FCurrentSessionId, EditPrompt.Text);
    EditPrompt.Text := '';
    lblStatus.Text := 'Sending prompt...';
  end;
end;

procedure TfrmTestGemini.DoStatusChange(Sender: TObject; const Msg: string);
begin
  System.Classes.TThread.Queue(nil, procedure begin lblStatus.Text := Msg; end);
end;

procedure TfrmTestGemini.DoThoughtChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
begin
  System.Classes.TThread.Queue(nil, procedure begin lblStatus.Text := 'Thinking... (' + IntToStr(Length(FullText)) + ')'; end);
end;

procedure TfrmTestGemini.DoMessageChunk(Sender: TObject; const SessionId, Chunk, FullText: string);
begin
  System.Classes.TThread.Queue(nil, procedure begin lblStatus.Text := 'Receiving... (' + IntToStr(Length(FullText)) + ')'; end);
end;

procedure TfrmTestGemini.DoEndTurn(Sender: TObject; const SessionId, StopReason: string);
begin
  AddLogLine('AI Turn Ended: ' + StopReason);
  System.Classes.TThread.Queue(nil, procedure begin lblStatus.Text := 'Ready'; end);
end;

end.
