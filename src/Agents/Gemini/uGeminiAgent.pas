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
    
    procedure NewSession(AParams: TJsonObject); override;
    procedure ResumeSession(const SessionId: string); override;
    procedure SendPrompt(const SessionId, AText: string); override;
    procedure ChangeModel(const ASessionId, AModelId: string); override;
    procedure CancelPrompt(const ASessionId: string); override;
    procedure ReplyPermission(const ID, SessionId, OptionId: string); override;
    
    function IsReady: Boolean;
  end;

implementation

uses
  uACPDispatcher;

{ TGeminiAgent }

constructor TGeminiAgent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AgentName := 'gemini';
  FAgentType := atGemini;
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
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          State := asError;
        end));
      end;
    except
      on E: Exception do
      begin
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          State := asError;
        end));
      end;
    end;
  end).Start;
end;

procedure TGeminiAgent.Initialize(AParams: TJsonObject);
var
  WaitEvent: TEvent;
begin
  WaitEvent := TEvent.Create(nil, False, False, '');
  try
    State := asInitializing;
    Dispatcher.InitializeAgent('acp-manager', '0.0.1',
      procedure(ASuccess: Boolean)
      begin
        if ASuccess then State := asReady else State := asError;
        if Assigned(WaitEvent) then
          WaitEvent.SetEvent;
      end
    );

    if WaitEvent.WaitFor(60000) <> wrSignaled then
    begin
      State := asError;
      WaitEvent := nil;
    end;
  finally
    if Assigned(WaitEvent) then
      WaitEvent.Free;
  end;
end;

procedure TGeminiAgent.EnsureReady(AOnReady: TProc);
begin
  if (State = asReady) and GetIsConnected then
  begin
    if Assigned(AOnReady) then AOnReady();
    Exit;
  end;

  TThread.CreateAnonymousThread(procedure
  begin
    try
      if not GetIsConnected then
      begin
        if not Start then
        begin
          TThread.Queue(nil, TThreadProcedure(procedure begin State := asError; end));
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
          TThread.Queue(nil, TThreadProcedure(procedure begin AOnReady(); end));
      end
      else
      begin
        TThread.Queue(nil, TThreadProcedure(procedure begin State := asError; end));
      end;
    except
      on E: Exception do
      begin
        TThread.Queue(nil, TThreadProcedure(procedure begin State := asError; end));
      end;
    end;
  end).Start;
end;

procedure TGeminiAgent.NewSession(AParams: TJsonObject);
var
  LClonedParams: TJsonObject;
begin
  if Assigned(AParams) then LClonedParams := AParams.Clone as TJsonObject else LClonedParams := nil;
  EnsureReady(procedure
  begin
    try
      inherited NewSession(LClonedParams);
    finally
      if Assigned(LClonedParams) then LClonedParams.Free;
    end;
  end);
end;

procedure TGeminiAgent.DoNewSession(AResponse: TJsonObject);
begin
  inherited;
end;

