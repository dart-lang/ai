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

You can install this plugin into Cursor using a Team Marketplace or by linking it locally.

#### Method 1: Local Installation (for testing)

1. Link the `plugins` directory to your local Cursor plugins folder:

```bash
mkdir -p ~/.cursor/plugins/local
ln -s /path/to/dart-lang/ai/plugins ~/.cursor/plugins/local/dart-flutter
```

2. Restart Cursor. The editor will automatically discover and load the skills under `skills/` and configure the MCP server defined in `mcp.json`.

#### Method 2: Team Marketplace

If you are using Cursor Teams/Enterprise, you can add this repository to your Team Marketplace:

1. Go to **Cursor Settings > Team > Team Marketplaces**.
2. Add the URL of the repository (pointing to the `plugins/` directory where the `.cursor-plugin` folder resides).
3. Members of your team can then install the **Dart and Flutter** plugin directly from the team marketplace tab in the Extensions panel.

