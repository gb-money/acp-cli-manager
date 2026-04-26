unit uACPClient;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, System.SyncObjs,
  JsonDataObjects, uAgentProcess, uAgentTypes;

type
  TACPResponseAnonCallback = reference to procedure(AResponse: TJsonObject);
  TACPResponseCondition = reference to function(AResponse: TJsonObject): Boolean;

  TACPRequestRecord = record
    MessageId: string;
    MethodName: string;
    SessionId: string;
    Conditions: TArray<TACPResponseCondition>;
    CurrentStep: Integer;
    Callback: TACPResponseAnonCallback;
  end;

  TACPReceiveEvent = procedure(Sender: TObject;
    const ID, Method: string;
    Params, ResultObj, ErrorObj: TJsonObject) of object;

  TACPRawDataEvent = procedure(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string) of object;
  TACPErrorEvent = procedure(Sender: TObject; const ErrorMsg: string) of object;
  TACPProcessTerminatedEvent = procedure(Sender: TObject; ExitCode: Cardinal) of object;

  TACPClient = class(TComponent)
  private
    FAgentProcess: TAgentProcess;
    FLineBuffer: string;
    FBufferLock: TCriticalSection;
    FLastMessageId: Integer;
    FCallbacks: TList<TACPRequestRecord>;
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
    procedure Send(const Method: string; Params: TJsonObject = nil; OnResponse: TACPResponseAnonCallback = nil; OnConditions: TArray<TACPResponseCondition> = nil; const SessionId: string = '');
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
  FCallbacks := TList<TACPRequestRecord>.Create;
  FAgentProcess := TAgentProcess.Create(Self);
  FAgentProcess.OnOutput := HandleProcessOutput;
  FAgentProcess.OnTerminated := HandleProcessTerminated;
end;

destructor TACPClient.Destroy;
begin
  FAgentProcess.Free;
  FCallbacks.Free;
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
  Result := FAgentProcess.Start;
end;

procedure TACPClient.Stop;
begin
  FAgentProcess.Stop;
  FLineBuffer := '';
  FCallbacks.Clear;
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
    FOnRawData(Self, rdOutgoing, '', nil, FinalStr);

  FBufferLock.Enter;
  try
    FAgentProcess.WriteLine(FinalStr);
  finally
    FBufferLock.Leave;
  end;
end;

procedure TACPClient.Send(const Method: string; Params: TJsonObject; OnResponse: TACPResponseAnonCallback; OnConditions: TArray<TACPResponseCondition>; const SessionId: string);
var
  ReqObj: TJsonObject;
  LRecord: TACPRequestRecord;
  LMessageId: string;
begin
  FBufferLock.Enter;
  try
    Inc(FLastMessageId);
    LMessageId := IntToStr(FLastMessageId);

    ReqObj := TJsonObject.Create;
    try
      ReqObj.S['jsonrpc'] := '2.0';
      ReqObj.S['method'] := Method;
      ReqObj.I['id'] := FLastMessageId;

      if Assigned(Params) then
        ReqObj.O['params'].FromJSON(Params.ToJSON(False));

      if Assigned(OnResponse) or (Length(OnConditions) > 0) then
      begin
        LRecord.MessageId := LMessageId;
        LRecord.MethodName := Method;
        LRecord.SessionId := SessionId;
        LRecord.Conditions := OnConditions;
        LRecord.CurrentStep := 0;
        LRecord.Callback := OnResponse;
        FCallbacks.Add(LRecord);
      end;

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
      RespObj.O['result'].FromJSON(ResultObj.ToJSON(False))
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
  LNewlinePos: Integer;
  LLineStr: string;
  LParsedObj: TJsonObject;
  LParams, LResult, LError: TJsonObject;
  LId, LMethod: string;
  LFinalCallback: TACPResponseAnonCallback;
  LProcessingBuffer: string;
  LBaseObj: TJsonBaseObject;
  i: Integer;
