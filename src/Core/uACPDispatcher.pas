unit uACPDispatcher;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections, JsonDataObjects,
  uACPClient, uAgentTypes;

type
  TACPDispatcher = class
  private
    FClient: TACPClient;
    FOnRawData: TACPRawDataEvent;
    FOnReceive: TACPReceiveEvent;
    FOnTerminated: TACPProcessTerminatedEvent;
    
    procedure HandleClientRawData(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
    procedure HandleClientReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
    procedure HandleClientTerminated(Sender: TObject; ExitCode: Cardinal);
    function GetIsRunning: Boolean;
    function GetCommandLine: string;
    procedure SetCommandLine(const Value: string);
  public
    constructor Create(AClient: TACPClient);
    destructor Destroy; override;

    function Start: Boolean;
    procedure Stop;

    procedure Send(const Method: string; Params: TJsonObject = nil; 
      OnResponse: TACPResponseAnonCallback = nil; 
      OnConditions: TArray<TACPResponseCondition> = nil; 
      const SessionId: string = '');
    procedure SendResponse(const ID: string; ResultObj: TJsonObject = nil);
    procedure SendRaw(const JsonStr: string);

    // Lifecycle specialized helpers
    procedure InitializeAgent(const AgentName, Version: string; OnReady: TProc<Boolean>);
    procedure CreateSession(const Cwd: string; OnCreated: TProc<string, TJsonObject>);
    procedure LoadSession(const SessionId, Cwd: string; OnLoaded: TProc<Boolean>);

    property IsRunning: Boolean read GetIsRunning;
    property CommandLine: string read GetCommandLine write SetCommandLine;

    property OnRawData: TACPRawDataEvent read FOnRawData write FOnRawData;
    property OnReceive: TACPReceiveEvent read FOnReceive write FOnReceive;
    property OnTerminated: TACPProcessTerminatedEvent read FOnTerminated write FOnTerminated;
  end;

implementation

uses
  uACPProtocol;

{ TACPDispatcher }

constructor TACPDispatcher.Create(AClient: TACPClient);
begin
  FClient := AClient;
  FClient.OnRawData := HandleClientRawData;
  FClient.OnReceive := HandleClientReceive;
  FClient.OnTerminated := HandleClientTerminated;
end;

destructor TACPDispatcher.Destroy;
begin
  inherited;
end;

function TACPDispatcher.GetCommandLine: string;
begin
  Result := FClient.CommandLine;
end;

function TACPDispatcher.GetIsRunning: Boolean;
begin
  Result := FClient.IsRunning;
end;

procedure TACPDispatcher.HandleClientRawData(Sender: TObject; Direction: TRPCDirection; const ASessionId: string; AObj: TJsonObject; const RawText: string);
begin
  if Assigned(FOnRawData) then FOnRawData(Sender, Direction, ASessionId, AObj, RawText);
end;

procedure TACPDispatcher.HandleClientReceive(Sender: TObject; const ID, Method: string; Params, ResultObj, ErrorObj: TJsonObject);
begin
  if Assigned(FOnReceive) then FOnReceive(Sender, ID, Method, Params, ResultObj, ErrorObj);
end;

procedure TACPDispatcher.HandleClientTerminated(Sender: TObject; ExitCode: Cardinal);
begin
  if Assigned(FOnTerminated) then FOnTerminated(Sender, ExitCode);
end;

procedure TACPDispatcher.Send(const Method: string; Params: TJsonObject; OnResponse: TACPResponseAnonCallback; OnConditions: TArray<TACPResponseCondition>; const SessionId: string);
begin
  FClient.Send(Method, Params, OnResponse, OnConditions, SessionId);
end;

procedure TACPDispatcher.SendResponse(const ID: string; ResultObj: TJsonObject);
begin
  FClient.SendResponse(ID, ResultObj);
end;

procedure TACPDispatcher.SendRaw(const JsonStr: string);
begin
  FClient.SendRaw(JsonStr);
end;

procedure TACPDispatcher.SetCommandLine(const Value: string);
begin
  FClient.CommandLine := Value;
end;

function TACPDispatcher.Start: Boolean;
begin
  Result := FClient.Start;
end;

procedure TACPDispatcher.Stop;
begin
  FClient.Stop;
end;

procedure TACPDispatcher.InitializeAgent(const AgentName, Version: string; OnReady: TProc<Boolean>);
var
  LParams: TJsonObject;
begin
  LParams := TACPProtocol.CreateInitializeParams(AgentName, Version);
  try
    Send('initialize', LParams,
      procedure(AResponse: TJsonObject)
      begin
        if Assigned(OnReady) then
          OnReady(Assigned(AResponse) and not AResponse.Contains('error'));
      end,
      [
        function(AResponse: TJsonObject): Boolean
        begin
          Result := Assigned(AResponse) and AResponse.Contains('result') and AResponse.O['result'].Contains('authMethods');
        end
      ]);
  finally
    LParams.Free;
  end;
end;

procedure TACPDispatcher.CreateSession(const Cwd: string; OnCreated: TProc<string, TJsonObject>);
var
  LParams: TJsonObject;
  LCapturedSid: string;
  LFirstResponse: TJsonObject;
begin
  LCapturedSid := '';
  LFirstResponse := nil;
  LParams := TACPProtocol.CreateSessionNewParams(Cwd, '');
  
  Send('session/new', LParams,
    procedure(AFinalUpdate: TJsonObject)
    begin
      try
        if Assigned(LFirstResponse) and Assigned(OnCreated) then
          OnCreated(LCapturedSid, LFirstResponse);
      finally
        if Assigned(LFirstResponse) then LFirstResponse.Free;
      end;
    end,
    [
      function(AObj: TJsonObject): Boolean
      begin
        Result := Assigned(AObj) and AObj.Contains('result') and AObj.O['result'].Contains('sessionId');
        if Result then
        begin
          LCapturedSid := AObj.O['result'].S['sessionId'];
          LFirstResponse := AObj.Clone as TJsonObject;
        end;
      end,
      function(AObj: TJsonObject): Boolean
      begin
        Result := Assigned(AObj) and 
                  (AObj.S['id'] = '') and 
                  (AObj.S['method'] = 'session/update') and 
                  (AObj.O['params'].S['sessionId'] = LCapturedSid);
      end
    ]
  );
  LParams.Free;
end;

procedure TACPDispatcher.LoadSession(const SessionId, Cwd: string; OnLoaded: TProc<Boolean>);
var
  LParams: TJsonObject;
begin
  LParams := TJsonObject.Create;
  LParams.S['sessionId'] := SessionId;
  LParams.S['cwd'] := Cwd;
  LParams.A['mcpServers'];

  Send('session/load', LParams,
    procedure(AResponse: TJsonObject)
    begin
      if Assigned(OnLoaded) then
        OnLoaded(Assigned(AResponse) and not AResponse.Contains('error'));
    end,
    [
      function(AObj: TJsonObject): Boolean
      begin
        Result := Assigned(AObj) and AObj.Contains('result') and AObj.O['result'].Contains('sessionId') and
                  SameText(AObj.O['result'].S['sessionId'], SessionId);
      end,
      function(AObj: TJsonObject): Boolean
      begin
        Result := Assigned(AObj) and 
                  (AObj.S['id'] = '') and 
                  (AObj.S['method'] = 'session/update') and 
                  (AObj.O['params'].S['sessionId'] = SessionId) and
                  (AObj.O['params'].O['update'].S['sessionUpdate'] = 'available_commands_update');
      end
    ],
    SessionId
  );
  LParams.Free;
end;

end.
