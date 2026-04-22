unit uGeminiAgent;

interface

uses
  System.Classes, System.SysUtils, System.RegularExpressions, System.IOUtils, 
  JsonDataObjects, uACPAgent, uACPClient, uAgentTypes, uACPProtocol, System.SyncObjs;

type
  TGeminiAgent = class(TACPAgent)
  private
    procedure EnsureReady(AOnReady: TProc);
  protected
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); override;
    procedure DoNewSession(AResponse: TJsonObject); override;
  public
    constructor Create(AOwner: TComponent); override;
    
    procedure Connect; override;
    function Start(const ACommandLine: string = ''): Boolean; override;
    procedure Initialize(AParams: TJsonObject = nil); override;
    
    procedure NewSession(AParams: TJsonObject; OnResponse: TACPResponseAnonCallback = nil; OnCondition: TACPResponseCondition = nil); override;
    procedure LoadSession(const SessionId: string; ACallback: TProc<string>); override;
    procedure ResumeSession(const SessionId: string); override;
    procedure SendPrompt(const SessionId, AText: string); override;
    procedure ChangeModel(const SessionId, AModelId: string);
    procedure CancelPrompt(const SessionId: string);
    
    function IsReady: Boolean;
  end;

implementation

{ TGeminiAgent }

constructor TGeminiAgent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AgentName := 'gemini';
  AgentType := atGemini;
end;

function TGeminiAgent.Start(const ACommandLine: string = ''): Boolean;
begin
  if ACommandLine = '' then
    Result := inherited Start('cmd /c gemini --acp')
  else
    Result := inherited Start(ACommandLine);
end;

procedure TGeminiAgent.Connect;
begin
  State := asConnecting;
  
  TThread.CreateAnonymousThread(procedure
  begin
    try
      if Start then
      begin
        Initialize;
      end
      else
      begin
        TThread.Queue(nil, procedure
        begin
          State := asError;
        end);
      end;
    except
      on E: Exception do
      begin
        var LErrorMsg := E.Message;
        TThread.Queue(nil, procedure
        begin
          State := asError;
        end);
      end;
    end;
  end).Start;
end;

procedure TGeminiAgent.Initialize(AParams: TJsonObject);
var
  LParams: TJsonObject;
  WaitEvent: TEvent;
begin
  WaitEvent := TEvent.Create(nil, False, False, '');
  try
    State := asInitializing;
    
    if Assigned(AParams) then
      LParams := AParams.Clone as TJsonObject
    else
      LParams := TACPProtocol.CreateInitializeParams('acp-manager', '0.0.1');
      
    try
      ACPClient.Send('initialize', LParams,
        procedure(AResponse: TJsonObject)
        begin
          try
            if Assigned(AResponse) and not AResponse.Contains('error') then
            begin
              State := asReady;
            end
            else
            begin
              State := asError;
            end;
          finally
            WaitEvent.SetEvent;
          end;
        end,
        function(AResponse: TJsonObject): Boolean
        begin
          Result := AResponse.O['result'].Contains('authMethods');
        end);
    finally
      if not Assigned(AParams) then LParams.Free;
    end;

    if WaitEvent.WaitFor(10000) <> wrSignaled then
    begin
      State := asError;
    end;
  finally
    WaitEvent.Free;
  end;
end;

procedure TGeminiAgent.EnsureReady(AOnReady: TProc);
begin
  if (State = asReady) and IsConnected then
  begin
    if Assigned(AOnReady) then AOnReady();
    Exit;
  end;

  TThread.CreateAnonymousThread(procedure
  begin
    try
      if not IsConnected then
      begin
        if not Start then
        begin
          TThread.Queue(nil, procedure begin State := asError; end);
          Exit;
        end;
      end;

      if State <> asReady then
      begin
        Initialize;
      end;

      if State = asReady then
      begin
        if Assigned(AOnReady) then
          TThread.Queue(nil, procedure begin AOnReady(); end);
      end
      else
      begin
        TThread.Queue(nil, procedure begin State := asError; end);
      end;
    except
      on E: Exception do
      begin
        var LMsg := E.Message;
        TThread.Queue(nil, procedure begin State := asError; end);
      end;
    end;
  end).Start;
end;

procedure TGeminiAgent.NewSession(AParams: TJsonObject; OnResponse: TACPResponseAnonCallback; OnCondition: TACPResponseCondition);
var
  LClonedParams: TJsonObject;
begin
  if Assigned(AParams) then
    LClonedParams := AParams.Clone as TJsonObject
  else
    LClonedParams := nil;

  EnsureReady(procedure
  begin
    try
      inherited NewSession(LClonedParams, OnResponse, OnCondition);
    finally
      if Assigned(LClonedParams) then
        LClonedParams.Free;
    end;
  end);
end;

procedure TGeminiAgent.DoNewSession(AResponse: TJsonObject);
begin
  inherited; // 기본 구현 호출 (이벤트 발생 등)

  if Assigned(AResponse) and not AResponse.Contains('error') then
  begin
    var NewSessionId := AResponse.O['result'].S['sessionId'];
  end;
end;

