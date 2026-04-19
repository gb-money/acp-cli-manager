unit uSingleInstance;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes;

type
  TSingleInstance = class
  public
    // 이미 실행 중인 인스턴스가 있으면 URL을 전달하고 True 반환
    class function CheckAndRedirect: Boolean;
    // 메인 폼의 윈도우 핸들을 찾기 위한 고유 식별자
    const UNIQUE_ID = 'ACP_MULTI_AGENT_MANAGER_WINDOW';
  end;

implementation

{ TSingleInstance }

class function TSingleInstance.CheckAndRedirect: Boolean;
var
  H: HWND;
  Data: TCopyDataStruct;
  Cmd: string;
begin
  Result := False;
  // 1. 기존 윈도우 찾기 (캡션 또는 클래스명 기반)
  H := FindWindow('TfmxTS', nil); // FMX 폼의 기본 클래스명 패턴 (프로젝트 상황에 따라 조정 필요)
  
  // 만약 못 찾았다면 캡션으로 시도 (uMain.fmx의 Caption)
  if H = 0 then
    H := FindWindow(nil, 'ACP Multi-Agent Manager');

  if (H <> 0) and (H <> GetForegroundWindow) then
  begin
    // 2. 인자(URL)가 있는지 확인
    if ParamCount > 0 then
    begin
      Cmd := ParamStr(1);
      Data.dwData := 0;
      Data.cbData := (Length(Cmd) + 1) * SizeOf(Char);
      Data.lpData := PChar(Cmd);
      
      // 3. 기존 인스턴스에 데이터 전송
      SendMessage(H, WM_COPYDATA, 0, LPARAM(@Data));
      
      // 4. 기존 인스턴스를 앞으로 가져오기
      ShowWindow(H, SW_RESTORE);
      SetForegroundWindow(H);
    end;
    Result := True; // 이미 실행 중이므로 현재 프로세스 종료 필요
  end;
end;

end.
