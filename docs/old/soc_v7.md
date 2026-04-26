# Agent Architecture & Global Metadata Management (SOC v7)

이 문서는 모델(Models) 및 모드(Modes) 데이터를 세션별 관리 방식에서 에이전트 레벨의 글로벌 관리 방식으로 전환하고, RPC 레이어의 세션 컨텍스트 보존 기능을 강화한 리팩토링 작업을 기록합니다.

## 1. 글로벌 모델 및 모드 관리 아키텍처 도입

기존에 개별 세션 데이터(`TSessionData`)에 종속되어 있던 모델과 모드 정보를 에이전트(`TACPAgent`) 레벨에서 전역으로 관리하도록 구조를 변경했습니다.

- **강력한 타입의 데이터 구조**: JSON 문자열을 그대로 저장하던 방식에서 벗어나, `TAgentModelInfo` 및 `TAgentModeInfo` 레코드 구조를 도입하여 타입 안정성과 파싱 효율을 높였습니다.
- **에이전트 전역 프로퍼티**: `TACPAgent`에 `AvailableModels`, `AvailableModes`, `CurrentModelId`, `CurrentModeId` 필드를 추가하여 모든 세션이 동일한 에이전트의 역량을 공유하도록 했습니다.
- **전역 통지 메커니즘**: `HandleModels`, `HandleModes` 메서드 호출 시 데이터가 업데이트되면, 현재 등록된 모든 세션에 대해 메타데이터 업데이트 이벤트를 발생시켜 UI가 즉시 동기화되도록 개선했습니다.

## 2. RPC 레이어의 세션 컨텍스트 보존 강화

서버 응답 시 `sessionId`가 누락되더라도 클라이언트가 이를 정확히 식별할 수 있도록 RPC 코어 레이어를 보강했습니다.

- **요청 레코드 확장**: `TACPRequestRecord`에 `SessionId` 필드를 추가하고, `Send` 메서드가 호출 시점의 세션 ID를 기억하도록 확장했습니다.
- **응답 자동 주입**: JSON-RPC 응답 수신 시, 기억해둔 세션 ID를 결과 객체(`result`)에 자동으로 주입하는 로직을 추가했습니다. 이를 통해 `session/load`처럼 응답에 세션 ID가 명시되지 않는 경우에도 에이전트 레이어가 대상 세션을 정확히 파악할 수 있게 되었습니다.
- **인터페이스 일관성 확보**: `Send` 메서드의 선언부와 구현부 시그니처를 일치시켜 컴파일 안정성을 확보했습니다.

## 3. UI 렌더링 최적화 및 안정성

- **글로벌 데이터 참조**: `TAgentControl.SessionToJSON`에서 개별 세션의 JSON 문자열을 파싱하던 로직을 제거하고, 에이전트의 글로벌 배열로부터 직접 UI용 JSON을 조립하도록 최적화했습니다.
- **레거시 코드 제거**: `uGeminiAgent.pas`의 `ChangeModel` 등에서 더 이상 존재하지 않는 세션별 `ModelsJson` 필드를 참조하던 코드를 정리하여 컴파일 에러를 해결하고 로직을 단순화했습니다.

## 4. 수정 파일 목록
- `src/ACP/uACPClient.pas`: 세션 컨텍스트 보존 및 ID 매칭 로직 보강.
- `src/Agents/uACPAgent.pas`: 글로벌 모델/모드 관리 필드, 레코드 및 핸들러 구현.
- `src/Agents/Gemini/uGeminiAgent.pas`: 레거시 세션 데이터 조작 로직 제거 및 시그니처 대응.
- `src/UI/uAgentControl.pas`: 글로벌 에이전트 프로퍼티 기반의 UI 직렬화 로직 반영.
- `docs/soc_v7.md` (신규)