procedure TGeminiAgent.LoadSession(const SessionId: string; ACallback: TProc<string>);
begin
  var LSid := SessionId;
  EnsureReady(procedure
  begin
    var Params: TJsonObject := TJsonObject.Create;
    try
      Params.S['sessionId'] := LSid;
      Params.S['cwd'] := Workspace;
      Params.A['mcpServers']; 
      
      ACPClient.Send('session/load', Params,
        procedure(AResponse: TJsonObject)
        var
          LErrMsg, LLoadedSid: string;
          LError, LParams, LUpdate: TJsonObject;
          LData: TSessionData;
          LSession: TSessionInfo;
        begin
          if Assigned(AResponse) and not AResponse.Contains('error') then
          begin
            LParams := AResponse.O['params'];
            LLoadedSid := LParams.S['sessionId'];
            
            // params가 비어있는 경우(result 응답인 경우 등)에 대한 방어 코드
            if LLoadedSid = '' then
              LLoadedSid := AResponse.O['result'].S['sessionId'];
              
            LUpdate := LParams.O['update'];

            // 1. 세션 데이터(커맨드 목록 등) 업데이트
            if (LLoadedSid <> '') and Sessions.TryGetValue(LLoadedSid, LData) then
            begin
              if LUpdate.Contains('availableCommands') then
                LData.CommandsJson := LUpdate.A['availableCommands'].ToJSON(False);
              LData.IsRestoring := False;
              Sessions.AddOrSetValue(LLoadedSid, LData);
            end;

            // 2. 세션 정보 객체 상태 업데이트
            LSession := FindSessionById(LLoadedSid);
            if Assigned(LSession) then
            begin
              LSession.IsRestoring := False;
              LSession.IsLoading := False;
              LSession.IsWaitForResponse := False;
            end;

            // 3. 복구 완료 통지 (UI 업데이트 유도)
            if LLoadedSid <> '' then
              DoSessionResumed(LLoadedSid);

            State := asReady;
            if Assigned(ACallback) then ACallback(LLoadedSid);
          end
          else
          begin
            LErrMsg := 'Session Load Failed';
            if Assigned(AResponse) and AResponse.Contains('error') then
            begin
              LError := AResponse.O['error'];
              LErrMsg := LErrMsg + ' (Code: ' + IntToStr(LError.I['code']) + ')';
              if LError.Contains('data') and LError.O['data'].Contains('details') then
                LErrMsg := LErrMsg + ': ' + LError.O['data'].S['details'];
            end;
            
            State := asReady; 
            if Assigned(ACallback) then ACallback(''); 
          end;
        end,
        function(AResponse: TJsonObject): Boolean
        begin
          // session/load 응답은 available_commands_update가 올 때까지 대기
          // sessionId가 일치하는지도 확인하여 더 정확하게 매칭 (SameText로 대소문자 무시)
          Result := SameText(AResponse.O['params'].S['sessionId'], LSid) and 
                    SameText(AResponse.O['params'].O['update'].S['sessionUpdate'], 'available_commands_update');
        end);
    finally
      Params.Free;
    end;
  end);
end;

procedure TGeminiAgent.ResumeSession(const SessionId: string);
begin
  inherited ResumeSession(SessionId);
  LoadSession(SessionId, nil);
end;

procedure TGeminiAgent.SendPrompt(const SessionId, AText: string);
var
  LD: TSessionData;
  Params, ItemObj: TJsonObject;
  PromptArr: TJsonArray;
  LMatchValue, LPart: string;
  LFilePath, LFileContent: string;
  LLastPos: Integer;
  LStream: TFileStream;
  LBytes: TBytes;
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LWorkspaceName: string;
  LSession: TSessionInfo;
