<h1 align="center">
  Dart and Flutter Plugins
</h1>

This plugin provides a collection of [Dart](https://github.com/dart-lang/skills) and [Flutter](https://github.com/flutter/skills) skills and an MCP server for AI coding agents. These resources/tools help agents understand and work more effectively with Flutter and Dart.

## Installation

### Claude Plugin

1. Add the Dart and Flutter marketplace for Claude plugins:

```bash
claude plugin marketplace add dart-lang/ai/plugins
```

Install the Claude plugin for Dart and Flutter:

```bash
claude plugin install dart-flutter@dart-flutter
```

Verify the installation:

```bash
claude plugin marketplace list
```

### Kiro Power

To install the Dart and Flutter power in Kiro:

1. Open Kiro and navigate to the **Powers** panel.
2. Click **Add Custom Power** -> **Import power from GitHub**.
3. Enter the repository URL: `https://github.com/dart-lang/ai` (or select **Import power from a folder** and select the `plugins/power-dart-flutter` directory if you are developing locally).

