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

2. Install the Claude plugin for Dart and Flutter:

```bash
claude plugin install dart-flutter@dart-flutter
```

3. Verify the installation:

```bash
claude plugin marketplace list
```

### Cursor Plugin

You can test this plugin locally by copying it to your Cursor plugins directory.

1. Copy the `plugins` directory to your local Cursor plugins folder:

```bash
mkdir -p ~/.cursor/plugins/local
cp -r /path/to/dart-lang/ai/plugins ~/.cursor/plugins/local/dart-flutter
```

2. Restart Cursor. The editor will automatically discover and load the skills under `skills/` and configure the MCP server defined in `mcp.json`.

For more details about developing Cursor plugins, see the following resources:
- **Creating plugins**: [cursor.com/docs/plugins#creating-plugins](https://cursor.com/docs/plugins#creating-plugins)
- **Testing plugins**: [cursor.com/docs/plugins#test-plugins-locally](https://cursor.com/docs/plugins#test-plugins-locally)
- **Publishing plugins**: [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish)
- **Plugin template**: [github.com/cursor/plugin-template](https://github.com/cursor/plugin-template)
