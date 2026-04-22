코드 리팩토링을 위한 준비를 해야해.

# 1. 관심사 분리 진행

Delphi <-> WebBrowser 간 통신은 필연적으로 비동기일 수 밖에 없음.

Delphi의 src/UI/u~~~Control.pas 는 WebBrowser에서 넘어오는 이벤트를 델파이로 넘기고, 델파이에서 WebBrowser JS를 호출함.

현재 이 계층이 올바르게 되어있지 않아 Rade Condition 등 여러 문제가 발생하는 중.

## 1 - 1. Delphi 유닛 별 역할 파악

- uACPClient.pas : ACP 를 연결하고 rpc 데이터를 Send/Recv 하는 전용 윈도우
  - 특징
    - Send 에 Callback을 구성하여 결과에 따른 개별 동작을 구현함.

- uACPAgent.pas : ACP로 연결되는 cli Agent의 조상 클래스
- uACPAgentHandler.pas : ACP에서 넘어오는 rpc를 처리하는 비즈니스 로직 구현체
- uGeminiAgent.pas : Gemini cli에서 넘어오는 rpc를 처리하는 비즈니스 로직 구현체
- uGeminiAgentHandler.pas : Gemini Agent와 용도가 중복되는 중. => 사실상 uGeminiAgent로 통합되거나, 용도 분리가 필요함.

## 1 - 2. rpc 흐름도

최초로 acp 연결을 진행하는 initialize부터, 대화를 주고받는 session/prompt, session/update를 정리함.

1. initialize
  - WebBrowser에서 sendAcp('new-chat?agent=에이전트명')
  - Delphi의 uMain.pas에서 WebBrowserMainShouldStartLoadWithRequest 프로시저에서 처리 시작
  - AgentControl 유닛이 AgentType에 맞는 Agent를 반환받아 연결 시도

이하 흐름은 모두 동일함. 즉

- AgentControl 에서 이벤트를 받아서, Agent에게 전달.
- Agent 는 ACPClient 로 rpc를 전달하고 응답을 받음.
- ACPClient 는 응답에 따라 정해진 Callback을 호출
- Callback에서 적절한 조치(파일 저장, UI 업데이트 요청 등) 수행.

## 1 - 3. 현재 문제점

- TSessionInfo 에는 IsRestoring 이라는 플래그가 존재함.
- session/load 요청 전 True로 설정 후 session/update (available_commands_update)를 받으면 False로 풀어줌
- 이 과정에서 agent_message_chunk, agent_thought_chunk 등의 데이터가 채팅창 UI를 업데이트해서는 안됨.
- uAgent는 ACPClient를 가지고있어야 하고, AgentControl은 uAgent를 가지고 있어야함. 



AgentControl이 웹에서 받은 이벤트를 처리할때
- acp-action://{command_name} 을 보고 command_name에 맞는 Handle~~~ 함수 호출
- {resume-session?id=SESSION_UUID} 라면? 해당 sessionId를 가진 TAgent를 찾아야함.
- TAgent의 타입에 따른 알맞은 클래스로 캐스팅 (if Agent.Type = atGemini then TGeminiAgent(Agent).ResumeSession(AsessionId))
- TGeminiAgent.ResumeSession 에서는 ACPClient 프로퍼티로 세션을 복구하는 rpc를 날림. (session/load)
- 복구중임을 알리기 위해 UI 업데이트를 해야함.
- TGeminiAgent가 다시 AgentControl.StartResumeSession(ASessionId) 함수를 호출함



index.html에서 gemini-cli로 세션을 생성할때, 폴더를 선택한 다음에 initialize를 호출하는 흐름
1. gemini cli가 켜져있는지 확인 (TGeminiAgent.IsReady)
2. 켜져있지 않다면 프로세스 실행 (TGeminiAgent.Start) 
  - 여기서 ACPClient.CommandLine 설정 후 inherited Start로 ACPAgent.Start 처리
  - ACPAgent.Start 에서는 ACPClient.Start 처리


여기서 문제가 있는데, TGeminiAgent.Start 에서 ACPClient에 다이렉트로 접근함.
이는 올바른 참조 구성이 아님.

ACPAgent.Start 에 (ACommandLine: string) 파라미터를 추가하고
TGeminiAgent.Start => inherited Start('cmd /c gemini --acp')
ACPAgent는 ACPClient 프로퍼티가 있으니, ACPAgent.Start로 넘어온 파라미터를 ACPClient.CommandLine로 설정하고 ACPClient.Start 호출

이 흐름에 대해 어떻게 생각해?

