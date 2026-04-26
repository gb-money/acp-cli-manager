# Agent Architecture & Session Lifecycle Refactoring (SOC v5)

이 문서는 `session/prompt` 라이프사이클의 에이전트 레이어 캡슐화, 상태 관리(`IsWaitForResponse`)의 자동화, 그리고 UI 레이어와의 결합도 해제 작업을 기록합니다.

## 1. session/prompt 상태 관리 캡슐화 (Encapsulation)

기존에 UI 레이어(`TAgentControl`)에서 수동으로 관리하던 세션의 응답 대기 상태(`IsWaitForResponse`)를 에이전트 레이어 내부로 이동시켰습니다.

- **TGeminiAgent.SendPrompt 개선**:
    - 프롬프트 전송 직전 `TSessionInfo`를 검색하여 `IsWaitForResponse := True`를 설정.
    - `OnSessionMetadataUpdate` 이벤트를 발생시켜 UI가 상태 변화를 즉시 반영하도록 구현.
- **TGeminiAgent.CancelPrompt 개선**:
    - 프롬프트 취소 시에도 `IsWaitForResponse := False` 처리 및 메타데이터 업데이트 이벤트를 발생시켜 UI 상태 동기화.
- **자동 해제 (Auto-Reset)**:
    - RPC 콜백 내에서 호출되는 `EndTurn` 메서드가 이미 `IsWaitForResponse := False`와 `UpdateSession` 호출을 포함하고 있으므로, 별도의 추가 로직 없이 응답 완료 시 상태가 자동으로 해제됨.

## 2. UI 레이어 결합도 해제 (Decoupling)

UI 레이어는 이제 에이전트의 내부 상태를 직접 수정하지 않고, 에이전트가 발행하는 이벤트를 구독하여 화면을 갱신하는 리액티브 구조를 갖게 되었습니다.

- **TAgentControl.HandleSendMessage**:
    - `LActive.IsWaitForResponse := True` 및 `UpdateSession` 호출 코드를 삭제.
    - **레거시 핸들러(`TAgentHandler`) 의존성 제거**: 핸들러를 조회하여 프롬프트를 전달하던 분기 로직을 삭제하고, 에이전트의 `SendPrompt`를 직접 호출하도록 간소화했습니다.
    - 에이전트의 `SendPrompt` 호출만 담당하며, 이후의 UI 변화는 `DoAgentSessionMetadataUpdate` 및 `DoAgentEndTurn` 이벤트를 통해 처리됨.

## 3. 안정성 및 일관성 강화

- **이벤트 기반 동기화**: `OnSessionMetadataUpdate`를 통해 `IsWaitForResponse`뿐만 아니라 향후 추가될 다양한 세션 속성 변화에 대해서도 일관된 UI 갱신 메커니즘을 확보했습니다.
- **프로토콜 일관성**: `TGeminiAgent.SendPrompt`의 RPC 콜백 및 완료 조건 검증 시 `result.stopReason` 경로를 명확히 확인하여 응답 처리의 정확성을 높였습니다.
- **스레드 안정성**: 모든 UI 갱신은 `TThread.Queue`를 통해 메인 스레드에서 안전하게 실행되도록 유지했습니다.

## 4. 수정 파일 목록
- `src/Agents/Gemini/uGeminiAgent.pas`: `SendPrompt`, `CancelPrompt` 내 상태 관리 및 이벤트 발생 로직 추가.
- `src/UI/uAgentControl.pas`: `HandleSendMessage` 내 레거시 상태 설정 코드 및 `TAgentHandler` 의존성 제거.
- `docs/soc_v5.md` (업데이트)
