# Project AI Agent Guidelines

This document defines the essential rules that AI agents (such as Gemini) must follow when writing or modifying code in this project.

## 1. Development Environment
- **IDE Version**: Delphi 11 Alexandria (Update 3 / 11.3)
- **Framework**: FireMonkey (FMX)
- **Target Platform**: Win32
- **Language**: Object Pascal (Modern syntax: Inline variables, Record helpers, Binary literals supported)

## 2. Mandatory JSON Library Usage
This project does NOT use the built-in `System.JSON` of Delphi. All JSON parsing, generation, and modification tasks MUST use the dedicated library:
- **Target File**: `src/modules/JsonDataObjects/Source/JsonDataObjects.pas`
- **Implementation Guidelines**:
  - Explicitly add `JsonDataObjects` to the `uses` clause.
  - Use `TJsonObject.Create` or `TJsonObject.Parse()` for object creation and parsing.
  - Use intuitive property accessors: `.S['key']`, `.I['key']`, `.O['object']`, `.A['array']`, etc.
  - **Auto-Creation**: Accessing `.O[]` or `.A[]` on a non-existent key automatically creates the object/array.

## 3. External Component & Implementation Restrictions
- **Core Layer (`src/Core`)**: No external libraries (e.g., DOSCommand, JCL) allowed. Must be implemented using 100% **Winapi.Windows** native APIs (CreateProcess, Anonymous Pipes).
- **Exceptions**: `JsonDataObjects.pas` is the only approved 3rd party library for JSON.

## 4. Communication Protocol (ACP)
- **Standard**: Agent Client Protocol (ACP) based on JSON-RPC 2.0.
- **Reference Document**: See `JSONRPC.md` for detailed message schemas.
- **Protocol Logic**: All core communication must follow the implementation in `src/ACP/uACPProtocol.pas`.
- **Logging Rule**: Internal metadata (timestamp, direction, data_raw) used in `history.json` **MUST NOT** be transmitted over the RPC connection.

## 5. Source Control Management
- **Strategy**: Follow GitHub Flow as defined in `GIT.md`.
- **Branch**: All daily development and implementation must occur on the **`dev` branch**.
- **Versioning**: Adhere to Semantic Versioning (vMajor.Minor.Patch).

## 6. Build Error Handling (Delphi Compiler Bug)
- **Cascade Errors**: Be aware that the Delphi compiler often misinterprets subsequent code after an error on a high-level line, causing valid lines to be flagged incorrectly.
- **Priority Fix**: When build errors occur, always prioritize fixing the error on the **top-most line** of the file first.
- **Verification**: After fixing the top-level error, you MUST rebuild the project immediately to verify if the cascading errors have disappeared before attempting to fix them.

## 7. Hybrid UI Communication Architecture
The project utilizes a hybrid architecture where the UI is rendered in HTML/JS and the logic is handled in Delphi via `TWebBrowser`.

### A. Web-to-Delphi (Inbound Communication)
- **Format**: Custom URL Schemas with action names and query parameters.
- **Structure**: `schema://action-name?param1=value1&param2=value2`
- **Standard Schemas**:
  - `ui-action://`: Global UI layout and view state transitions.
  - `acp-action://`: Agent orchestration, chat messaging, and session control.
  - `explorer-action://`: File system navigation and previews.
- **Handling**: All inbound requests must be intercepted in the `HandleRequest` method of the respective `~~Control.pas` unit.

### B. Delphi-to-Web (Outbound Communication)
- **Mechanism**: Data is pushed to the Web UI using `FWebBrowser.EvaluateJavaScript`.
- **Mandatory Encoding**: To prevent string escaping issues (quotes, newlines, backslashes) and ensure data integrity, **ALL** data sent from Delphi to the Web UI MUST be Base64 encoded.
- **Data Encoding Standard**:
  1. Generate JSON using **`JsonDataObjects`**.
  2. Encode the JSON string into **Base64**.
  3. Pass the Base64 string to a JavaScript bridge function (e.g., `window.ACP.loadHistoryBase64("...")`).
  4. The Web UI must decode the string using `atob()` and parse it back to JSON.
- **Thread Safety**: All JavaScript evaluations MUST be executed on the **Main Thread** using `TThread.Queue` or `TThread.Synchronize`.

## 8. Resource and Asset Standards
To maintain visual consistency across the hybrid interface, the following asset standards apply:

### A. Iconography
- **Standard**: All icons used in the HTML/JS Web UI must follow the **Google Material Design Icons** specification.
- **Reference**: [google/material-design-icons](https://github.com/google/material-design-icons)
- **Implementation**: Prefer using SVG or the Material Icons web font to ensure crisp rendering at all scales within the `TWebBrowser` component.

## 9. Thread Safety and Concurrency
The application relies heavily on asynchronous communication with background processes. Strict adherence to thread-safe practices is mandatory.

### A. UI Thread Protection
- **Rule**: NEVER update UI components or call `EvaluateJavaScript` directly from a background thread or an anonymous thread.
- **Mechanism**: Use `TThread.Queue(nil, ...)` to dispatch UI tasks to the main thread.
- **Why Queue?**: `TThread.Queue` is preferred over `Synchronize` to prevent deadlocks and maintain a responsive UI while handling high-frequency ACP messages.

### B. Background Process Management
- **Pattern**: Use `TProcessReaderThread` (inheriting from `TThread`) for monitoring standard output/error of child processes.
- **Execution**: Long-running tasks or heavy I/O operations must be wrapped in `TThread.CreateAnonymousThread`.

### C. Data Synchronization
- **Shared Resources**: When accessing global session data or shared lists from multiple threads, use synchronization primitives from `System.SyncObjs` (e.g., `TCriticalSection`).
- **Convention**: Always use `try...finally` blocks to ensure critical sections are released even if an exception occurs.

## 10. Coding Style and Conventions
- **Namespace Usage**: Avoid using fully qualified names (e.g., `System.Classes.TThread`) within the code body. 
- **Guideline**: Add the required unit to the `uses` clause and use the short type/method name (e.g., `TThread`, `TJsonObject`). This ensures the code remains concise and readable.
- **Consistency**: Maintain the `u` prefix for units (e.g., `uMain.pas`) and `T` prefix for classes (e.g., `TUIControl`) as established in the project.

## 11. Character Encoding and Korean (Hangul) Support
To ensure consistent handling of Korean characters across different development environments and platforms:

### A. Source File Encoding
- **Mandatory Standard**: All source files (`.pas`, `.dpr`, `.fmx`, `.dfm`) MUST be saved in **UTF-8 with BOM (Byte Order Mark)** format.
- **Why BOM?**: The Delphi compiler requires the BOM to correctly identify the file as UTF-8. Without it, the compiler may treat the file as ANSI (CP949), causing Hangul characters in strings or comments to be corrupted.
- **External Editors**: If using external editors like VS Code, ensure they are configured to save with the "UTF-8 with BOM" encoding.

### B. String Handling
- **Native Type**: The default `string` type in Delphi 11 is `UnicodeString` (UTF-16). Use it for all internal text processing to maintain full Hangul compatibility.
- **I/O Operations**: When reading from or writing to external files or network streams, explicitly specify `TEncoding.UTF8` to prevent encoding mismatches.

## 12. Shell Command Usage (PowerShell)
- **Command Chaining**: The development environment uses **Windows PowerShell**. 
- **Rule**: NEVER use the `&&` operator to chain multiple commands, as it is not supported in many PowerShell versions.
- **Mechanism**: Use the semicolon `;` operator for sequential command execution (e.g., `git status; git diff HEAD`).
