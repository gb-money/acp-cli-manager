# Agent Architecture, Dependency Decoupling & Content Rawness (SOC v8)

이 문서는 순환 참조 해결을 위한 타입 분리, 2단계 디스패처 도입, 그리고 에이전트 레이어의 UI 종속적 가공 로직 제거 작업을 기록합니다.

## 1. 순환 참조 해제 및 타입 시스템 재설계

에이전트(`TACPAgent`)와 세션 관리자(`TSessionManager`) 간의 강한 결합도를 낮추고 컴파일 안정성을 확보했습니다.

- **uAgentTypes.pas 중심의 타입 통합**: `uACPAgent.pas`에 정의되어 있던 `TSessionInfo`, `TAgentModelInfo`, `TAgentModeInfo`를 `uAgentTypes.pas`로 이동했습니다.
- **타입 지우기(Type Erasure) 패턴 적용**: `TSessionInfo.Agent` 필드를 `TObject` 타입으로 변경하여 에이전트와 관리자 간의 순환 참조를 물리적으로 끊었습니다.
- **메타데이터 경로 독립성 확보**: 에이전트 객체에 직접 접근하지 않고도 세션 경로를 생성할 수 있도록 `TSessionInfo`에 `AgentName` 필드를 추가했습니다.

## 2. 2단계 세션 업데이트 디스패처 도입

`session/update` 메시지 내부의 다양한 하위 업데이트 타입을 효율적으로 처리하기 위한 라우팅 구조를 확장했습니다.

- **FSessionUpdateHandlers 도입**: `TDictionary<string, TSessionUpdateHandler>`를 통해 `agent_thought_chunk`, `models_update` 등 하위 타입을 1:1 매핑했습니다.
- **HandleSessionUpdate 리팩토링**: 거대한 `if-else if` 문을 제거하고 딕셔너리 기반의 2차 디스패칭을 수행하도록 변경하여 확장성을 극대화했습니다.

## 3. 에이전트 레이어의 원본 데이터(Rawness) 유지

SoC 원칙에 따라 로직 레이어가 UI의 영역(데이터 가공 및 필터링)을 침범하던 코드를 모두 제거했습니다.

- **필터링 로직 완전 삭제**: `uACPAgent.ProcessChunkUpdate`와 `uConversationService.CleanContent`에서 `"USER:"` 접두어나 `"--- content from"` 컨텍스트 마커를 강제로 잘라내던 코드를 제거했습니다.
- **데이터 흐름 정규화**: 에이전트는 프로토콜 규격에 맞는 원본 데이터를 그대로 상위 레이어(UI/Service)로 전달하며, 최종적인 데이터의 노출 방식은 UI 레이어가 결정하도록 역할을 분리했습니다.

## 4. RPC 통신 및 통지 메커니즘 최적화

- **중복 파싱 제거**: `TACPClient`에서 파싱된 JSON 객체를 이벤트 인자로 직접 전달하도록 `TACPRawDataEvent` 시그니처를 고도화했습니다. 이로 인해 에이전트 레이어에서 로그 처리를 위해 JSON을 재파싱하던 오버헤드가 제거되었습니다.
- **글로벌 모델 업데이트 일관성**: 특정 세션에서 모델 변경 성공 시, 해당 세션뿐만 아니라 에이전트 전역 상태를 갱신하고 모든 활성 세션에 통지하도록 `ChangeModel` 로직을 개선했습니다.

## 5. 수정 파일 목록
- `src/Core/uAgentTypes.pas`: 핵심 데이터 구조 및 이벤트 타입 통합.
- `src/Agents/uACPAgent.pas`: 2단계 디스패처 및 원본 데이터 전달 로직 반영.
- `src/ACP/uACPClient.pas`: 파싱된 객체 전달을 통한 통신 최적화.
- `src/Core/uSessionManager.pas`: 타입 이동에 따른 세션 생성 로직 수정.
- `src/Core/uConversationService.pas`: 가공 로직 제거 및 raw 데이터 처리.
- `src/UI/uAgentControl.pas`: 타입 캐스팅 보강 및 UI 라우팅 조정.
- `src/Agents/Gemini/uGeminiAgent.pas`: 글로벌 모델 갱신 방식 적용.
- `docs/soc_v8.md` (신규)
