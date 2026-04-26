# Agent Architecture & Session Lifecycle Refactoring (SOC v3)

이 문서는 레거시 세션 생성 함수 제거, 옵저버 패턴을 통한 UI 연동 강화, 그리고 비동기 초기화 로직의 안정성 개선 작업을 기록합니다.

## 1. 레거시 함수 제거 및 표준화 (Standardization)

- **CreateNewSession 제거**: `TACPAgent` 및 `TGeminiAgent`에서 사용되던 레거시 함수 `CreateNewSession`을 완전히 제거했습니다.
- **NewSession 표준화**: SOC v1/v2에서 도입된 `TACPAgent.NewSession`을 세션 생성을 위한 표준 메서드로 확립했습니다.
- **TGeminiAgent 오버라이드**: `TGeminiAgent`에서 `NewSession`을 오버라이드하여, 내부에 `EnsureReady`를 포함함으로써 "프로세스 실행 -> 초기화(initialize) -> 세션 생성(session/new)"으로 이어지는 비동기 체인을 단순화했습니다.

## 2. 옵저버 패턴을 통한 UI 결합도 해제 (Observer Pattern)

- **uAgentControl의 직접 구독**: 기존에는 `uGeminiAgentHandler`가 익명 콜백을 통해 세션 생성 후처리를 담당했으나, 이제 `uAgentControl`이 에이전트의 `OnNewSession` 이벤트를 직접 구독합니다.
- **DoAgentNewSession 구현**: `uAgentControl`에서 이벤트를 수신하여 Pending 세션을 Finalize하고 UI(채팅창, 파일 목록 등)를 갱신하는 로직을 중앙집중화했습니다.
- **핸들러 역할 축소**: `uGeminiAgentHandler`는 이제 단순히 요청을 전달하는 역할만 수행하며, 향후 완전 삭제를 위한 준비 단계를 마쳤습니다.

## 3. 비동기 안정성 및 버그 수정 (Robustness)

- **파라미터 클로닝 (Parameter Cloning)**: `EnsureReady`에 의해 `NewSession`이 비동기로 지연 실행될 때, 호출측에서 파라미터(`TJsonObject`)를 즉시 해제하여 발생하는 Access Violation 문제를 해결하기 위해 내부적으로 `Clone`을 수행하고 실행 완료 후 해제하도록 개선했습니다.
- **EnsureReady 로직 강화**: 에이전트의 상태(`State`)와 연결 여부(`IsConnected`)를 엄격히 체크하고, 초기화 실패 시 적절한 상태 메시지를 출력하도록 보완했습니다.
- **초기화 완료 조건 수정**: `TGeminiAgent.Initialize`의 응답 대기 조건을 `capabilities`에서 `authMethods` 포함 여부로 수정하여 최신 에이전트 스펙에 맞췄습니다.

## 4. 세션 관리자 기능 확장 (Session Manager)

- **GetPendingSessionByAgent**: 특정 에이전트가 생성 중인 임시 세션(ID가 `pending-`으로 시작하는 세션)을 찾기 위한 API를 `TSessionManager`에 추가했습니다. 이를 통해 비동기 응답 시 올바른 세션 객체를 찾아 ID를 교체할 수 있습니다.

## 5. 코드 정리 (Cleanup)

- **DoStateChange 삭제**: 레거시 메서드인 `DoStateChange`를 삭제하고, `TACPAgent.SetState`에서 직접 `OnStateChange` 이벤트를 발생시키도록 정리했습니다.
- **의존성 정리**: `uAgentControl` 및 핸들러에서 불필요한 참조를 줄이고 `uACPProtocol` 등을 적재적소에 배치했습니다.

## 6. 수정 파일 목록
- `src/Core/uSessionManager.pas`
- `src/Agents/uACPAgent.pas`
- `src/Agents/Gemini/uGeminiAgent.pas`
- `src/Agents/Gemini/uGeminiAgentHandler.pas`
- `src/UI/uAgentControl.pas`
- `docs/soc_v3.md` (신규)