만약 수정한다면, 추가적으로 
ACPAgent에서 private인 FACPClient를 사용중인 코드를 ACPClient를 프로퍼티로 접근하도록 고쳐야해.

====================================================

uAgent는 더이상 사용되지 않는 유닛이 될 예정.

ACPAgent가 추상 클래스가 될 것.

TGeminiAgent에서 처리하는 비즈니스 로직은
TGeminiAgent => TACPAgent => TACPAgent.ACPClient 프로퍼티를 통해 rpc를 보낼 것.

TGeminiAgent.NewSession (session/new 를 호출하기 위한 프로시저임)이 동작하려면?

필요한 추가 함수 : `TGeminiAgent.Initialize`
- ACPAgent.Initialize(Param: TJsonObject) 추가
- TGeminiAgent.Initialize(Param: TJsonObject) 추가

- Checklist
  - TGeminiAgent가 켜져있는지 확인하고, 아니라면 프로세스 실행.
  - 프로세스가 켜져있다면, initialize 되었는지 확인. 아니라면 TGeminiAgent.Initialize() 호출.
  - initialize까지 완료했다면, session/new rpc를 호출해야함.

- 작업 흐름도
  - TGeminiAgent.IsReady 확인 (프로세스 실행 여부)
  - False라면 TGeminiAgent.Start(); (여기서 내부적으로 ACPClient까지 넘어가서 프로세스 실행)
  - Start 이후에 initialize까지 진행. (TGeminiAgent.Initialize)
  - session/new 를 위한 TGeminiAgent.CreateSessionNewParam 만들기
  - TGeminiAgent 프로퍼티 ACPAgent를 사용해서 ACPAgent.NewSession(Param: TJsonObject) 호출하기
  - ACPAgent.NewSession에서는 ACPClient.Send('session/new', Param) 호출.

- session/new 에 대한 콜백을 받아서 TGeminiAgent까지 가려면?
  - 옵저버 패턴으로 ACPAgent에 OnNewSession을 만들고, ACPClient.Send('session/new', Param, procedure(Result: TJsonObject)
  begin
    if Assigned(FOnNewSession) then
      FOnNewSession(Result);
  end;)

ACPClient.ProcessBuffer 를 분석해야함.
- 한줄의 json rpc가 완성되면, json 파싱 진행
- 지금은 Send에서 만든 id 기반 Callback을 처리중인데, 이는 문제가 있음
- id는 고유하지 않음. 다른 method 호출과 id가 겹칠 수 있음.
- Send에서 처리한 rpc method를 기억하고, 일치하는 id를 받았을때, 특정 내용이 담긴 json이어야 callback 실행하는 형태로 변경 필요.
=> Send 프로시저에 CallbackCondition을 추가함. 

ACPAgent에서 ACPClient.Send를 처리하고있음.
ACPAgent.NewSession 프로시저에서 AParam만 받고있는데, 여기에 Condition, Callback을 넣고
GeminiAgent.NewSession 프로시저에서 Param, Condition, Callback을 넘겨주면?
==> OK 받음

session/new 의 Condition은?
=> 동일한 id를 가졌고, result에 sessionId를 가지고 있으면 OK

{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "sessionId": "a00e25fa-91d3-4d46-8bbf-821e21a99208",
    "modes": {
      "availableModes": [
        {
          "id": "default",
          "name": "Default",
          "description": "Prompts for approval"
        },
        {
          "id": "autoEdit",
          "name": "Auto Edit",
          "description": "Auto-approves edit tools"
        },
        {
          "id": "yolo",
          "name": "YOLO",
          "description": "Auto-approves all tools"
        },
        {
          "id": "plan",
          "name": "Plan",
          "description": "Read-only mode"
        }
      ],
      "currentModeId": "default"
    },
    "models": {
      "availableModels": [
        {
          "modelId": "auto-gemini-3",
          "name": "Auto (Gemini 3)",
          "description": "Let Gemini CLI decide the best model for the task: gemini-3.1-pro, gemini-3-flash"
        },
        {
          "modelId": "auto-gemini-2.5",
          "name": "Auto (Gemini 2.5)",
          "description": "Let Gemini CLI decide the best model for the task: gemini-2.5-pro, gemini-2.5-flash"
        },
        {
          "modelId": "gemini-3.1-pro-preview",
          "name": "gemini-3.1-pro-preview"
        },
        {
          "modelId": "gemini-3-flash-preview",
          "name": "gemini-3-flash-preview"
        },
        {
          "modelId": "gemini-3.1-flash-lite-preview",
          "name": "gemini-3.1-flash-lite-preview"
        },
        {
          "modelId": "gemini-2.5-pro",
          "name": "gemini-2.5-pro"
        },
        {
          "modelId": "gemini-2.5-flash",
          "name": "gemini-2.5-flash"
        },
        {
          "modelId": "gemini-2.5-flash-lite",
          "name": "gemini-2.5-flash-lite"
        }
      ],
      "currentModelId": "auto-gemini-3"
    }
  }
}

