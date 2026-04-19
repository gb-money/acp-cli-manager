unit uGeminiAgent;

interface

uses
  System.Classes, System.SysUtils, JsonDataObjects, uAgent, uACPAgent, uACPClient, uACPProtocol;

type
  TModelsAvailableEvent = procedure(Sender: TObject; AModels: TStrings) of object;
  TSessionCreatedCallback = reference to procedure(const SessionId: string);

  TGeminiAgent = class(TACPAgent)
  private
    FAvailableModels: TStringList;
    FCurrentModelId: string;
    FOnModelsAvailable: TModelsAvailableEvent;

    procedure SendInitialize;
    procedure ExtractAvailableModels(Target: TJsonObject);
    procedure ExtractSessionMetadata(const SessionId: string; Target: TJsonObject);
  protected
    procedure DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    
    procedure Connect; override;
    procedure CreateNewSession(const ACwd: string; const APrompt: string = ''; OnSuccess: TSessionCreatedCallback = nil);
    procedure LoadSession(const SessionId: string; OnSuccess: TSessionCreatedCallback = nil);
    procedure SendPrompt(const SessionId, AText: string); override;
    procedure ChangeModel(const SessionId, AModelId: string);
    procedure CancelPrompt(const SessionId: string);
    
    function IsReady: Boolean;
    property CurrentModelId: string read FCurrentModelId;
    property AvailableModels: TStringList read FAvailableModels;
    property OnModelsAvailable: TModelsAvailableEvent read FOnModelsAvailable write FOnModelsAvailable;
  end;

implementation

{ TGeminiAgent }

constructor TGeminiAgent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AgentName := 'Gemini';
  FAvailableModels := TStringList.Create;
end;

destructor TGeminiAgent.Destroy;
begin
  FAvailableModels.Free;
  inherited;
end;

procedure TGeminiAgent.Connect;
begin
  inherited Connect;
  DoStatusChange('Starting Gemini process...');
  State := asConnecting;
  ACPClient.CommandLine := 'cmd /c gemini --acp';
  if ACPClient.Start then
    SendInitialize
  else
  begin
    DoStatusChange('ERR: Failed to start gemini process.');
    State := asError;
  end;
end;

procedure TGeminiAgent.SendInitialize;
var
  Params: TJsonObject;
begin
  DoStatusChange('Sending initialize request...');
  State := asInitializing;
  Params := TACPProtocol.CreateInitializeParams('acp-manager', '0.0.1');
  try
    ACPClient.Send('initialize', Params,
      procedure(Success: Boolean; ResultObj, ErrorObj: TJsonObject)
      begin
        if Success then
        begin
          DoStatusChange('Initialized successfully.');
          State := asReady;
        end
        else
        begin
          DoStatusChange('ERR: Initialization failed.');
          State := asError;
        end;
      end);
  finally
    Params.Free;
  end;
end;

procedure TGeminiAgent.ExtractSessionMetadata(const SessionId: string; Target: TJsonObject);
var
  Data: TSessionData;
  Changed: Boolean;
begin
  if not Assigned(Target) then Exit;
  
  if not Sessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);
    
  Changed := False;

  if Target.Contains('modes') then
  begin
    Data.ModesJson := Target.O['modes'].ToJSON(False);
    Changed := True;
  end;
  
  if Target.Contains('models') then
  begin
    Data.ModelsJson := Target.O['models'].ToJSON(False);
    Changed := True;
  end;

  if Target.Contains('availableCommands') then
  begin
    Data.CommandsJson := Target.A['availableCommands'].ToJSON(False);
    Changed := True;
  end;

  if Changed then
  begin
    Sessions.AddOrSetValue(SessionId, Data);
    ExtractAvailableModels(Target);
    
    if Assigned(OnSessionMetadataUpdate) then
      OnSessionMetadataUpdate(Self, SessionId);
  end;
end;

procedure TGeminiAgent.CreateNewSession(const ACwd: string; const APrompt: string; OnSuccess: TSessionCreatedCallback);
var
  Params: TJsonObject;
begin
  DoStatusChange('Creating Session...');
  Params := TACPProtocol.CreateSessionNewParams(ACwd, APrompt);
  try
    ACPClient.Send('session/new', Params,
      procedure(Success: Boolean; ResultObj, ErrorObj: TJsonObject)
      var
        NewSessionId: string;
      begin
        if Success and Assigned(ResultObj) then
        begin
          NewSessionId := ResultObj.S['sessionId'];
          if NewSessionId = '' then NewSessionId := ResultObj.S['session_id'];

          if NewSessionId <> '' then
          begin
            ExtractSessionMetadata(NewSessionId, ResultObj);
            DoStatusChange('Session Created: ' + NewSessionId);
            if Assigned(OnSuccess) then OnSuccess(NewSessionId);
          end
          else
            DoStatusChange('ERR: Session ID missing in response.');
        end
        else
        begin
          if Assigned(ErrorObj) then DoStatusChange('Session Failed: ' + ErrorObj.ToJSON(False))
          else DoStatusChange('Session Failed: Unknown error');
          if Assigned(OnSuccess) then OnSuccess('');
        end;
      end);
  finally
    Params.Free;
  end;
end;

procedure TGeminiAgent.LoadSession(const SessionId: string; OnSuccess: TSessionCreatedCallback);
var
  Params: TJsonObject;
