unit uWebACPCommandHandler;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.NetEncoding;

type
  // 파라미터를 값 복사하여 안전하게 전달하기 위해 TDictionary를 로컬에서 생성하여 전달함
  TACPCommandEvent = procedure(Sender: TObject; const Action: string; const Params: TDictionary<string, string>) of object;
  TACPLogEvent = procedure(Sender: TObject; const LogMsg: string) of object;

  TWebACPCommandHandler = class
  private
    FOnCommand: TACPCommandEvent;
    FOnLog: TACPLogEvent;
  public
    constructor Create;
    destructor Destroy; override;
    function HandleUrl(const AUrl: string): Boolean;
    property OnCommand: TACPCommandEvent read FOnCommand write FOnCommand;
    property OnLog: TACPLogEvent read FOnLog write FOnLog;
  end;

implementation

{ TWebACPCommandHandler }

constructor TWebACPCommandHandler.Create;
begin
  inherited;
end;

destructor TWebACPCommandHandler.Destroy;
begin
  inherited;
end;

function TWebACPCommandHandler.HandleUrl(const AUrl: string): Boolean;
const
  SCHEMA = 'acp-action://';
var
  LRaw, LAction, LParamStr, LPair: string;
  LQuery: TStringList;
  I, LPos: Integer;
  LParams: TDictionary<string, string>;
begin
  Result := False;
  if not AUrl.ToLower.StartsWith(SCHEMA) then Exit;

  if Assigned(FOnLog) then
    FOnLog(Self, '[ACP-ACTION] Incoming: ' + AUrl);

  LRaw := AUrl.Substring(SCHEMA.Length);
  LPos := LRaw.IndexOf('?');
  
  if LPos >= 0 then
  begin
    LAction := LRaw.Substring(0, LPos);
    LParamStr := LRaw.Substring(LPos + 1);
  end
  else
  begin
    LAction := LRaw;
    LParamStr := '';
  end;

  LParams := TDictionary<string, string>.Create;
  try
    if LParamStr <> '' then
    begin
      LQuery := TStringList.Create;
      try
        LQuery.Delimiter := '&';
        LQuery.StrictDelimiter := True;
        LQuery.DelimitedText := LParamStr;
        for I := 0 to LQuery.Count - 1 do
        begin
          LPair := LQuery[I];
          LPos := LPair.IndexOf('=');
          if LPos >= 0 then
            LParams.AddOrSetValue(LPair.Substring(0, LPos), 
                                  TNetEncoding.URL.Decode(LPair.Substring(LPos + 1)))
          else
            LParams.AddOrSetValue(LPair, '');
        end;
      finally
        LQuery.Free;
      end;
    end;

    // 동기적 실행: 이벤트 핸들러가 끝날 때까지 LParams는 유효함
    if Assigned(FOnCommand) then
      FOnCommand(Self, LAction, LParams);
      
    Result := True;
  finally
    LParams.Free;
  end;
end;

end.
