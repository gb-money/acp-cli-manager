# Project AI Agent Guidelines

This document defines the essential rules that AI agents (such as Gemini) must follow when writing or modifying code in this project.

## 1. Mandatory JSON Library Usage
This project does NOT use the built-in `System.JSON` of Delphi. All JSON parsing, generation, and modification tasks MUST use the dedicated library at the path below:

- **Target File**: `src/modules/JsonDataObjects/Source/JsonDataObjects.pas`
- **Implementation Guidelines**:
  - Explicitly add `JsonDataObjects` to the `uses` clause.
  - Use `TJsonObject.Create` or `TJsonObject.Parse()` for object creation and parsing.
  - Use `JsonDataObjects` specific intuitive syntax for property access: `.S['key']`, `.I['key']`, `.O['object']`, `.A['array']`, etc.

## 2. External Component Restrictions
- The process management layer (`src/Core`) is not allowed to use any external libraries (e.g., DOSCommand, JCL) and must be implemented using 100% `Winapi.Windows` native APIs.
- (Current exception to 3rd party library list: `JsonDataObjects.pas`)

## 3. Source Control Management
- All development activities must follow the Git strategy defined in [GIT.md](./GIT.md).
- Ensure you are working on the `dev` branch for daily tasks.
