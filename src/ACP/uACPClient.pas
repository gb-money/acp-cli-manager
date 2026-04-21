unit uACPClient;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.SyncObjs,
  JsonDataObjects, uAgentProcess;

type
  TRPCDirection = (rdIncoming, rdOutgoing, rdInternal);
  
  TACPResponseAnonCallback = reference to procedure(AResponse: TJsonObject);

  TACPReceiveEvent = procedure(Sender: TObject;
    const ID, Method: string;
    Params, ResultObj, ErrorObj: TJsonObject) of object;

  TACPRawDataEvent = procedure(Sender: TObject; Direction: TRPCDirection; const RawText: string) of object;
  TACPErrorEvent = procedure(Sender: TObject; const ErrorMsg: string) of object;
  TACPProcessTerminatedEvent = procedure(Sender: TObject; ExitCode: Cardinal) of object;

  TACPClient = class(TComponent)
  private
    FAgentProcess: TAgentProcess;
    FLineBuffer: string;
    FBufferLock: TCriticalSection;
    FLastMessageId: Integer;
    FCallbacks: TDictionary<string, TACPResponseAnonCallback>;
    FPendingMethods: TDictionary<string, string>;
    FOnReceive: TACPReceiveEvent;
    FOnRawData: TACPRawDataEvent;
    FOnError: TACPErrorEvent;
    FOnTerminated: TACPProcessTerminatedEvent;
    procedure HandleProcessOutput(Sender: TObject; const Text: string);
    procedure HandleProcessTerminated(Sender: TObject; ExitCode: Cardinal);
    procedure ProcessBuffer;
    function GetCommandLine: string;
    procedure SetCommandLine(const Value: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Start: Boolean;
    procedure Stop;
    procedure Send(const Method: string; Params: TJsonObject = nil; OnResponse: TACPResponseAnonCallback = nil);
    procedure SendResponse(const ID: string; ResultObj: TJsonObject = nil);
    procedure SendRaw(const JsonStr: string);
    function IsRunning: Boolean;
    property CommandLine: string read GetCommandLine write SetCommandLine;
    property OnReceive: TACPReceiveEvent read FOnReceive write FOnReceive;
    property OnRawData: TACPRawDataEvent read FOnRawData write FOnRawData;
    property OnError: TACPErrorEvent read FOnError write FOnError;
    property OnTerminated: TACPProcessTerminatedEvent read FOnTerminated write FOnTerminated;
  end;

implementation

{ TACPClient }

constructor TACPClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBufferLock := TCriticalSection.Create;
  FLineBuffer := '';
  FLastMessageId := 0;
  FCallbacks := TDictionary<string, TACPResponseAnonCallback>.Create;
  FPendingMethods := TDictionary<string, string>.Create;
  FAgentProcess := TAgentProcess.Create(Self);
  FAgentProcess.OnOutput := HandleProcessOutput;
  FAgentProcess.OnTerminated := HandleProcessTerminated;
end;

destructor TACPClient.Destroy;
begin
  FAgentProcess.Free;
  FCallbacks.Free;
  FPendingMethods.Free;
  FBufferLock.Free;
  inherited;
end;

function TACPClient.GetCommandLine: string;
begin
  Result := FAgentProcess.CommandLine;
end;

procedure TACPClient.SetCommandLine(const Value: string);
begin
  FAgentProcess.CommandLine := Value;
end;

function TACPClient.IsRunning: Boolean;
begin
  Result := FAgentProcess.IsRunning;
end;

function TACPClient.Start: Boolean;
begin
  FLineBuffer := '';
  FLastMessageId := 0;
  FCallbacks.Clear;
  FPendingMethods.Clear;
  Result := FAgentProcess.Start;
end;

procedure TACPClient.Stop;
begin
  FAgentProcess.Stop;
  FLineBuffer := '';
  FCallbacks.Clear;
  FPendingMethods.Clear;
end;

procedure TACPClient.SendRaw(const JsonStr: string);
var
  FinalStr: string;
begin
  if not IsRunning or FAgentProcess.IsStopping then
    Exit;

  FinalStr := StringReplace(JsonStr, #13, '', [rfReplaceAll]);
  FinalStr := StringReplace(FinalStr, #10, '', [rfReplaceAll]);

  if Assigned(FOnRawData) then
    FOnRawData(Self, rdOutgoing, FinalStr);
    
  FBufferLock.Enter;
  try
    FAgentProcess.WriteLine(FinalStr);
  finally
    FBufferLock.Leave;
  end;
end;

procedure TACPClient.Send(const Method: string; Params: TJsonObject; OnResponse: TACPResponseAnonCallback);
var
  ReqObj: TJsonObject;
  MessageId: string;
begin
  FBufferLock.Enter;
  try
    Inc(FLastMessageId);
    MessageId := IntToStr(FLastMessageId);

    ReqObj := TJsonObject.Create;
    try
      ReqObj.S['jsonrpc'] := '2.0';
      ReqObj.S['method'] := Method;
      ReqObj.I['id'] := FLastMessageId;

      if Assigned(Params) then
        ReqObj.O['params'].Assign(Params);

      if Assigned(OnResponse) then
        FCallbacks.Add(MessageId, OnResponse);
      FPendingMethods.AddOrSetValue(MessageId, Method);

      SendRaw(ReqObj.ToJSON(False));
    finally
      ReqObj.Free;
    end;
  finally
    FBufferLock.Leave;
  end;
end;

procedure TACPClient.SendResponse(const ID: string; ResultObj: TJsonObject);
var
  RespObj: TJsonObject;
begin
  RespObj := TJsonObject.Create;
  try
    RespObj.S['jsonrpc'] := '2.0';
    // ID가 숫자 형태이면 숫자로, 아니면 문자열로 전송
    if (Length(ID) > 0) and (ID[1] in ['0'..'9']) then
      RespObj.I['id'] := StrToIntDef(ID, 0)
    else
      RespObj.S['id'] := ID;

    // 표준 JSON-RPC 응답: method 없이 result 필드 사용
    if Assigned(ResultObj) then
      RespObj.O['result'].Assign(ResultObj)
    else
      RespObj.O['result']; // Empty {}

    SendRaw(RespObj.ToJSON(False));
  finally
    RespObj.Free;
  end;
end;

procedure TACPClient.HandleProcessOutput(Sender: TObject; const Text: string);
begin
  if FAgentProcess.IsStopping then
    Exit;
    
  FBufferLock.Enter;
  try
    FLineBuffer := FLineBuffer + Text;
  finally
    FBufferLock.Leave;
  end;
  ProcessBuffer;
end;

procedure TACPClient.ProcessBuffer;
var
  NewlinePos: Integer;
  LineStr: string;
  ParsedObj: TJsonObject;
  pParams, pResult, pError: TJsonObject;
  vID, vMethod: string;
  Callback: TACPResponseAnonCallback;
  ProcessingBuffer: string;
  LBaseObj: TJsonBaseObject;
begin
  // 1. 버퍼 전체를 로컬로 가져오고 메인 버퍼 비움 (락 보호)
  FBufferLock.Enter;
  try
    ProcessingBuffer := FLineBuffer;
    FLineBuffer := '';
  finally
    FBufferLock.Leave;
  end;

  if ProcessingBuffer = '' then Exit;

  // 2. 로컬 버퍼를 분해하여 처리
  while True do 
  begin
    NewlinePos := Pos(#10, ProcessingBuffer);
    if NewlinePos <= 0 then 
    begin
      // 줄바꿈이 없는 남은 조각은 다시 메인 버퍼 앞으로 돌려줌 (락 보호)
      if ProcessingBuffer <> '' then
      begin
        FBufferLock.Enter;
        try
          FLineBuffer := ProcessingBuffer + FLineBuffer;
        finally
          FBufferLock.Leave;
        end;
      end;
      Break;
    end;

    LineStr := Copy(ProcessingBuffer, 1, NewlinePos - 1);
    Delete(ProcessingBuffer, 1, NewlinePos);

    LineStr := Trim(StringReplace(LineStr, #13, '', [rfReplaceAll]));
    if LineStr = '' then Continue;

    if Assigned(FOnRawData) then
      FOnRawData(Self, rdIncoming, LineStr);

    LBaseObj := nil;
    try
      try
        LBaseObj := TJsonBaseObject.Parse(LineStr);
      except
        on E: Exception do
        begin
          if Assigned(FOnRawData) then
            FOnRawData(Self, rdInternal, 'JSON Parse Error: ' + E.Message + ' Source: ' + LineStr);
          Continue; // Skip invalid JSON and continue loop
        end;
      end;

      if (LBaseObj = nil) or not (LBaseObj is TJsonObject) then
        Continue;

      ParsedObj := TJsonObject(LBaseObj);

      vID := '';
      if ParsedObj.Contains('id') then 
      begin
        if ParsedObj.Types['id'] = jdtString then
          vID := ParsedObj.S['id']
        else
          vID := IntToStr(ParsedObj.I['id']);
      end;

      vMethod := ParsedObj.S['method'];

      if (vID <> '') and (vMethod = '') then
        FPendingMethods.TryGetValue(vID, vMethod);

      pParams := nil; pResult := nil; pError := nil;
      if ParsedObj.IndexOf('params') >= 0 then
      begin
        if ParsedObj.Items[ParsedObj.IndexOf('params')].Typ = jdtObject then
          pParams := ParsedObj.O['params'];
      end;
      
      if ParsedObj.IndexOf('result') >= 0 then
      begin
        if ParsedObj.Items[ParsedObj.IndexOf('result')].Typ = jdtObject then
          pResult := ParsedObj.O['result'];
      end;

      if ParsedObj.IndexOf('error') >= 0 then
      begin
        if ParsedObj.Items[ParsedObj.IndexOf('error')].Typ = jdtObject then
          pError := ParsedObj.O['error'];
      end;

      if (vID <> '') and not Assigned(pResult) and Assigned(pParams) then
        pResult := pParams;

      // --- Improved Response Matching ---
      Callback := nil;
      // Only treat as a Response if it contains 'result' or 'error' and has no 'method'
      if (vID <> '') and (vID <> '0') and (ParsedObj.S['method'] = '') and 
         (Assigned(pResult) or Assigned(pError)) then 
      begin
        if FCallbacks.TryGetValue(vID, Callback) then
        begin
          FCallbacks.Remove(vID);
          if Assigned(FOnRawData) then
            FOnRawData(Self, rdInternal, 'Callback FOUND and matching for ID: ' + vID);
        end;
        FPendingMethods.Remove(vID);
      end;

      if Assigned(Callback) then
      begin
        try
          Callback(ParsedObj);
        except
          on E: Exception do
            if Assigned(FOnRawData) then
              FOnRawData(Self, rdInternal, 'Exception in RPC Callback: ' + E.Message);
        end;
      end;

      if Assigned(FOnReceive) and not FAgentProcess.IsStopping then
        FOnReceive(Self, vID, vMethod, pParams, pResult, pError);
    finally
      LBaseObj.Free;
    end;
  end;
end;

procedure TACPClient.HandleProcessTerminated(Sender: TObject; ExitCode: Cardinal);
begin
  if Assigned(FOnTerminated) then
    FOnTerminated(Self, ExitCode);
end;

end.