session/new 또는 session/load 일때 위 json이 넘어옴.

new든 load든 modes와 models를 다 가져와서 해당 에이전트 객체에 업데이트하는 구조가 필요한데..

1. TGeminiAgent.OnUpdateMode, OnUpdateModel 콜백을 만든다.
  - ACPClient의 DoReceive가 ACPAgent => GeminiAgent까지 넘어올 수 있는가?



이제 ResumeSession을 구현해야함.
TGeminiAgent.ResumeSession(ASessionId: string)
- TSessionInfo.IsRestoring = True 설정
- ACPAgent.ResumeSession(ASessionId, Condition, Callback) 호출
  - Condition : params.update.sessionUpdate == 'available_commands_update' 일때
  - Callback : TSessionInfo.IsRestoring = False 처리 후 UI 갱신 (UI 갱신을 옵저버 패턴으로 할 수 있는가?)


session/prompt 의 콜백을 구성 완료했음. 콜백 컨디션 조건에 맞는 json을 받으면 UI까지 활성화가 잘 됨.
이제 그 중간에 들어오는 응답을 잘 처리해야함.
먼저, 에이전트의 응답은 다음 구조를 가지고 있음

1. method: "fs/~~~~~" 로 들어오는 경우
  - fs/read_text_file : 파일 읽기를 요청함. 같은 id, method를 사용하여 params.content 에 파일의 풀 텍스트를 응답해야함.
  - fs/write_text_file : 파일 쓰기를 요청함. params.path에 파일의 전체경로, params.content 에 업데이트해야할 내용이 넘어옴
    - 이 경우 프로그램이 직접 파일 쓰기를 하고, 쓰기가 완료되면 같은 id, method를 사용하고, 비어있는 params 오브젝트와 함께 응답해야함.   

2. method: "session/update" 로 들어오는 경우
  이 타입은 다시 타입에 따라 나눠서 처리해야함.
   - agent_message_chunk : 대답이 생성되는 중 (실시간으로 텍스트를 쌓음)
   - agent_thought_chunk : 생각과정이 생성되는 중 (실시간으로 텍스트를 쌓음)
  
3. method: "session/tool_call" 로 들어오는 경우
   - 

4. method: "session/request_permission" 로 들어오는 경우
  - params.toolCall.kind : 'edit' or 'other'
    - 'edit' : 윈도우에서 파일 쓰기 전 권한을 요청함. 사용자가 승인하면 fs/write_text_file 이 넘어올 것임
      - 이때 params.toolCall.content 배열이 있는데, type: diff, path: 파일경로, oldText: 변경전 텍스트, newText: 변경후 텍스트 가 넘어옴
    - 'other' : MCP 사용 등 기타 권한을 요청함.
  - params.toolCall.options : 사용자가 할 수 있는 행동 목록이 들어옴
    - ShowRequestPermission 에 options를 담아서 UI를 업데이트 해야함.
  - 동일한 id, method로 응답하며, params.outcome.outcome, params.outcome.optionId (toolCalls.options 에 있는 optionId와 일치하게)
    - 이때 특이 사항은 아래 내용을 참고.
        If the current prompt turn gets cancelled, the Client MUST respond with the "cancelled" outcome:
        {
        "jsonrpc": "2.0",
        "id": 5,
        "result": {
            "outcome": {
            "outcome": "cancelled"
            }
        }
        }
        ​
        outcome : The user’s decision, either: 
          - cancelled - The prompt turn was cancelled


[10:57:59] IN: {"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"sessionId":"009253a7-9f08-43f4-a7bd-fe3747176136","options":[{"optionId":"proceed_always_server","name":"Allow all server tools for this session","kind":"allow_always"},{"optionId":"proceed_always_tool","name":"Allow tool for this session","kind":"allow_always"},{"optionId":"proceed_once","name":"Allow","kind":"allow_once"},{"optionId":"cancel","name":"Reject","kind":"reject_once"}],"toolCall":{"toolCallId":"mcp_sequential-thinking_sequentialthinking-1776823079855-1","status":"pending","title":"sequentialthinking (sequential-thinking MCP Server)","content":[],"locations":[],"kind":"other"}}}