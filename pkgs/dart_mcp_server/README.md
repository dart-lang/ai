The Dart Tooling MCP Server exposes Dart and Flutter development tool actions to compatible AI-assistant clients.

[![Add to Cursor](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/install-mcp?name=dart_tooling&config=eyJ0eXBlIjoic3RkaW8iLCJjb21tYW5kIjoiZGFydCBtY3Atc2VydmVyIC0tZXhwZXJpbWVudGFsLW1jcC1zZXJ2ZXIgLS1mb3JjZS1yb290cy1mYWxsYmFjayJ9)

## Status

WIP. This package is still experimental and is likely to evolve quickly.

## Tools

<!-- run 'dart tool/update_readme.dart' to update -->

<!-- generated -->

| Name | Title | Description |
| --- | --- | --- |
| `connect_dart_tooling_daemon` | Connect to DTD | Connects to the Dart Tooling Daemon. You should get the uri either from available tools or the user, do not just make up a random URI to pass. When asking the user for the uri, you should suggest the "Copy DTD Uri to clipboard" action. When reconnecting after losing a connection, always request a new uri first. |
| `get_runtime_errors` | Get runtime errors | Retrieves the most recent runtime errors that have occurred in the active Dart or Flutter application. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `take_screenshot` | Take screenshot | Takes a screenshot of the active Flutter application in its current state. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `hot_reload` | Hot reload | Performs a hot reload of the active Flutter application. This is to apply the latest code changes to the running application. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `get_widget_tree` | Get widget tree | Retrieves the widget tree from the active Flutter application. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `get_selected_widget` | Get selected widget | Retrieves the selected widget from the active Flutter application. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `set_widget_selection_mode` | Set Widget Selection Mode | Enables or disables widget selection mode in the active Flutter application. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `get_active_location` | Get Active Editor Location | Retrieves the current active location (e.g., cursor position) in the connected editor. Requires "connect_dart_tooling_daemon" to be successfully called first. |
| `pub_dev_search` | pub.dev search | Searches pub.dev for packages relevant to a given search query. The response will describe each result with its download count, package description, topics, license, and publisher. |
| `remove_roots` | Remove roots | Removes one or more project roots previously added via the add_roots tool. |
| `add_roots` | Add roots | Adds one or more project roots. Tools are only allowed to run under these roots, so you must call this function before passing any roots to any other tools. |
| `dart_fix` | Dart fix | Runs `dart fix --apply` for the given project roots. |
| `dart_format` | Dart format | Runs `dart format .` for the given project roots. |
| `run_tests` | Run tests | Run Dart or Flutter tests with an agent centric UX. ALWAYS use instead of `dart test` or `flutter test` shell commands. |
| `create_project` | Create project | Creates a new Dart or Flutter project. |
| `pub` | pub | Runs a pub command for the given project roots, like `dart pub get` or `flutter pub add`. |
| `analyze_files` | Analyze projects | Analyzes the entire project for errors. |
| `resolve_workspace_symbol` | Project search | Look up a symbol or symbols in all workspaces by name. Can be used to validate that a symbol exists or discover small spelling mistakes, since the search is fuzzy. |
| `signature_help` | Signature help | Get signature help for an API being used at a given cursor position in a file. |
| `hover` | Hover information | Get hover information at a given cursor position in a file. This can include documentation, type information, etc for the text at that position. |

<!-- generated -->

## Usage

This server only supports the STDIO transport mechanism and runs locally on
your machine. Many of the tools require that your MCP client has `roots`
support, and usage of the tools is scoped to only these directories.

If you are using a client that claims it supports roots but does not actually
set them, pass `--force-roots-fallback` which will instead enable tools for
managing the roots.

### Running from the SDK

For most users, you should just use the `dart mcp-server` command. For now you
also need to provide `--experimental-mcp-server` in order for the command to
succeed.

### Running a local checkout

The server entrypoint lives at `bin/main.dart`, and can be ran however you
choose, but the easiest way is to run it as a globally activated package.

You can globally activate it from path for local development:

```sh
dart pub global activate -s path .
```

Or from git:

```sh
dart pub global activate -s git https://github.com/dart-lang/ai.git \
  --git-path pkgs/dart_mcp_server/
```

And then, assuming the pub cache bin dir is [on your PATH][set-up-path], the
`dart_mcp_server` command will run it, and recompile as necessary.

[set-up-path]: https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path

**Note:**: For some clients, depending on how they launch the MCP server and how
tolerant they are, you may need to compile it to exe to avoid extra output on
stdout:

```sh
dart compile exe bin/main.dart
```

And then provide the path to the executable instead of using the globally
activated `dart_mcp_server` command.

### With the example WorkflowBot

After compiling the binary, you can run the example [workflow bot][workflow_bot]
to interact with the server. Note that the workflow bot sets the current
directory as the root directory, so if your server expects a certain root
directory you will want to run the command below from there (and alter the
paths as necessary). For example, you may want to run this command from the
directory of the app you wish to test the server against.

[workflow_bot]: https://github.com/dart-lang/ai/tree/main/mcp_examples/bin/workflow_bot


```dart
dart pub add "dart_mcp_examples:{git: {url: https://github.com/dart-lang/ai.git, path: mcp_examples}}"
dart run dart_mcp_examples:workflow_client --server dart_mcp_server
```

### With Cursor

The following button should work for most users:

[![Add to Cursor](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/install-mcp?name=dart_tooling&config=eyJ0eXBlIjoic3RkaW8iLCJjb21tYW5kIjoiZGFydCBtY3Atc2VydmVyIC0tZXhwZXJpbWVudGFsLW1jcC1zZXJ2ZXIgLS1mb3JjZS1yb290cy1mYWxsYmFjayJ9)

To manually install it, go to Cursor -> Settings -> Cursor Settings and select "MCP".

Then, click "Add new global MCP server".

If you are directly editing your mcp.json file, it should look like this:

```json
{
  "mcpServers": {
    "dart_mcp": {
      "command": "dart",
      "args": [
        "mcp-server",
        "--experimental-mcp-server",
        "--force-roots-fallback"
      ]
    }
  }
}
```

Each time you make changes to the server, you'll need to restart the server on
the MCP configuration page or reload the Cursor window (Developer: Reload Window
from the Command Palette) to see the changes.

## Development

For local development, use the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

1. Run the inspector with no arguments:
    ```shell
    npx @modelcontextprotocol/inspector
    ```

2. Open the MCP Inspector in the browser and enter `dart_mcp_server` in
the "Command" field.

3. Click "Connect" to connect to the server and debug using the MCP Inspector.
