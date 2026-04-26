# File Service Decoupling, Handshake Fix & UI Integration (SOC v11)

이 문서는 파일 시스템 로직의 완전한 분리, 다단계 RPC 핸드셰이크 안정화, 그리고 메인 UI와 독립 폼 간의 연결 고리 구현 작업을 기록합니다.

## 1. 파일 서비스 전담 클래스(`TFileService`) 도입

에이전트의 핵심 로직과 파일 시스템 작업 간의 결합도를 낮추기 위해 전용 서비스 계층을 신설했습니다.

- **관심사 분리(SoC)**: `TACPAgent`에 하드코딩되어 있던 `fs/read_text_file` 및 `fs/write_text_file` 핸들러를 `TFileService`로 위임했습니다.
- **자동 Diff 생성 통합**: `TConversationService`에 흩어져 있던 파일 변경 이력 저장 로직을 `TFileService.WriteTextFile` 과정에 통합하여, 파일 수정 시 실시간으로 `diffs/` 내역이 생성되도록 보장했습니다.
- **이벤트 기반 알림**: `OnWriteFile`, `OnReadFile` 이벤트를 통해 UI 레이어가 에이전트의 파일 작업을 관찰(Observe)하고 피드백을 줄 수 있는 구조를 마련했습니다.

## 2. RPC 핸드셰이크 및 세션 복구 안정화

다단계 핸드셰이크 과정에서 발생하던 데이터 누락 및 데드락 문제를 해결했습니다.

- **응답 데이터 캡처(Capture & Pass)**: `TACPClient`의 순차적 조건 체인(Step 0 -> Step 1)에 맞춰 첫 번째 응답(Result)을 복제 보관했다가 최종 콜백에 전달하는 로직을 적용했습니다. 이를 통해 UI가 세션 정보를 정확히 수신합니다.
- **파라미터 완전성 확보**: `session/load` 호출 시 누락되었던 `cwd` 및 `mcpServers: []` 파라미터를 추가하여 에이전트 환경 설정을 보강했습니다.
- **물리 디스크 스캔**: 앱 시작 시 비어있는 메모리가 아닌 실제 세션 디렉토리를 스캔하여 기존 대화 목록을 복구하도록 `GetSessionList`를 수정했습니다.

## 3. 폼 생명주기 및 UI 인터랙션 개선

사용자 인터페이스의 안정성과 사용성을 강화했습니다.

- **Access Violation 해결**: 자식 폼(`Explorer`, `Diff Viewer` 등) 종료 시 메인 폼이 들고 있는 참조 포인터를 `nil`로 초기화하는 `DoChildFormClose` 핸들러를 구현하여, 폼 재오픈 시의 메모리 오류를 제거했습니다.
- **에셋 및 로직 분리**: `diff_view.html`의 JavaScript를 `diff_view.UI.js`로 분리하여 관리성을 높이고 `assets/` 경로로 구조를 통일했습니다.
- **워크스페이스 표시 최적화**: 전체 경로 대신 폴더명만 표시하여 가독성을 높였습니다.
- **검색 기능 보강**: 사용자 메시지(`prompt`)가 배열 형태일 경우 검색이 실패하던 파싱 버그를 수정하고, 검색 결과 포커스 시 배경색이 유실되던 CSS 애니메이션을 교정했습니다.

## 4. 수정 파일 목록
- `src/Core/uFileService.pas` (신규): 파일 I/O 및 Diff 관리 전담.
- `src/Agents/uACPAgent.pas`: 핸드셰이크 로직 수정 및 파일 서비스 위임.
- `src/UI/uAgentControl.pas`: 파일 입출력 옵저버 추가.
- `src/UI/uUIControl.pas`: 검색 및 폼 호출 이벤트 브릿지.
- `uMain.pas`: 자식 폼 생명주기 제어 및 연결고리 구현.
- `src/Core/uSearchService.pas`: 대화 검색 파싱 로직 강화.
- `src/Core/uConversationService.pas`: 레거시 Diff 로직 제거.
- `src/UI/assets/diff_view.html`: 외부 JS 참조 구조로 변경.
- `src/UI/assets/js/diff_view.UI.js` (신규): 디프 뷰어 제어 로직.
- `docs/soc_v11.md` (신규)
