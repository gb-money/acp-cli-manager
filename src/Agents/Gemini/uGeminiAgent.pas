unit uGeminiAgent;

interface

uses
  System.Classes, System.SysUtils, System.RegularExpressions, System.IOUtils, 
  JsonDataObjects, uAgent, uACPAgent, uACPClient, uACPProtocol, System.SyncObjs;

type
  TModelsAvailableEvent = procedure(Sender: TObject; AModels: TStrings) of object;
  TSessionCreatedCallback = reference to procedure(const SessionId: string);

  TGeminiAgent = class(TACPAgent)
  private
  protected
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    
    procedure Connect; override;
    function Start: Boolean; override; // Synchronous start for this agent
    procedure Initialize; override;
    procedure Stop; override;
    
    procedure CreateNewSession(const Cwd: string; const Mode: string; ACallback: TProc<string>); override;
    procedure LoadSession(const SessionId: string; ACallback: TProc<string>); override;
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
end;

destructor TGeminiAgent.Destroy;
begin
  inherited;
end;

function TGeminiAgent.Start: Boolean;
begin
  // Set CommandLine before starting the process engine
  ACPClient.CommandLine := 'cmd /c gemini --acp';
  Result := inherited Start;
end;

procedure TGeminiAgent.Connect;
begin
  inherited Connect;
  DoStatusChange('Starting Gemini process...');
  State := asConnecting;
  
  TThread.CreateAnonymousThread(procedure
  begin
    try
      // In background thread, we can call synchronous Start and Initialize
      if Start then
      begin
        Initialize;
      end
      else
      begin
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          DoStatusChange('ERR: Failed to start gemini process. (Check if gemini-cli is installed)');
          State := asError;
        end));
      end;
    except
      on E: Exception do
      begin
        var LErrorMsg := E.Message;
        TThread.Queue(nil, TThreadProcedure(procedure
        begin
          DoStatusChange('ERR: ' + LErrorMsg);
          State := asError;
        end));
      end;
    end;
  end).Start;
end;

procedure TGeminiAgent.Initialize;
var
  Params: TJsonObject;
  WaitEvent: TEvent;
begin
  // Initialize MUST be called from a background thread as it blocks
  WaitEvent := TEvent.Create(nil, False, False, '');
  try
    DoStatusChange('Sending initialize request...');
    State := asInitializing;
    Params := TACPProtocol.CreateInitializeParams('acp-manager', '0.0.1');
    try
      ACPClient.Send('initialize', Params,
        procedure(AResponse: TJsonObject)
        begin
          try
            if Assigned(AResponse) and not AResponse.Contains('error') then
            begin
              DoStatusChange('Initialized successfully.');
              State := asReady;
            end
            else
            begin
              DoStatusChange('ERR: Initialization failed.');
              State := asError;
            end;
          finally
            WaitEvent.SetEvent;
          end;
        end);
    finally
      Params.Free;
    end;

    // Block current thread until callback signals or 10s timeout
    if WaitEvent.WaitFor(10000) <> wrSignaled then
    begin
      DoStatusChange('ERR: Initialization timed out.');
      State := asError;
    end;
  finally
    WaitEvent.Free;
  end;
end;

procedure TGeminiAgent.CreateNewSession(const Cwd: string; const Mode: string; ACallback: TProc<string>);
var
  Params: TJsonObject;
begin
  DoStatusChange('Creating Session...');
  Params := TACPProtocol.CreateSessionNewParams(Cwd, Mode);
  try
    ACPClient.Send('session/new', Params,
      procedure(AResponse: TJsonObject)
      var
        NewSessionId: string;
        LResult: TJsonObject;
      begin
        if Assigned(AResponse) and not AResponse.Contains('error') then
        begin
          LResult := AResponse.O['result'];
          NewSessionId := LResult.S['sessionId'];
          if NewSessionId = '' then NewSessionId := LResult.S['session_id'];

          if NewSessionId <> '' then
          begin
            DoStatusChange('Session Created: ' + NewSessionId);
            if Assigned(ACallback) then ACallback(NewSessionId);
          end
          else
            DoStatusChange('ERR: Session ID missing in response.');
        end
        else
        begin
          if Assigned(AResponse) and AResponse.Contains('error') then 
            DoStatusChange('Session Failed: ' + AResponse.O['error'].ToJSON(False))
          else 
            DoStatusChange('Session Failed: Unknown error');
          if Assigned(ACallback) then ACallback('');
        end;
      end);
  finally
    Params.Free;
  end;
end;

procedure TGeminiAgent.LoadSession(const SessionId: string; ACallback: TProc<string>);
var
  Params: TJsonObject;
  LSid: string;
begin
  LSid := SessionId;
  DoStatusChange('Loading Session: ' + LSid);
  Params := TJsonObject.Create;
  try
    Params.S['sessionId'] := LSid;
    Params.S['cwd'] := Workspace;
    Params.A['mcpServers']; 
    
    ACPClient.Send('session/load', Params,
      procedure(AResponse: TJsonObject)
      var
        LErrMsg: string;
        LError: TJsonObject;
      begin
        if Assigned(AResponse) and not AResponse.Contains('error') then
        begin
          DoStatusChange('Session Loaded: ' + LSid);
          State := asReady;
          if Assigned(ACallback) then ACallback(LSid);
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
          
          DoStatusChange(LErrMsg);
          State := asReady; 
          if Assigned(ACallback) then ACallback(''); 
        end;
      end);
  finally
    Params.Free;
  end;
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
begin
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

      DoStatusChange('Loading attachment: ' + LFilePath);

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
      end);
  finally Params.Free; end;
end;

procedure TGeminiAgent.CancelPrompt(const SessionId: string);
var P: TJsonObject;
begin
  P := TACPProtocol.CreateSessionCancelParams(SessionId);
  try ACPClient.SendRaw('{"jsonrpc":"2.0","method":"session/cancel","params":' + P.ToJSON(False) + '}'); finally P.Free; end;
end;

procedure TGeminiAgent.ChangeModel(const SessionId, AModelId: string);
var P: TJsonObject;
begin
  P := TJsonObject.Create;
  try
    P.S['sessionId'] := SessionId; P.S['modelId'] := AModelId;
    ACPClient.Send('session/set_model', P, procedure(AResponse: TJsonObject)
      begin if Assigned(AResponse) and not AResponse.Contains('error') then DoStatusChange('Model changed to ' + AModelId + ' (Session: ' + SessionId + ')'); end);
  finally P.Free; end;
end;

function TGeminiAgent.IsReady: Boolean; begin Result := State = asReady; end;
procedure TGeminiAgent.DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin inherited; if Assigned(ErrorObj) and (ErrorObj.Count > 0) then DoStatusChange('ERR: ' + ErrorObj.ToJSON(True)); end;

procedure TGeminiAgent.Stop;
begin
  inherited;
end;

end.
