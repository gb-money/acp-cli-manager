# Agent Client Protocol (ACP) JSON-RPC 2.0 Specification

This document provides an exhaustive technical reference for the Agent Client Protocol (ACP) JSON-RPC 2.0 messages used in the `acp-cli-manager` project.

## 1. Protocol Architecture
ACP uses JSON-RPC 2.0 for bidirectional communication.
- **Client**: Initiator (IDE, CLI, or Editor).
- **Agent**: The AI program providing intelligence.
- **Standard Transports**: `stdio` (pipes), `http` (POST), and `websocket`.

---

## 2. Session Lifecycle & Management

### A. Initialization (`initialize`)
Handshake to negotiate versions and capabilities.
- **Client Params**: `protocolVersion`, `clientCapabilities` (fs, terminal, auth), `clientInfo`.
- **Agent Result**: `protocolVersion`, `agentCapabilities` (loadSession, promptCapabilities, mcpCapabilities), `agentInfo`, `authMethods`.

### B. Session Operations
| Method | Description |
| :--- | :--- |
| `session/new` | Creates a new session context with specified `cwd` and `mcpServers`. |
| `session/load` | Resumes an existing session. History is replayed via notifications before the final result. |
| `session/list` | Returns a paginated list of sessions filtered by `cwd`. |
| `session/set_config_option` | Updates session settings like model choice or reasoning level. |

---

## 3. Communication & State Updates (`session/update`)

Agents use the `session/update` notification to push state changes to the client.

### Update Types (`params.update`)
- **`plan`**: Communicates the agent's strategy using `PlanEntry` objects (content, priority, status).
- **`agent_message_chunk`**: Incremental text or content blocks.
- **`session_info_update`**: Real-time metadata like session title or timestamps.
- **`config_option_update`**: Pushes the current state of all available configuration options.
- **`available_commands_update`**: Advertises available **Slash Commands** (e.g., `/web`, `/test`).
- **`user_message_chunk`**: Used during `session/load` to restore user history.

### Prompting (`session/prompt`)
The client sends user input as an array of `ContentBlock` objects.
- **Slash Commands**: Executed as text within a prompt (e.g., `{"type": "text", "text": "/explain this code"}`).

---

## 4. Capability Interfaces

### A. File System (`fs/`)
- **`fs/read_text_file`**: Agent requests file content.
- **`fs/write_text_file`**: Agent requests to save file content.

### B. Terminals (`terminal/`)
- **`terminal/create`**: Agent starts a shell process.
- **`terminal/output`**: Agent polls/receives process output.
- **`terminal/wait_for_exit`**: Agent waits for a process to terminate.

---

## 5. Key Data Structures

### ContentBlock
```json
{
  "type": "text" | "image" | "resource" | "resource_link",
  "text": "...",
  "mimeType": "...",
  "data": "base64..."
}
```

### ConfigOption
```json
{
  "id": "model",
  "category": "model",
  "type": "select",
  "currentValue": "gpt-4o",
  "options": [ { "id": "gpt-4o", "label": "GPT-4o" } ]
}
```

---

## 6. Local Logging & History (`history.json`)

The `acp-cli-manager` maintains a local log of all RPC communication within a `history.json` file per session (managed by `uACPAgent.pas` / `LogRPC`).

When writing to `history.json`, the system wraps the standard JSON-RPC payload in a custom logging object. **These wrapper fields are strictly for local log management and MUST NEVER be transmitted over the RPC connection.**

### Non-Standard Logging Fields (Internal Metadata):
The following fields are used exclusively for local state management and history tracking. They **MUST NOT** be included in messages sent to the agent:

- `timestamp`: (String) Local record time.
- `direction`: (String) Flow direction (`send`/`receive`).
- `data_raw`: (String) Raw payload fallback.
- `data.params.prompt.filename`: (String) Internal reference for UI rendering or context tracking within prompt content blocks.

> **CRITICAL WARNING**: These fields are non-standard extensions. **Absolutely do not send any of the above fields (including nested fields like `data.params.prompt.filename`) as part of a JSON-RPC transmission.** Doing so violates the Agent Client Protocol and may cause the agent to fail.

---

## 7. Implementation Guide (Delphi/Pascal)

Strict adherence to **`JsonDataObjects.pas`** is required for all JSON operations.

### Handling a Plan Update (Example)
```pascal
procedure HandlePlanUpdate(const UpdateObj: TJsonObject);
var
  Entries: TJsonArray;
  i: Integer;
begin
  Entries := UpdateObj.A['entries'];
  for i := 0 to Entries.Count - 1 do
  begin
    // Accessing PlanEntry fields
    Log(Entries.O[i].S['content'] + ' [' + Entries.O[i].S['status'] + ']');
  end;
end;
```

### Sending a Config Option Update
```pascal
var
  Params: TJsonObject;
begin
  Params := TJsonObject.Create;
  Params.S['sessionId'] := FSessionId;
  Params.S['configId'] := 'reasoning_level';
  Params.S['value'] := 'high';
  
  SendRequest('session/set_config_option', Params);
end;
```

### Reference Unit
Core protocol logic is centralized in `src/ACP/uACPProtocol.pas`.