begin
  // 1. 버퍼 전체를 로컬로 가져오고 메인 버퍼 비움 (락 보호)
  FBufferLock.Enter;
  try
    LProcessingBuffer := FLineBuffer;
    FLineBuffer := '';
  finally
    FBufferLock.Leave;
  end;

  if LProcessingBuffer = '' then Exit;

  // 2. 로컬 버퍼를 분해하여 처리
  while True do 
  begin
    LNewlinePos := Pos(#10, LProcessingBuffer);
    if LNewlinePos <= 0 then 
    begin
      // 줄바꿈이 없는 남은 조각은 다시 메인 버퍼 앞으로 돌려줌 (락 보호)
      if LProcessingBuffer <> '' then
      begin
        FBufferLock.Enter;
        try
          FLineBuffer := LProcessingBuffer + FLineBuffer;
        finally
          FBufferLock.Leave;
        end;
      end;
      Break;
    end;

    LLineStr := Copy(LProcessingBuffer, 1, LNewlinePos - 1);
    Delete(LProcessingBuffer, 1, LNewlinePos);

    LLineStr := Trim(StringReplace(LLineStr, #13, '', [rfReplaceAll]));
    if LLineStr = '' then Continue;

    LBaseObj := nil;
    try
      try
        LBaseObj := TJsonBaseObject.Parse(LLineStr);
      except
        on E: Exception do
        begin
          if Assigned(FOnRawData) then
            FOnRawData(Self, rdInternal, '', nil, 'JSON Parse Error: ' + E.Message + ' Source: ' + LLineStr);
          Continue;
        end;
      end;

      if (LBaseObj = nil) or not (LBaseObj is TJsonObject) then
        Continue;

      LParsedObj := TJsonObject(LBaseObj);

      if Assigned(FOnRawData) then
      begin
        var LSid := '';
        if Assigned(LParsedObj) then
        begin
          LSid := LParsedObj.S['sessionId'];
          if LSid = '' then LSid := LParsedObj.O['params'].S['sessionId'];
          if LSid = '' then LSid := LParsedObj.O['result'].S['sessionId'];
        end;
        FOnRawData(Self, rdIncoming, LSid, LParsedObj, LLineStr);
      end;

      // JSON 필드 추출 (id, method, params, result, error)
      LId := '';
      if LParsedObj.Contains('id') then 
      begin
        if LParsedObj.Types['id'] = jdtString then LId := LParsedObj.S['id']
        else LId := IntToStr(LParsedObj.I['id']);
      end;

      LMethod := LParsedObj.S['method'];
      LParams := nil; LResult := nil; LError := nil;
      if LParsedObj.Contains('params') and (LParsedObj.Types['params'] = jdtObject) then LParams := LParsedObj.O['params'];
      if LParsedObj.Contains('result') and (LParsedObj.Types['result'] = jdtObject) then LResult := LParsedObj.O['result'];
      if LParsedObj.Contains('error') and (LParsedObj.Types['error'] = jdtObject) then LError := LParsedObj.O['error'];

      // Fallback: Result가 Params 필드에 실려오는 경우 처리
      if (LId <> '') and (LResult = nil) and (LParams <> nil) then
        LResult := LParams;

      // 3. 콜백 매칭 (Sequential Condition Chain)
      LFinalCallback := nil;
      FBufferLock.Enter;
      try
        for i := FCallbacks.Count - 1 downto 0 do
        begin
          var LReq := FCallbacks[i];
          var LStep := LReq.CurrentStep;
          
          // 3-1. 매칭 판단 로직
          var LMatch := False;
          var LIsStep0 := (LStep = 0);
          
          if LIsStep0 and (LReq.MessageId <> '') and (LId = LReq.MessageId) then
          begin
            // Step 0이고 ID가 일치함. 
            LMethod := LReq.MethodName; // 🎯 메서드명 복원
            
            // 조건이 있다면 조건까지 통과해야 함.
            if (LStep < Length(LReq.Conditions)) and Assigned(LReq.Conditions[LStep]) then
              LMatch := LReq.Conditions[LStep](LParsedObj)
            else
              LMatch := True; // 조건이 없으면 ID 일치만으로 통과
          end
          else if (LStep < Length(LReq.Conditions)) and Assigned(LReq.Conditions[LStep]) then
          begin
            // ID가 없거나 Step 0이 아님. 조건 체크 수행.
            LMatch := LReq.Conditions[LStep](LParsedObj);
          end;

          // 3-2. 단계 진행 또는 완료
          if LMatch then
          begin
            LReq.CurrentStep := LReq.CurrentStep + 1;
            
            if LReq.CurrentStep >= Length(LReq.Conditions) then
            begin
              // 모든 단계 완료 (Handshake Finished)
              LFinalCallback := LReq.Callback;
              FCallbacks.Delete(i);
              if Assigned(FOnRawData) then
                FOnRawData(Self, rdInternal, '', nil, 'Handshake COMPLETED for Method: ' + LReq.MethodName);
              Break;
            end
            else
            begin
              // 다음 단계를 위해 상태 업데이트 (Wait for next message)
              FCallbacks[i] := LReq;
              if Assigned(FOnRawData) then
                FOnRawData(Self, rdInternal, '', nil, 'Handshake STEP ' + IntToStr(LReq.CurrentStep) + ' matched for Method: ' + LReq.MethodName);
              Break; 
            end;
          end;
        end;
      finally
        FBufferLock.Leave;
      end;

      // 4. 콜백 실행
      if Assigned(LFinalCallback) then
      begin
        try
          LFinalCallback(LParsedObj);
        except
          on E: Exception do
            if Assigned(FOnRawData) then
              FOnRawData(Self, rdInternal, '', nil, 'Exception in RPC Callback: ' + E.Message);
        end;
      end;

      // 5. 일반 수신 이벤트 발생
      if Assigned(FOnReceive) and not FAgentProcess.IsStopping then
      begin
        try
          FOnReceive(Self, LId, LMethod, LParams, LResult, LError);
        except
          on E: Exception do
            if Assigned(FOnRawData) then
              FOnRawData(Self, rdInternal, '', nil, 'Exception in OnReceive event: ' + E.Message);
        end;
      end;
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
