unit uACPProtocol;

interface

uses
  System.Classes, System.SysUtils, JsonDataObjects;

type
  TACPProtocol = class
  public
    class function CreateInitializeParams(const ClientName, Version: string): TJsonObject;
    class function CreateSessionNewParams(const Cwd: string; const Prompt: string = ''): TJsonObject;
    class function CreateSessionPromptParams(const SessionId, Prompt: string): TJsonObject; overload;
    class function CreateSessionPromptParams(const SessionId: string; const PromptArray: TJsonArray): TJsonObject; overload;
    class function CreateSessionCancelParams(const SessionId: string): TJsonObject;
    class function CreateResponse(const ID: string; ResultObj: TJsonObject = nil): TJsonObject;
  end;

implementation

{ TACPProtocol }

class function TACPProtocol.CreateInitializeParams(const ClientName, Version: string): TJsonObject;
var
  Cap, FS, Auth, Meta, Info: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.I['protocolVersion'] := 1;
  
  Cap := Result.O['clientCapabilities'];
  FS := Cap.O['fs'];
  FS.B['readTextFile'] := True;
  FS.B['writeTextFile'] := True;
  Cap.B['terminal'] := True;
  
  Auth := Cap.O['auth'];
  Auth.B['terminal'] := True;
  
  Meta := Cap.O['_meta'];
  Meta.B['terminal_output'] := True;
  Meta.B['terminal-auth'] := True;
  
  Info := Result.O['clientInfo'];
  Info.S['name'] := ClientName;
  Info.S['title'] := ClientName;
  Info.S['version'] := Version;
end;

class function TACPProtocol.CreateSessionNewParams(const Cwd: string; const Prompt: string): TJsonObject;
var
  Parts: TJsonArray;
  Part: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['cwd'] := Cwd;
  Result.A['mcpServers'];
  
  if Prompt <> '' then
  begin
    Parts := Result.A['prompt'];
    Part := Parts.AddObject;
    Part.S['type'] := 'text';
    Part.S['text'] := Prompt;
  end;
end;

class function TACPProtocol.CreateSessionPromptParams(const SessionId, Prompt: string): TJsonObject;
var
  Parts: TJsonArray;
  Part: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['sessionId'] := SessionId;
  
  Parts := Result.A['prompt'];
  Part := Parts.AddObject;
  Part.S['type'] := 'text';
  Part.S['text'] := Prompt;
end;

class function TACPProtocol.CreateSessionPromptParams(const SessionId: string;
  const PromptArray: TJsonArray): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['sessionId'] := SessionId;
  Result.A['prompt'].Assign(PromptArray);
end;

class function TACPProtocol.CreateSessionCancelParams(const SessionId: string): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['sessionId'] := SessionId;
end;

class function TACPProtocol.CreateResponse(const ID: string; ResultObj: TJsonObject): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['jsonrpc'] := '2.0';
  if ID <> '' then
  begin
    if (Length(ID) > 0) and (ID[1] in ['0'..'9']) then
      Result.I['id'] := StrToIntDef(ID, 0)
    else
      Result.S['id'] := ID;
  end;
  
  if Assigned(ResultObj) then
    Result.O['result'].Assign(ResultObj)
  else
    Result.O['result'];
end;

end.
