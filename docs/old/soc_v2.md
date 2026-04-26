# Agent Architecture & Session Lifecycle Refactoring (SOC v2)

이 문서는 비동기 RPC 콜백의 정확성 개선, 세션 메타데이터 동기화 자동화, 그리고 세션 복구(Resume) 흐름의 옵저버 패턴 도입을 포함한 리팩토링 작업(v2)을 기록합니다.

## 1. 비동기 RPC 콜백 시스템 개선 (Callback Condition)

기존 ID 기반 콜백 매칭의 한계(ID 중복 및 스트리밍 응답 매칭 오류)를 해결하기 위해 익명 함수 기반의 조건 검증 시스템을 도입했습니다.

- **Storage 변경**: `TDictionary`에서 `TList<TACPRequestRecord>` 구조로 변경하여 동일 ID 요청이 누적되더라도 안전하게 처리.
- **TACPResponseCondition 도입**: 
    - `reference to function(AResponse: TJsonObject): Boolean` 타입을 통해 응답 JSON의 유효성을 자식 클래스에서 정의.
    - `Condition`이 `True`를 반환할 때까지 콜백을 실행하지 않고 대기함으로써 스트리밍 응답(예: `session/prompt`)의 최종 완료 시점을 정확히 포착.
- **안전장치**: RPC 에러(`error` 필드 존재) 수신 시에는 조건을 무시하고 즉시 콜백을 실행하여 예외 처리 보장.

## 2. 세션 생성 및 로드 시그니처 확장

부모 클래스(`TACPAgent`)가 공통 흐름을 제어하고, 자식 클래스가 에이전트 특화 로직을 주입할 수 있도록 개선했습니다.

- **TACPAgent.NewSession 확장**:
    - `OnResponse`, `OnCondition` 파라미터 추가.
    - 실행 순서: `DoNewSession`(자식 오버라이드) -> `OnResponse`(주입된 콜백) -> `OnNewSession`(외부 옵저버).
- **식별자 표준화**: 모든 곳에서 `session_id` 폴백을 제거하고 `sessionId`로 필드명 통일.

## 3. 메타데이터 동기화 자동화 (Metadata Auto-Sync)

세션 상태(모드, 모델) 정보를 에이전트 객체와 동기화하는 로직을 부모 클래스로 중앙집중화했습니다.

- **TACPAgent.DoReceive 개선**:
    - `session/new` 및 `session/load` 응답 수신 시, `modes`와 `models` 객체가 포함되어 있다면 자동으로 `HandleModes`, `HandleModels` 호출.
    - 자식 클래스(`TGeminiAgent`)에서 중복되던 파싱 및 업데이트 로직 제거.

## 4. 세션 복구 흐름 및 옵저버 패턴 (Resume Session)

비동기 알림(Notification) 기반의 세션 복구 완료 처리를 위해 옵저버 패턴을 도입했습니다.

- **ResumeSession(SessionId)**:
    - 에이전트 상태를 `IsRestoring := True`로 설정하고 서버에 복구 요청(`session/load`) 전송.
- **TSessionResumedEvent**:
    - 서버로부터 `available_commands_update` 알림을 받았을 때, 복구 모드인 경우 이를 감지하여 `IsRestoring := False` 처리 및 `OnSessionResumed` 이벤트 발생.
    - UI 레이어는 이 이벤트를 구독하여 복구 완료 시점(모든 데이터 로드 완료)에 화면을 갱신.

## 5. 수정 파일 목록
- **src/Core/uAgentTypes.pas**: `TSessionResumedEvent` 정의 추가.
- **src/ACP/uACPClient.pas**: `TList` 기반 콜백 저장소 및 `Condition` 검증 로직 구현.
- **src/Agents/uACPAgent.pas**: `NewSession`, `ResumeSession`, `DoReceive` 로직 대폭 강화 및 옵저버 프로퍼티 추가.
- **src/Agents/Gemini/uGeminiAgent.pas**: 새로운 콜백/조건 구조에 맞춰 모든 `ACPClient.Send` 호출부 갱신 및 중복 로직 정리.
