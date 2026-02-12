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
- **Parameter Names**: When adding new arguments to tools or prompts, always
  add a constant to the `ParameterNames` extension in
  `pkgs/dart_mcp_server/lib/src/utils/names.dart` and use that constant
  instead of hardcoding string literals in your tool parsing and schema.

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

## 5. Documentation

- Run the `pkgs/dart_mcp_server/tool/update_readme.dart` script to update the
  `README.md` file with any new features, it must be ran from the
  `pkgs/dart_mcp_server` directory.
- Apply any other manual edits to the `README.md` file as needed.
- Update the `CHANGELOG.md` file to include any user facing updates.

## 6. Update this skill

- Update this `SKILL.md` file if that would be helpful for future features.