procedure TGeminiAgent.ResumeSession(const SessionId: string);
begin
  EnsureReady(procedure
  begin
    inherited ResumeSession(SessionId);
  end);
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
  if Assigned(LSession) then begin LSession.IsWaitForResponse := True; NotifySessionMetadataUpdate(SessionId); end;
  if not Sessions.TryGetValue(SessionId, LD) then LD := Default(TSessionData);
  LD.FullThought := ''; LD.FullMessage := ''; LD.CurrentBlockText := ''; LD.LastChunkType := ''; LD.IsProcessing := True; 
  Sessions.AddOrSetValue(SessionId, LD);
  Params := TJsonObject.Create;
  try
    Params.S['sessionId'] := SessionId; PromptArr := Params.A['prompt']; LWorkspaceName := TPath.GetFileName(ExcludeTrailingPathDelimiter(Workspace));
    LLastPos := 1; LMatches := TRegEx.Matches(AText, '(@"(?:[^"]+)"|@[^\s\xa0\n]+)');
    for LMatch in LMatches do begin
      if LMatch.Index > LLastPos then begin LPart := Copy(AText, LLastPos, LMatch.Index - LLastPos); if LPart <> '' then begin ItemObj := PromptArr.AddObject; ItemObj.S['type'] := 'text'; ItemObj.S['text'] := LPart; end; end;
      LMatchValue := LMatch.Value; LFilePath := Trim(LMatchValue.Substring(1)); if LFilePath.StartsWith('"') and LFilePath.EndsWith('"') then LFilePath := Copy(LFilePath, 2, Length(LFilePath) - 2);
      LFilePath := LFilePath.Replace('/', PathDelim); if LFilePath.StartsWith(LWorkspaceName + PathDelim, True) then LFilePath := LFilePath.Substring(Length(LWorkspaceName) + 1);
      if not TPath.IsPathRooted(LFilePath) then LFilePath := TPath.GetFullPath(TPath.Combine(Workspace, LFilePath));
      LFileContent := ''; if TFile.Exists(LFilePath) then begin try LStream := TFileStream.Create(LFilePath, fmOpenRead or fmShareDenyNone); try if LStream.Size > 0 then begin SetLength(LBytes, LStream.Size); LStream.ReadBuffer(LBytes[0], LStream.Size); LFileContent := TEncoding.UTF8.GetString(LBytes); end; finally LStream.Free; end; except end; end;
      ItemObj := PromptArr.AddObject; ItemObj.S['type'] := 'resource'; with ItemObj.O['resource'] do begin S['text'] := LFileContent; S['uri'] := 'file:///' + LFilePath.Replace('\', '/'); end;
      LLastPos := LMatch.Index + LMatch.Length;
    end;
    if LLastPos <= Length(AText) then begin LPart := Copy(AText, LLastPos, MaxInt); if LPart <> '' then begin ItemObj := PromptArr.AddObject; ItemObj.S['type'] := 'text'; ItemObj.S['text'] := LPart; end; end;
    if PromptArr.Count = 0 then begin ItemObj := PromptArr.AddObject; ItemObj.S['type'] := 'text'; ItemObj.S['text'] := AText; end;
    Send('session/prompt', Params, procedure(AResponse: TJsonObject)
      var LD_Callback: TSessionData; LStopReason: string;
      begin
        if Sessions.TryGetValue(SessionId, LD_Callback) then begin LD_Callback.IsProcessing := False; Sessions.AddOrSetValue(SessionId, LD_Callback); end;
        if Assigned(AResponse) and not AResponse.Contains('error') then begin
          LStopReason := ''; if AResponse.Contains('result') then LStopReason := AResponse.O['result'].S['stopReason'];
          if (LStopReason = '') and AResponse.Contains('params') then LStopReason := AResponse.O['params'].O['update'].S['stopReason'];
          if LStopReason = '' then LStopReason := 'end_turn'; if Sessions.TryGetValue(SessionId, LD_Callback) then EndTurn(SessionId, LStopReason);
        end;
      end,
      [function(AObj: TJsonObject): Boolean begin Result := False; if AObj.Contains('result') then Result := AObj.O['result'].S['stopReason'] = 'end_turn'; if not Result and AObj.Contains('params') then Result := AObj.O['params'].O['update'].S['stopReason'] = 'end_turn'; end],
      SessionId);
  finally Params.Free; end;
end;

procedure TGeminiAgent.CancelPrompt(const ASessionId: string);
var P: TJsonObject; LSession: TSessionInfo;
begin
  LSession := FindSessionById(ASessionId); if Assigned(LSession) then begin LSession.IsWaitForResponse := False; NotifySessionMetadataUpdate(ASessionId); end;
  P := TACPProtocol.CreateSessionCancelParams(ASessionId); try Dispatcher.SendRaw('{"jsonrpc":"2.0","method":"session/cancel","params":' + P.ToJSON(False) + '}', P, ASessionId); finally P.Free; end;
end;

procedure TGeminiAgent.ChangeModel(const ASessionId, AModelId: string);
var P: TJsonObject;
begin
  P := TJsonObject.Create;
  try P.S['sessionId'] := ASessionId; P.S['modelId'] := AModelId;
    Send('session/set_model', P, procedure(AResponse: TJsonObject)
      var LUpdate: TJsonObject;
      begin
        if Assigned(AResponse) and not AResponse.Contains('error') then begin LUpdate := TJsonObject.Create; try LUpdate.S['currentModelId'] := AModelId; HandleModels(LUpdate); finally LUpdate.Free; end; end;
      end, [function(AResponse: TJsonObject): Boolean begin Result := AResponse.Contains('result'); end]);
  finally P.Free; end;
end;

procedure TGeminiAgent.ReplyPermission(const ID, SessionId, OptionId: string); begin inherited ReplyPermission(ID, SessionId, OptionId); end;
function TGeminiAgent.IsReady: Boolean; begin Result := State = asReady; end;
procedure TGeminiAgent.DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); begin inherited; end;

end.
