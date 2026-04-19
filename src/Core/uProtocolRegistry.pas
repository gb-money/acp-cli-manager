unit uProtocolRegistry;

interface

uses
  System.Win.Registry, Winapi.Windows, System.SysUtils, System.IOUtils;

type
  TProtocolRegistry = class
  public
    class procedure RegisterSchema(const ASchema: string);
  end;

implementation

{ TProtocolRegistry }

class procedure TProtocolRegistry.RegisterSchema(const ASchema: string);
var
  Reg: TRegistry;
  ExePath: string;
begin
  ExePath := ParamStr(0);
  Reg := TRegistry.Create(KEY_WRITE OR KEY_READ);
  try
    Reg.RootKey := HKEY_CLASSES_ROOT;
    // 1. 프로토콜 기본 키 생성
    if Reg.OpenKey(ASchema, True) then
    begin
      Reg.WriteString('', 'URL:' + ASchema + ' Protocol');
      Reg.WriteString('URL Protocol', '');
      Reg.CloseKey;
    end;

    // 2. 아이콘 설정 (선택 사항)
    if Reg.OpenKey(ASchema + '\DefaultIcon', True) then
    begin
      Reg.WriteString('', ExePath + ',0');
      Reg.CloseKey;
    end;

    // 3. 실행 명령 등록
    if Reg.OpenKey(ASchema + '\shell\open\command', True) then
    begin
      // "%1"은 수신된 URL 전체를 인자로 전달함을 의미함
      Reg.WriteString('', '"' + ExePath + '" "%1"');
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

end.
