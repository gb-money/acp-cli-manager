# 대화 시스템 및 UI 개선 보고서 (2026-04-23 v2)

## 1. 개요
에이전트 응답 종료 후 입력창 활성화 문제, 자정을 넘기는 대화 시 날짜 뱃지 렌더링 오류, 그리고 세션별 로깅 구조 개선을 포함한 종합적인 시스템 안정화 작업을 수행함.

## 2. 주요 수정 사항

### A. 에이전트 제어 및 상태 관리
- **입력창 자동 활성화**: `TACPAgent.EndTurn` 호출 시 `IsWaitForResponse` 상태를 `False`로 명시적 해제하여, 답변 완료 후 Web UI의 전송 버튼이 즉시 활성화되도록 수정.
- **RPC 전환 감지 및 버블 분리**:
    - `TSessionData`에 `LastRPCType` 필드를 추가하여 컨텍스트 변화(생각 ↔ 메시지 ↔ 도구 호출)를 감지.
    - `CheckRPCTransition` 로직을 통해 타입 전환 시 기존 스트리밍을 종료하고 버퍼를 초기화하여 UI 버블이 깔끔하게 분리되도록 함.
    - 단, 메시지 직후 권한 요청(`request_permission`)이 올 경우 버튼이 버블 하단에 붙도록 예외 처리 적용.

### B. 로깅 시스템 개선 (SOC v9)
- **세션별 디버그 로그**: `%USERPROFILE%`에 생성되던 전역 `acp.log`를 각 세션 폴더(`sessions/.../acp.log`)로 이동하여 독립적인 추적 가능하게 함.
- **대화 내역 복구**: `uACPAgent`에서 Raw 트래픽 파싱을 통해 `sessionId`를 자동 추출하고, `history.json`에 기록하는 로직을 복원하여 재시작 시 대화 보존 문제 해결.

### C. 날짜 뱃지(Date Badge) 고도화
- **버블 내 날짜 일관성 (Delphi)**:
    - `TSessionInfo.CurrentBubbleDate` 도입.
    - 스트리밍 응답 도중 자정이 지나더라도 동일한 버블 내에서는 최초 시작 시간을 유지하여 뱃지 중복 생성을 원천 차단.
- **동적 라벨 업데이트 (JavaScript)**:
    - `window.ACP.dateBadges` 객체로 생성된 뱃지 ID 관리.
    - 새로운 날짜 뱃지가 그려질 때, 이전의 "Today" 뱃지들을 찾아 실제 날짜(예: 2026-04-19)로 라벨을 자동 갱신.
    - 세션 전환 및 대화창 초기화 시 관련 상태를 정확히 리셋하여 메모리 안전성 확보.

## 3. 기술적 세부사항
- **대상 파일**:
    - `src/Agents/uACPAgent.pas` (로깅, 전환 감지)
    - `src/UI/uAgentControl.pas` (스트리밍 제어, 날짜 갱신)
    - `src/Core/uAgentTypes.pas` (세션 속성 확장)
    - `src/UI/assets/js/index.ACP.js` (JS 렌더링 로직)
- **형식 보존**: `JsonDataObjects` 사용 및 `UTF-8 with BOM` 인코딩 표준 준수.

## 4. 결과 및 향후 과제
- **결과**: 대화창 UI가 시간 흐름에 따라 더 정확하게 반응하며, 디버깅 로그가 세션별로 격리되어 관리 효율성이 증대됨.
- **과제**: 향후 대화 내역이 매우 길어질 경우를 대비한 DOM 가상화(Virtual Scrolling) 검토 필요.
