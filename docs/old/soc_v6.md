# Agent Architecture & Intermediate Message Handling (SOC v6)

이 문서는 `session/prompt` 실행 도중 발생하는 중간 메시지(파일 I/O, 권한 요청, 상태 업데이트 등)의 처리 로직 리팩토링 및 메서드 디스패처(Method Dispatcher) 패턴 도입 작업을 기록합니다.

## 1. 메서드 디스패처(Method Dispatcher) 패턴 도입

기존 `DoReceive` 메서드 내의 거대한 `if-else` 분기문을 제거하고, 확장성과 가독성이 뛰어난 딕셔너리 기반의 라우팅 구조를 도입했습니다.

- **TMethodHandler 정의**: 클래스 메서드와 호환되는 전용 핸들러 타입(`procedure of object`)을 정의하여 타입 안정성을 확보했습니다.
- **라우터 테이블 (`FMethodHandlers`)**: `TDictionary<string, TMethodHandler>`를 통해 JSON-RPC 메서드 명과 실제 처리 함수를 1:1로 매핑했습니다.
- **RegisterHandlers 가상 메서드**: 모든 핸들러 등록 로직을 한곳으로 모았으며, 하위 클래스에서 필요 시 새로운 메서드를 쉽게 추가하거나 재정의할 수 있도록 설계했습니다.

## 2. 모듈화된 핸들러 구현

각 기능의 책임을 분리하여 독립된 헬퍼 메서드로 구현했습니다.

- **파일 시스템 조작 (`fs/`)**:
    - `HandleFSRead`: 에이전트의 파일 읽기 요청 시 즉시 파일을 읽어 `result.content` 필드에 담아 회신합니다.
    - `HandleFSWrite`: 에이전트의 파일 쓰기 요청을 수행하고, 성공 시 JSON-RPC 규격에 맞게 빈 객체(`result: {}`)를 응답합니다.
- **권한 요청 및 응답 (`session/request_permission`)**:
    - `HandleRequestPermission`: AI의 도구 실행 전 사용자 승인이 필요한 경우(`edit`, `other`), 관련 옵션들을 파싱하여 UI 레이어로 이벤트를 전달합니다.
    - `ReplyPermission` 개선: 사용자의 승인(`optionId`)뿐만 아니라 취소 시 명세에 따른 `"outcome": {"outcome": "cancelled"}` 응답을 정확히 생성하도록 보강했습니다.
- **도구 호출 스텁 (`session/tool_call`)**: 향후 UI 연동을 위해 TODO 주석과 함께 기본 처리 구조를 마련했습니다.

## 3. 세션 업데이트 로직 캡슐화 (`session/update`)

가장 복잡했던 `session/update` 처리를 하위 타입별 전용 메서드로 분리하여 유지보수성을 극대화했습니다.

- `ProcessAvailableCommandsUpdate`: 가용 커맨드 목록 동기화 및 세션 복구 완료 처리.
- `ProcessChunkUpdate`: `agent_thought_chunk`, `agent_message_chunk` 등을 실시간으로 누적하고 UI 스트리밍 이벤트를 발생시킵니다.
- `ProcessToolCallUpdate`: 답변 중 발생하는 인라인 도구 호출(예: diff 쓰기)을 처리합니다.
- `ProcessModelsUpdate` / `ProcessModesUpdate`: 모델 및 모드 변경 사항을 세션 데이터에 반영합니다.

## 4. 안정성 및 규격 준수

- **JSON-RPC 2.0 준수**: 모든 응답과 알림 처리를 프로토콜 규격에 맞춰 엄격하게 조정했습니다.
- **에러 핸들링**: 파일 I/O 실패 등 예외 상황 발생 시에도 에이전트 프로세스가 멈추지 않도록 방어 로직을 강화했습니다.

## 5. 수정 파일 목록
- `src/Agents/uACPAgent.pas`: 디스패처 패턴 및 모듈화된 핸들러 구현체 추가.
- `docs/soc_v6.md` (신규)
