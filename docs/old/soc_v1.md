# Agent Architecture & Session Lifecycle Refactoring (SOC v1)

이 문서는 에이전트 구조의 단순화, 캡슐화 강화, 그리고 비동기 세션 생성 흐름 개선을 위해 진행된 리팩토링 작업(v1)을 기록합니다.

## 1. 클래스 계층 구조 변경 (Class Hierarchy)

- **uAgent.pas 제거**: 최상위 추상 클래스였던 `TAgent`를 제거하고 기능을 `TACPAgent`로 통합했습니다.
- **TACPAgent 격상**: `TACPAgent`가 이제 `TComponent`를 직접 상속받는 최상위 에이전트 베이스 클래스가 되었습니다.
- **타입 통합**: 
    - `TAgentState`, `TAgentStatusChangeEvent` 등 공통 타입 -> `uAgentTypes.pas`로 이동.
    - `TSessionInfo` -> `uACPAgent.pas`로 이동하여 에이전트와의 결합도 최적화.

## 2. 캡슐화 및 참조 개선 (Encapsulation)

### 2.1 Start 메서드 리팩토링
- **As-Is**: 자식 클래스(`TGeminiAgent`)가 부모의 `FACPClient.CommandLine`에 직접 접근.
- **To-Be**: `TACPAgent.Start(const ACommandLine: string)` 파라미터를 통해 명령어를 전달받아 부모 내부에서 처리.

### 2.2 순환 참조 해결 (Circular Reference)
- `uACPAgent` <-> `uSessionManager` 간의 참조 고리를 끊기 위해 `uACPAgent` 인터페이스 섹션에서 `uSessionManager` 참조를 제거했습니다.
- `FSessionMgr` 필드를 `TObject`로 선언하고 `implementation` 섹션에서 타입 캐스팅하여 사용합니다.

## 3. 세션 생성 흐름 개선 (Session Lifecycle)

### 3.1 옵저버 패턴 도입 (Observer Pattern)
- `session/new` 호출 결과를 처리하기 위해 `TACPAgent`에 다음 구조를 도입했습니다.
    - `procedure NewSession(Params: TJsonObject)`: RPC 요청 송신.
    - `procedure DoNewSession(AResponse: TJsonObject) virtual`: 자식 클래스 오버라이드 지점.
    - `property OnNewSession: TNewSessionEvent`: 외부 UI 레이어 통지용.

### 3.2 EnsureReady 로직
- `TGeminiAgent` 내부에 `EnsureReady` 헬퍼를 추가하여 프로세스가 켜져있는지, 초기화(`initialize`)가 완료되었는지를 자동으로 체크하고 비동기적으로 다음 단계를 실행합니다.

## 4. 관련 유닛 업데이트 사항

- **uGeminiAgent.pas**: 새로운 비동기 흐름에 맞춰 `Initialize` 및 `CreateNewSession` 재구현.
- **uGeminiAgentHandler.pas**: 상태 체크 로직을 에이전트로 위임하여 비즈니스 로직 단순화.
- **uAgentControl.pas / uMain.pas**: `TAgent` 참조를 `TACPAgent`로 일괄 업데이트.
- **uSessionManager.pas**: `TComparer` 및 `CompareDateTime` 사용을 위한 유닛 참조 추가.

## 5. 삭제 및 수정 파일 목록
- **삭제**: `src/Agents/uAgent.pas`
- **수정**:
    - `src/Core/uAgentTypes.pas`
    - `src/Agents/uACPAgent.pas`
    - `src/Agents/Gemini/uGeminiAgent.pas`
    - `src/Agents/Gemini/uGeminiAgentHandler.pas`
    - `src/Agents/uAgentHandler.pas`
    - `src/Core/uSessionManager.pas`
    - `src/Core/uConversationService.pas`
    - `src/UI/uAgentControl.pas`
    - `uMain.pas`
