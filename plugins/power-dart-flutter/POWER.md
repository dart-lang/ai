---
name: "dart-flutter"
displayName: "Dart and Flutter"
description: "Official Kiro Power for Dart and Flutter. Installs Dart/Flutter steering files and mcp-server to build natively compiled, visually stunning applications."
keywords: ["dart", "flutter", "mobile", "web", "desktop", "analysis", "unit test", "widget test", "formatting"]
author: "Dart and Flutter Team"
---

# Onboarding

Before using the Dart and Flutter Power, verify that the Dart and Flutter SDKs are installed on your system.

## Step 1: Verify SDK Installation
Ensure that the CLI tools are available in your path:
- Verify Dart SDK: `dart --version`
- Verify Flutter SDK: `flutter --version`

## Step 2: Validate MCP Server
The Dart and Flutter Power utilizes the `dart-mcp-server` exposed in the `mcp.json` file. Ensure that the Dart SDK version is 3.9.0 or later for the built-in `mcp-server` command, or make sure the server package is active.

# When to Load Steering Files
- Add `flutter_localizations` and `intl` dependencies, enable "generate true" in `pubspec.yaml`, and create an `l10n.yaml` configuration file. Use when initializing localization support for a new Flutter project. -> flutter-setup-localization.md
- Adds interactive widget previews to the project using the previews.dart system. Use when creating new UI components or updating existing screens to ensure consistent design and interactive testing. -> flutter-add-widget-preview.md
- Architects a Flutter application using the recommended layered approach (UI, Logic, Data). Use when structuring a new project or refactoring for scalability. -> flutter-apply-architecture-best-practices.md
- Collect coverage using the coverage packge and create an LCOV report -> dart-collect-coverage.md
- Configure `MaterialApp.router` using a package like `go_router` for advanced URL-based navigation. Use when developing web applications or mobile apps that require specific deep linking and browser history support. -> flutter-setup-declarative-routing.md
- Configures Flutter Driver for app interaction and converts MCP actions into permanent integration tests. Use when adding integration testing to a project, exploring UI components via MCP, or automating user flows with the integration_test package. -> flutter-add-integration-test.md
- Create model classes with `fromJson` and `toJson` methods using `dart:convert`. Use when manually mapping JSON keys to class properties for simple data structures. -> flutter-implement-json-serialization.md
- Define and generate mock objects for external dependencies using `package:mockito` and `build_runner`. Use when unit testing classes that depend on complex external services like APIs or databases. -> dart-generate-test-mocks.md
- Entrypoint structure, exit codes, cross-platform scripts. Use when building command line utilities, scripts, or applications. -> dart-build-cli-app.md
- Execute `dart analyze` to identify warnings and errors, and use `dart fix --apply` to automatically resolve mechanical lint issues. Use during development to ensure code quality and before committing changes. -> dart-run-static-analysis.md
- Fixes Flutter layout errors (overflows, unbounded constraints) using Dart and Flutter MCP tools. Use when addressing "RenderFlex overflowed", "Vertical viewport was given unbounded height", or similar layout issues. -> flutter-fix-layout-issues.md
- Guide agents to use `package:ffigen` to automatically generate FFI bindings instead of writing them manually. Use this skill when a task involves writing new FFI bindings, extending C/Objective-C/Swift integrations, or replacing hand-crafted `dart:ffi` setups. -> dart-use-ffigen.md
- Guides agents in compiling and packaging C/C++ source code into dynamic or static libraries (Code Assets) using Dart's Native Assets hook system (via hook/build.dart and hook/link.dart utilizing package:hooks and package:native_toolchain_c). Use when a user asks to: 'setup native assets', 'compile C/C++ source code', 'bundle dynamic libraries', 'build native C code', 'link native assets', 'implement build.dart or link.dart hooks', or 'integrate C/C++ interop in Dart/Flutter'. Helps agents avoid manual toolchain orchestration and configures secure hash-validated binary downloads or advanced linker tree-shaking with package:record_use mapping. -> dart-setup-ffi-assets.md
- Implement a component-level test using `WidgetTester` to verify UI rendering and user interactions (tapping, scrolling, entering text). Use when validating that a specific widget displays correct data and responds to events as expected. -> flutter-add-widget-test.md
- Replace the usage of `expect` and similar functions from `package:matcher` to `package:checks` equivalents. -> dart-migrate-to-checks-package.md
- Use `LayoutBuilder`, `MediaQuery`, or `Expanded/Flexible` to create a layout that adapts to different screen sizes. Use when you need the UI to look good on both mobile and tablet/desktop form factors. -> flutter-build-responsive-layout.md
- Use switch expressions and pattern matching where appropriate -> dart-use-pattern-matching.md
- Use the `http` package to execute GET, POST, PUT, or DELETE requests. Use when you need to fetch from or send data to a REST API. -> flutter-use-http-package.md
- Uses get_runtime_errors and lsp to fetch an active stack trace, locate the failing line, apply a fix, and verify resolution via hot_reload. -> dart-fix-runtime-errors.md
- Workflow for fixing package version conflicts. Use this when `pub get` fails due to incompatible package versions. -> dart-resolve-package-conflicts.md
- Write and organize unit tests for functions, methods, and classes using `package:test`. Use when creating new logic or fixing bugs to ensure code remains correct and regression-free. -> dart-add-unit-test.md
