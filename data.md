# Delphi 11 Alexandria: Comprehensive Research Data

This document summarizes the characteristics, features, and known issues of **Delphi 11 Alexandria** (RAD Studio 11), covering versions 11.0, 11.1, 11.2, and 11.3.

## 1. Release Overview & Mission
Delphi 11 Alexandria was released with a primary focus on **modernizing the developer experience** and supporting **high-end hardware** (4K+ monitors and Apple Silicon).

*   **11.0 Release Date:** September 2021
*   **11.3 Release Date:** February 2023 (Final update in the Alexandria cycle)
*   **Key Mission:** High DPI IDE, Apple M1 Support, and Windows 11 readiness.

---

## 2. Language Characteristics & Features
Delphi 11 refined several modern Pascal features and introduced new syntax for better readability and performance.

### **Syntax & Language Additions**
*   **Binary Literals:** Use the `%` prefix for binary numbers (e.g., `%101010`).
*   **Digit Separators:** Use underscores for readability in numbers (e.g., `1_000_000` or `$FF_AA_CC`).
*   **Inline Variables & Type Inference:** (Refined) Declare variables at the point of use: `var I := 10;`.
*   **Managed Records:** (Refined) Records that support `Initialize`, `Finalize`, and `Assign` operators.
*   **Record Helpers for Intrinsic Types:** Added helpers for standard types like `Integer`, `String`, `Double`, etc., allowing for syntax like `MyInt.ToString`.

### **RTL (Runtime Library) Improvements**
*   **Zip64 Support:** `TZipFile` now supports files larger than 4GB.
*   **Performance:** Optimized `TStringBuilder`, JSON processing, and 64-bit collection classes.
*   **Apple M1 (macOS ARM64):** Full native compiler support for Apple Silicon.

---

## 3. Version Breakdown (11.0 - 11.3)

| Version | Key Focus | Notable Additions |
| :--- | :--- | :--- |
| **11.0** | High DPI & M1 | 4K IDE support, macOS ARM64 compiler, VCL Styles in Designer. |
| **11.1** | Quality & Security | **ASLR/DEP/NX enabled by default**, New LLDB-based Win32 debugger. |
| **11.2** | iOS & Markdown | iOS Simulator for ARM64 macOS, **Markdown (.md) support in IDE**. |
| **11.3** | Stability & Mobile | **Android API 33 support**, TBiometricAuth component, LSP performance peak. |

---

## 4. Known Bugs & Minor Issues
Delphi 11 had several notable issues, some of which were controversial or required workarounds.

### **Critical / Architectural Issues**
*   **Early Local Variable Release (RSP-30050):** The compiler may release interface/managed variables before the literal end of a function if they are no longer referenced. This can break "scope guard" patterns.
*   **LSP (Language Server Protocol) Stability:** Early 11.x versions suffered from "Ghost Errors" or Code Insight stopping. *Fixed mostly in 11.3.*
*   **ASLR/DEP Incompatibility:** Applications using legacy COM/OLE objects (like old Excel automation) may crash because these security features are now ON by default.
*   **Android API 33 Permissions:** Apps migrated to 11.3 must handle the new granular media permissions (Photos, Video, Audio) or they will fail to run on Android 13+.

### **Minor / UI Bugs**
*   **Editor "Insert" Glitch:** Highlighting text and typing occasionally appends instead of replacing. (Workaround: Press `Insert` key twice).
*   **Dark Mode Rendering:** Occasional "white flashes" or unpainted areas in the Object Inspector when switching between themes.
*   **HelpInsight Sizing:** Tooltips in the editor sometimes appear too small or with truncated text on certain DPI settings.

---

## 5. Direct Reference Links
These are the official and community-trusted links for Delphi 11:

### **Official Documentation (DocWiki)**
*   [What's New in RAD Studio 11 Alexandria](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/What%27s_New)
*   [Delphi 11.1 Release Notes](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/11_Alexandria_-_Release_1)
*   [Delphi 11.2 Release Notes](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/11_Alexandria_-_Release_2)
*   [Delphi 11.3 Release Notes](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/11_Alexandria_-_Release_3)

### **Technical Analysis & Community**
*   [Managed Records & ARC Changes (Synopse)](https://blog.synopse.info/post/2021/09/13/Delphi-11-Alexandria-is-out)
*   [RSP-30050: Early Variable Release Discussion](https://quality.embarcadero.com/browse/RSP-30050)
*   [Embarcadero Quality Portal](https://quality.embarcadero.com/) (Search for 11.x issues)

---

## 6. External Libraries in Use

Currently, the project uses one primary third-party library.

### **JsonDataObjects** (by Andreas Hausladen)
A high-performance JSON parser for Delphi that serves as a faster, more intuitive alternative to the native `System.JSON`.

*   **Repository:** [ahausladen/JsonDataObjects](https://github.com/ahausladen/JsonDataObjects)
*   **Key Characteristics:**
    *   **Performance:** Features dual parsers for UTF-8 and UTF-16, minimizing conversion overhead.
    *   **Intuitive Syntax:** Uses a "Fluent-like" syntax (e.g., `.S['name']`, `.O['child']`).
    *   **Auto-Creation:** Accessing a non-existent object or array property automatically creates it, reducing null-check boilerplate.
    *   **Platform Support:** Fully compatible with Delphi 11 Alexandria across Win32, Win64, and mobile platforms.

*   **Common Usage Patterns (from Community & Docs):**
    *   Parsing: `Obj := TJsonObject.Parse(JsonString) as TJsonObject;`
    *   Serialization: `JsonString := Obj.ToJSON(Compact := False);`
    *   Accessors: `.S[]` (String), `.I[]` (Integer), `.B[]` (Boolean), `.A[]` (Array), `.O[]` (Object).

*   **Project Rule:** As per `GEMINI.md`, **System.JSON must NOT be used**. All JSON operations must utilize `JsonDataObjects`.

---
*Created by Gemini CLI for Delphi 11 Research Task.*
