---
name: Update MCP Spec Version
description: Instructions for updating the supported Model Context Protocol (MCP) specification version in the `dart_mcp` package.
---

# Update MCP Spec Version

This skill guides you through the process of updating the `dart_mcp` package to support a new version of the Model Context Protocol (MCP) specification.

## Steps

1.  **Review the New Specification**:
    -   Read [Model Context Protocol LLM Resources](https://modelcontextprotocol.io/llms.txt) to find relevant documentation links for the new version.
    -   Use your tools fetch the content of the linked changelogs, schemas, and specification documents.
    -   Identify all changes introduced in the new version (new types, fields, deprecated items, new features, etc).
    -   **CRITICAL**: Do NOT invent APIs or assume changes based on partial information. Every change MUST be backed by the actual schema or specification text. If you cannot find the schema, pause and ask the user for guidance.
    -   Pay special attention to the schema changes as these are the source of truth.

2.  **Update the Protocol Version**:
    -   Open `pkgs/dart_mcp/lib/src/api/api.dart`.
    -   Add the new version to the `ProtocolVersion` enum.
        ```dart
        enum ProtocolVersion {
          // ...
          vYYYY_MM_DD('YYYY-MM-DD'),
        }
        ```
    -   Update `ProtocolVersion.latestSupported` to the new version.
        ```dart
        static const latestSupported = ProtocolVersion.vYYYY_MM_DD;
        ```

3.  **Update Documentation URLs**:
    -   Search the codebase for the *previous* spec version string (e.g., `2024-11-05`) or the regex `specification/\d{4}-\d{2}-\d{2}`.
    -   Update URLs in comments to point to the new spec version.
    -   Key files to check:
        -   `pkgs/dart_mcp/lib/src/client/sampling_support.dart`
        -   `pkgs/dart_mcp/lib/src/server/server.dart`
        -   `pkgs/dart_mcp/README.md`

4.  **Implement Schema Changes**:
    -   Review the schema for new types or fields by comparing the various part files included by `lib/src/api/api.dart` against the schema. If you cannot find the schema, pause and ask the user for guidance. All changes must be backed by the real schema.
    -   Update `lib/src/api/api.dart` as needed, for new features typically you should add a new part file to keep the codebase organized.
    -   **Important**: When implementing numeric fields from the schema, use `num` (or `num?` for optional fields) instead of `int` or `double`, unless the schema explicitly constraints the value to be an integer. The JSON schema `number` type can be either an integer or floating-point value.

5.  **Update Client/Server Implementations**:
    - See the support files under `pkgs/dart_mcp/lib/src/client/` and `pkgs/dart_mcp_server/lib/src/server/` for examples of how to implement features.
    - Ensure that you update the capabilities inside of `initialize` when implementing new features.

6.  **Update Examples**:
    - See the existing examples under `pkgs/dart_mcp/example/`, and either update the existing ones or add new ones as appropriate.

7.  **Write and Update Tests**:
    -   Write tests for the new features. See the existing tests as an example and follow the same style.
    -   Update any existing tests as needed, make sure to have good coverage of all features.
    -   If you notice missing tests for existing features, feel free to add those as well.

8.  **Verify**:
    -   Run tests in `pkgs/dart_mcp` and `pkgs/dart_mcp_server` to ensure no regressions.
    -   Run the updated examples and ensure they work as expected.
    -   Run the dart formatter and analyzer, to ensure the code is well-formatted and free of lint errors.
    -   Walk the user through all the changes you made and describe your reasoning.

9.  **Update Version and CHANGELOG.md**:
    -   Open `pkgs/dart_mcp/pubspec.yaml` and update the version according to whether this was a breaking change
    -   Open `pkgs/dart_mcp/CHANGELOG.md` and add a version entry for the new version if one doesn't already exist, mentioning the update to the new MCP spec version and any relevant changes. For breaking changes preface them with **Breaking:**.

10.  **Update This Skill**:
    -   Update this skill with any additional steps you performed or insights you gained during the update process.
