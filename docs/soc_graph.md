# ACP CLI Manager Sequence Diagrams (SOC v8)

이 문서는 에이전트와 UI 간의 핵심 인터랙션 흐름을 시각화합니다.

## 1. New Session (채팅 생성 흐름)
새 채팅 생성 시 사용자 응답성을 위해 임시 ID를 먼저 생성하고, 실제 프로세스 응답 시 정규 ID로 전환하는 과정을 보여줍니다.

```mermaid
sequenceDiagram
    participant UI as Web UI (JS)
    participant AC as TAgentControl
    participant SM as TSessionManager
    participant AG as TACPAgent
    participant CLI as Agent CLI Process

    UI->>AC: acp-action://new-chat?agent=gemini
    AC->>SM: AddSession(pending-ID)
    SM-->>AC: TSessionInfo (Pending)
    AC->>UI: window.ACP.addUserMessage (UI 갱신)
    
    AC->>AG: NewSession(params)
    AG->>CLI: session/new
    CLI-->>AG: { result: { sessionId: "real-123" } }
    
    AG->>AC: OnNewSession(Event)
    AC->>SM: FinalizeSessionId(pending-ID -> real-123)
    AC->>UI: window.ACP.updateSessionList (정규 ID 반영)
```

## 2. Resume Session (세션 복구 흐름)
기존 로그 이력을 불러올 때 중복 기록을 방지하기 위한 `IsRestoring` 플래그 관리 흐름입니다.

```mermaid
sequenceDiagram
    participant AC as TAgentControl
    participant AG as TACPAgent
    participant CS as TConversationService
    participant CLI as Agent CLI Process

    AC->>AG: ResumeSession(SessionId)
    Note over AG: Set IsRestoring = True
    AG->>CLI: session/resume (Implicit/Explicit)
    
    loop History Replay
        CLI->>AG: session/update (Chunk)
        AG->>CS: AppendLog (Check IsRestoring)
        Note right of CS: Skip file write if Restoring
        AG->>AC: OnMessageChunk (Event)
        Note over AC: UI skip or update silent buffer
    end
    
    CLI-->>AG: session/update (end_turn)
    AG->>AC: OnSessionResumed (Event)
    Note over AG: Set IsRestoring = False
    AC->>UI: window.ACP.finishLoading
```

## 3. Send Prompt (메시지 전송 및 스트리밍)
사용자 입력 파싱부터 실시간 응답 스트리밍까지의 흐름입니다.

```mermaid
sequenceDiagram
    participant UI as Web UI (JS)
    participant AC as TAgentControl
    participant AG as TACPAgent (Gemini)
    participant CLI as Agent CLI Process

    UI->>AC: acp-action://send-message
    AC->>UI: window.ACP.addUserMessage (즉시 반영)
    
    AC->>AG: SendPrompt(text)
    Note over AG: Parse @"file.pas" -> resource reference
    AG->>CLI: session/prompt (JSON-RPC)
    
    Note over AC: Show Thinking State
    
    loop Streaming Chunks
        CLI->>AG: session/update (agent_message_chunk)
        AG->>AC: OnMessageChunk (Event)
        AC->>UI: window.ACP.updateStreaming (실시간 출력)
    end
    
    CLI-->>AG: session/update (end_turn)
    AG->>AC: OnEndTurn (Event)
    AC->>UI: window.ACP.finishStreaming
```

## 핵심 설계 특징
1.  **Asynchronous ID Finalization**: `pending-` 접두어를 통해 네트워크 지연 중에도 UI가 멈추지 않도록 설계됨.
2.  **Stateless Agent**: 에이전트는 상태를 이벤트를 통해 전파하며, UI 계층(`TAgentControl`)이 최종적인 화면 표현(JS)을 결정함.
3.  **Restoration Protection**: `IsRestoring` 상태를 통해 세션 복구 시 로그 파일이 오염되는 것을 원천 차단함.