begin
  DoStatusChange('Loading Session: ' + SessionId);
  Params := TJsonObject.Create;
  try
    Params.S['sessionId'] := SessionId;
    Params.S['cwd'] := Workspace;
    Params.A['mcpServers']; 
    
    ACPClient.Send('session/load', Params,
      procedure(Success: Boolean; ResultObj, ErrorObj: TJsonObject)
      begin
        if Success then
        begin
          ExtractSessionMetadata(SessionId, ResultObj);
          DoStatusChange('Session Loaded: ' + SessionId);
          State := asReady;
          if Assigned(OnSuccess) then OnSuccess(SessionId);
        end
        else
        begin
          DoStatusChange('Session Load Failed');
          State := asReady; 
          if Assigned(OnSuccess) then OnSuccess('');
        end;
      end);
  finally
    Params.Free;
  end;
end;

procedure TGeminiAgent.SendPrompt(const SessionId, AText: string);
var
  Data: TSessionData;
  Params: TJsonObject;
  PromptArr: TJsonArray;
begin
  if not Sessions.TryGetValue(SessionId, Data) then
    Data := Default(TSessionData);

  Data.FullThought := '';
  Data.FullMessage := '';
  Data.CurrentBlockText := '';
  Data.LastChunkType := '';
  Data.IsProcessing := True; 
  Sessions.AddOrSetValue(SessionId, Data);

  if AText.StartsWith('[') and AText.EndsWith(']') then
  begin
    PromptArr := TJsonArray.Parse(AText) as TJsonArray;
    try
      Params := TACPProtocol.CreateSessionPromptParams(SessionId, PromptArr);
    finally
      PromptArr.Free;
    end;
  end
  else
    Params := TACPProtocol.CreateSessionPromptParams(SessionId, AText);

  try
    ACPClient.Send('session/prompt', Params, 
      procedure(Success: Boolean; ResultObj, ErrorObj: TJsonObject)
      var
        LData: TSessionData;
        LStopReason: string;
      begin
        if Sessions.TryGetValue(SessionId, LData) then
        begin
          LData.IsProcessing := False; 
          Sessions.AddOrSetValue(SessionId, LData);
        end;

        if Success and Assigned(ResultObj) then
        begin
          LStopReason := ResultObj.S['stopReason'];
          if LStopReason = '' then LStopReason := 'end_turn';
          
          if Sessions.TryGetValue(SessionId, LData) then
            DoResponse(SessionId, LData.FullMessage + '||STOP:' + LStopReason);
        end;
      end);
  finally
    Params.Free;
  end;
end;

procedure TGeminiAgent.CancelPrompt(const SessionId: string);
var
  P: TJsonObject;
begin
  P := TACPProtocol.CreateSessionCancelParams(SessionId);
  try
    ACPClient.SendRaw('{"jsonrpc":"2.0","method":"session/cancel","params":' + P.ToJSON(False) + '}');
  finally
    P.Free;
  end;
end;

procedure TGeminiAgent.ChangeModel(const SessionId, AModelId: string);
var
  P, LModels: TJsonObject;
  LData: TSessionData;
begin
  if Sessions.TryGetValue(SessionId, LData) then
  begin
    if LData.ModelsJson <> '' then
    begin
      LModels := TJsonObject.Parse(LData.ModelsJson) as TJsonObject;
      try
        LModels.S['currentModelId'] := AModelId;
        LData.ModelsJson := LModels.ToJSON(False);
        Sessions.AddOrSetValue(SessionId, LData);
      finally
        LModels.Free;
      end;
    end;
  end;

  P := TJsonObject.Create;
  try
    P.S['sessionId'] := SessionId;
    P.S['modelId'] := AModelId;
    ACPClient.Send('session/set_model', P, 
      procedure(Success: Boolean; ResultObj, ErrorObj: TJsonObject)
      begin
        if Success then DoStatusChange('Model changed to ' + AModelId + ' (Session: ' + SessionId + ')');
      end);
  finally
    P.Free;
  end;
end;

procedure TGeminiAgent.ExtractAvailableModels(Target: TJsonObject);
var
  ModelsObj: TJsonObject;
  I: Integer;
begin
  if not Target.Contains('models') or (Target.O['models'] = nil) then Exit;
  
  ModelsObj := Target.O['models'];
  FCurrentModelId := ModelsObj.S['currentModelId'];
  
  if ModelsObj.Contains('availableModels') and (ModelsObj.A['availableModels'] <> nil) then
  begin
    FAvailableModels.Clear;
    for I := 0 to ModelsObj.A['availableModels'].Count - 1 do
    begin
      if ModelsObj.A['availableModels'].Items[I].Typ = jdtObject then
        FAvailableModels.Add(ModelsObj.A['availableModels'].O[I].S['modelId']);
    end;
    if Assigned(FOnModelsAvailable) then FOnModelsAvailable(Self, FAvailableModels);
  end;
end;

function TGeminiAgent.IsReady: Boolean;
begin
  Result := State = asReady;
end;

procedure TGeminiAgent.DoReceive(const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin
  inherited;
  if Assigned(ErrorObj) and (ErrorObj.Count > 0) then 
    DoStatusChange('ERR: ' + ErrorObj.ToJSON(True));
end;

end.
