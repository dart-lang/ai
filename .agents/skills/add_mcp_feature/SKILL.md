---
name: add_mcp_feature
description: >
  Instructions for adding new features (tools, prompts, etc.) to the
  dart_mcp_server package.
---

# Adding Features to dart_mcp_server

Follow these instructions when adding new tools, prompts, or other capabilities
to the `dart_mcp_server`.

## 1. Locate or Create a Mixin

All server features are implemented as mixins on the `DartMCPServer` at
`pkgs/dart_mcp_server/lib/src/server.dart`. 

- **Check existing mixins**: Look under `pkgs/dart_mcp_server/lib/src/mixins/`
  to see if your feature fits into an existing category (e.g., `analyzer.dart`,
  `pub.dart`).
- **Create a new mixin**: If your feature is distinct, create a new file in that
  directory, following the patterns in existing mixins. Make sure to include a
  copyright header at the top of the file, with the current year.

## 2. Implementation Details
- **Registration**: Tools, prompts, etc should be registered in the `initialize`
  method of the mixin, which is an override and must call `super.initialize()`.

## 3. Testing

Always add tests for any new features.

- **Test Harness**: Use the `TestHarness` class located in
  `pkgs/dart_mcp_server/test/test_harness.dart`.
- **Existing Tests**: Look at `pkgs/dart_mcp_server/test/tools/` for examples of
  how to test specific tools.
- **Enhance Harness**: If the current `TestHarness` lacks functionality needed
  for your test, feel free to add it.

## 4. Verification
- Run tests
- Run analysis
- Format the code