begin
  LSession := FindSessionById(SessionId);
  if Assigned(LSession) then
  begin
    LSession.IsWaitForResponse := True;
    if Assigned(OnSessionMetadataUpdate) then
      OnSessionMetadataUpdate(Self, SessionId);
  end;

  if not Sessions.TryGetValue(SessionId, LD) then
    LD := Default(TSessionData);

  LD.FullThought := '';
  LD.FullMessage := '';
  LD.CurrentBlockText := '';
  LD.LastChunkType := '';
  LD.IsProcessing := True; 
  Sessions.AddOrSetValue(SessionId, LD);

  Params := TJsonObject.Create;
  try
    Params.S['sessionId'] := SessionId;
    PromptArr := Params.A['prompt'];

    LWorkspaceName := TPath.GetFileName(ExcludeTrailingPathDelimiter(Workspace));

    LLastPos := 1;
    LMatches := TRegEx.Matches(AText, '(@"(?:[^"]+)"|@[^\s\xa0\n]+)');
    
    for LMatch in LMatches do
    begin
      if LMatch.Index > LLastPos then
      begin
        LPart := Copy(AText, LLastPos, LMatch.Index - LLastPos);
        if LPart <> '' then
        begin
          ItemObj := PromptArr.AddObject;
          ItemObj.S['type'] := 'text';
          ItemObj.S['text'] := LPart;
        end;
      end;

      LMatchValue := LMatch.Value;
      LFilePath := Trim(LMatchValue.Substring(1)); 
      
      if LFilePath.StartsWith('"') and LFilePath.EndsWith('"') then
        LFilePath := Copy(LFilePath, 2, Length(LFilePath) - 2);

      LFilePath := LFilePath.Replace('/', PathDelim);

      if LFilePath.StartsWith(LWorkspaceName + PathDelim, True) then
        LFilePath := LFilePath.Substring(Length(LWorkspaceName) + 1);

      if not TPath.IsPathRooted(LFilePath) then
        LFilePath := TPath.GetFullPath(TPath.Combine(Workspace, LFilePath));

      LFileContent := '';
      if TFile.Exists(LFilePath) then
      begin
        try
          LStream := TFileStream.Create(LFilePath, fmOpenRead or fmShareDenyNone);
          try
            if LStream.Size > 0 then
            begin
              SetLength(LBytes, LStream.Size);
              LStream.ReadBuffer(LBytes[0], LStream.Size);
              LFileContent := TEncoding.UTF8.GetString(LBytes);
            end;
          finally LStream.Free; end;
        except
        end;
      end;

      ItemObj := PromptArr.AddObject;
      ItemObj.S['type'] := 'resource';
      with ItemObj.O['resource'] do
      begin
        S['text'] := LFileContent;
        S['uri'] := 'file:///' + LFilePath.Replace('\', '/');
      end;

      LLastPos := LMatch.Index + LMatch.Length;
    end;

    if LLastPos <= Length(AText) then
    begin
      LPart := Copy(AText, LLastPos, MaxInt);
      if LPart <> '' then
      begin
        ItemObj := PromptArr.AddObject;
        ItemObj.S['type'] := 'text';
        ItemObj.S['text'] := LPart;
      end;
    end;
    
    if PromptArr.Count = 0 then
    begin
      ItemObj := PromptArr.AddObject;
      ItemObj.S['type'] := 'text';
      ItemObj.S['text'] := AText;
    end;

    ACPClient.Send('session/prompt', Params, 
      procedure(AResponse: TJsonObject)
      var
        LD_Callback: TSessionData;
        LStopReason: string;
      begin
        if Sessions.TryGetValue(SessionId, LD_Callback) then
        begin
          LD_Callback.IsProcessing := False; 
          Sessions.AddOrSetValue(SessionId, LD_Callback);
        end;
        if Assigned(AResponse) and not AResponse.Contains('error') then
        begin
          LStopReason := AResponse.O['result'].S['stopReason'];
          if LStopReason = '' then LStopReason := 'end_turn';
          if Sessions.TryGetValue(SessionId, LD_Callback) then
            EndTurn(SessionId, LStopReason);
        end;
      end,
      function(AResponse: TJsonObject): Boolean
      begin
        // session/prompt 응답은 stopReason이 end_turn이어야 최종 응답으로 간주함
        Result := AResponse.O['result'].S['stopReason'] = 'end_turn';
      end);
  finally Params.Free; end;
end;

procedure TGeminiAgent.CancelPrompt(const SessionId: string);
var 
  P: TJsonObject;
  LSession: TSessionInfo;
begin
  LSession := FindSessionById(SessionId);
  if Assigned(LSession) then
  begin
    LSession.IsWaitForResponse := False;
    if Assigned(OnSessionMetadataUpdate) then
      OnSessionMetadataUpdate(Self, SessionId);
  end;

  P := TACPProtocol.CreateSessionCancelParams(SessionId);
  try ACPClient.SendRaw('{"jsonrpc":"2.0","method":"session/cancel","params":' + P.ToJSON(False) + '}'); finally P.Free; end;
end;

procedure TGeminiAgent.ChangeModel(const SessionId, AModelId: string);
var P: TJsonObject;
begin
  P := TJsonObject.Create;
  try
    P.S['sessionId'] := SessionId; P.S['modelId'] := AModelId;
    ACPClient.Send('session/set_model', P, 
      procedure(AResponse: TJsonObject)
      var 
        LData: TSessionData;
        LModels: TJsonObject;
      begin 
        if Assigned(AResponse) and not AResponse.Contains('error') then 
        begin
          if Sessions.TryGetValue(SessionId, LData) and (LData.ModelsJson <> '') then
          begin
            LModels := TJsonObject.Parse(LData.ModelsJson) as TJsonObject;
            try
              if Assigned(LModels) then
              begin
                LModels.S['currentModelId'] := AModelId;
                LData.ModelsJson := LModels.ToJSON(False);
                Sessions.AddOrSetValue(SessionId, LData);
              end;
            finally LModels.Free; end;
          end;
          
          if Assigned(OnPropertyUpdate) then
            OnPropertyUpdate(Self, SessionId, 'currentModelId', AModelId);
        end;
      end,
      function(AResponse: TJsonObject): Boolean
      begin
        // set_model은 별도 데이터가 없으므로 result 객체가 존재하기만 하면 됨
        Result := AResponse.Contains('result');
      end);
  finally P.Free; end;
end;

function TGeminiAgent.IsReady: Boolean; 
begin 
  Result := State = asReady;
end;

procedure TGeminiAgent.DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin 
  
  inherited;
  
end;

end.
