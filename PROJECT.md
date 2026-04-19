# Gemini CLI 및 Delphi 기반 멀티 에이전트 매니저 (ACP)

## 1. 개요 (Overview)
본 프로젝트는 `google-gemini/gemini-cli` 및 `Claude Code`의 철학을 분석하여, Delphi(RAD Studio 11) FMX를 기반으로 구축된 독자적인 **멀티 에이전트 오케스트레이션 데스크톱 애플리케이션**입니다. 에이전트와의 표준화된 통신을 통해 개발 워크플로우를 자동화하고 제어하는 것을 목표로 합니다.

## 2. 기술 아키텍처 및 통신 (Architecture & Communication)
- **프로토콜**: **ACP (Agent Client Protocol)** 준수
  - JSON-RPC 2.0 규격의 표준 입출력(stdio) 통신 방식을 채택했습니다.
  - 에이전트와 클라이언트(UI) 간의 계층화된 인터페이스를 제공합니다.
- **에이전트 제어 (Process Management)**:
  - 자식 프로세스로 `gemini-cli --experimental-acp`를 실행하여 파이프라인을 관리합니다.
  - **UUID 기반 세션 재개(`--resume`)** 기능을 통해 프로세스 생명주기를 정밀하게 제어하고 시스템 리소스를 최적화합니다.

## 3. 핵심 구현 전략 (Core Implementation Strategy)
순수 Delphi FMX(FireMonkey) 및 Windows Native API를 활용하여 **외부 서드파티(3rd-party) 컴포넌트나 라이브러리 없이 100% 직접 네이티브로 구현**합니다.
- **네이티브 프로세스 제어**: 별도의 라이브러리(DOSCommand 등) 없이 `Winapi.Windows`의 `CreateProcess`와 **이름 없는 파이프(Anonymous Pipe)**를 직접 제어하여 CLI를 백그라운드 자식 프로세스로 실행하고 스레드 기반 ACP 표준 입출력(stdio) 통신을 구현합니다.
- **에이전트 사이드바**: `TListBox` 커스텀 아이템을 활용하여 에이전트 목록을 관리합니다. (핀 고정 및 드래그 앤 드롭 지원)
- **멀티 탭 인터페이스**: 에이전트별 독립적인 대화 탭을 구성하고, 실시간 스트리밍 응답을 시각화합니다.
- **마크다운 엔진**: `TTextLayout` 및 오픈소스 파서를 활용한 네이티브 리치 텍스트 렌더링을 지원합니다.
- **파일 및 Diff 관리**: 세션별 파일 변경 내역을 스냅샷으로 기록하며, Side-by-Side 방식의 Diff 뷰어를 제공합니다.

## 4. 멀티 에이전트 워크플로우 (Orchestration)
결정론적인 루프 제어를 통해 안정적인 결과물을 도출합니다.
- **표준 구조**: `Coder` (코드 작성) → `Reviewer` (리뷰 및 검증) → `Committer` (Git 배포)
- **제어 로직**: AI의 자율적 판단에만 의존하지 않고, 델파이 앱 내에서 **엄격한 조건부 반복 처리**를 구현합니다.
  - 리뷰 실패 시 피드백과 함께 Coder에게 재지시하는 Flow를 강제합니다.

## 5. 기존 툴 대응 및 차별성 (Differentiation)
- **강력한 통제력**: 코드 레벨에서 워크플로우를 강제하여 예측 가능한 자동화를 실현합니다.
- **리소스 효율성**: 필요에 따라 프로세스를 완전히 종료하고 나중에 상태를 복원하는 OS 수준의 관리가 가능합니다.
- **높은 확장성**: ACP 표준을 준수함으로써 향후 Gemini 외에도 다양한 에이전트 CLI와 손쉽게 교체 및 연동이 가능합니다.
