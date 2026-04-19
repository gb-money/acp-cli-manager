# 프로젝트 AI 에이전트 지침서 (Agent Guidelines)

본 문서는 현재 프로젝트에서 AI 동료(Gemini 등)가 코드 작성 및 수정을 수행할 때 **반드시 준수해야 할 필수 규칙**을 정의합니다.

## 1. JSON 처리 라이브러리 강제 사용 규칙
이 프로젝트는 델파이 내장 `System.JSON`을 사용하지 않습니다. 모든 JSON 파싱, 생성, 수정 작업은 **반드시 아래 경로의 전용 라이브러리를 사용**해야 합니다.

- **대상 파일**: `src/modules/JsonDataObjects/Source/JsonDataObjects.pas`
- **구현 지침**:
  - `uses` 절에 `JsonDataObjects`를 명시적으로 추가할 것.
  - 객체 생성 및 파싱 시 `TJsonObject.Create` 또는 `TJsonObject.Parse()`를 활용.
  - Property 접근 시 `.S['key']`, `.I['key']`, `.O['object']`, `.A['array']` 등 JsonDataObjects 고유의 직관적인 구문을 사용할 것.

## 2. 외부 컴포넌트 제한 현황
- 프로세스 관리 계층(`src/Core`)은 어떠한 외부 라이브러리(DOSCommand, JCL 등)도 허용되지 않으며 100% `Winapi.Windows` 네이티브로 구현되어야 합니다.
- (현존하는 유일한 서드파티 라이브러리 예외 목록: `JsonDataObjects.pas`)
