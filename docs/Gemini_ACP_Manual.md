# Agent Client Protocol (ACP) 연결 가이드

본 문서는 Delphi(FMX) 환경에서 ACP 표준을 준수하는 에이전트(예: `gemini-cli`)와 통신하기 위한 공식 프로토콜 규격 및 핸드셰이크 과정을 설명합니다. 본 가이드는 [ACP 공식 명세](https://github.com/agentclientprotocol/agent-client-protocol)를 바탕으로 작성되었습니다.

## 1. 개요 (Overview)
- **프로토콜 기반**: JSON-RPC 2.0
- **전송 계층**: 주로 표준 입출력(stdio) 또는 SSE(Server-Sent Events)를 사용함.
- **메시지 규칙**: 
  - 모든 메시지는 유효한 JSON-RPC 2.0 객체여야 함.
  - stdio 통신 시 메시지의 끝은 라인 피드(`#10`, `\n`)를 사용하며, 각 메시지는 한 줄로 구성됨.

## 2. 초기화 핸드셰이크 (Initialization Handshake)

에이전트 연결 후 가장 먼저 수행해야 하는 단계입니다.

### 1단계: `initialize` 요청 (Client -> Agent)
클라이언트가 자신의 기능(Capabilities)과 정보를 서버에 알립니다.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "roots": { "listChanged": true },
      "sampling": {}
    },
    "clientInfo": {
      "name": "acp-manager",
      "version": "1.0.0"
    }
  }
}
```

### 2단계: `notifications/initialized` 알림 (Client -> Agent)
서버로부터 `initialize` 응답을 받은 후, 클라이언트가 준비되었음을 알리는 단방향 알림입니다.

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized"
}
```

## 3. 핵심 기능 (Core Capabilities)

ACP 에이전트는 다음과 같은 세 가지 주요 리소스를 제공합니다.

### 1) Prompts (프롬프트)
에이전트가 제공하는 사전 정의된 템플릿입니다.
- **조회**: `prompts/list`
- **사용**: `prompts/get` (인자값 포함 가능)

### 2) Resources (리소스)
에이전트가 읽을 수 있는 데이터(파일, API 응답 등)입니다.
- **조회**: `resources/list`
- **읽기**: `resources/read` (URI 기반 접근)

### 3) Tools (도구)
에이전트가 클라이언트에게 실행을 요청할 수 있는 실행 가능한 기능입니다.
- **조회**: `tools/list`
- **실행**: `tools/call`

## 4. 메시징 및 샘플링 (Sampling)

클라이언트가 에이전트에게 메시지 생성을 요청할 때 사용하는 방식입니다.

### `sampling/createMessage` (Agent -> Client)
에이전트가 클라이언트에게 사용자 입력을 받거나 메시지를 생성해달라고 요청할 때 사용됩니다.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "sampling/createMessage",
  "params": {
    "messages": [
      {
        "role": "user",
        "content": { "type": "text", "text": "안녕, 오늘 날씨 어때?" }
      }
    ],
    "maxTokens": 100
  }
}
```

## 5. 주의 사항
- **표준 준수**: `session/new`와 같은 메서드는 비표준이며, 공식 ACP 환경에서는 작동하지 않을 수 있습니다.
- **버전 관리**: `protocolVersion`은 서버와 클라이언트 간의 호환성을 결정하는 중요한 값이므로 최신 명세를 확인하십시오.
- **비동기 처리**: 모든 요청은 `id`를 통해 비동기로 처리되므로, 응답 순서가 보장되지 않음에 유의하십시오.
