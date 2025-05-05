The Dart Tooling MCP Server exposes Dart and Flutter development tool actions to compatible AI-assistant clients.

## Status

WIP. This package is still experimental and is likely to evolve quickly.

## Tools

| Tool Name | Feature Group | Description |
| --- | --- | --- |
| `analyze_files` | `static analysis` | Analyzes the entire project for errors. |
| `signature_help` | `static_analysis` | Gets signature information for usage at a given cursor position. |
| `resolve_workspace_symbol` | `static analysis` | Look up a symbol or symbols in all workspaces by name. |
| `dart_fix` | `static tool` | Runs `dart fix --apply` for the given project roots. |
| `dart_format` | `static tool` | Runs `dart format .` for the given project roots. |
| `pub` | `static tool` | Runs a `dart pub` command for the given project roots. |
| `get_runtime_errors` | `runtime analysis` | Retrieves the list of runtime errors that have occurred in the active Dart or Flutter application. |
| `take_screenshot` | `runtime analysis` | Takes a screenshot of the active Flutter application in its current state. |
| `get_widget_tree` | `runtime analysis` | Retrieves the widget tree from the active Flutter application. |
| `get_selected_widget` | `runtime analysis` | Retrieves the selected widget from the active Flutter application. |
| `hot_reload` | `runtime tool` | Performs a hot reload of the active Flutter application. |
| `connect_dart_tooling_daemon`* | `configuration` | Connects to the locally running Dart Tooling Daemon. |

> *Experimental: may be removed.

## Usage

To use this package, you will need to compile the `bin/main.dart` script to exe
and use the compiled path as the command in your MCP server config.

```shell
dart compile exe bin/main.dart
```

### With the example WorkflowBot

After compiling the binary, you can run the example workflow chat bot to
interact with the server. Note that the workflow bot sets the current directory
as the root directory, so if your server expects a certain root directory you
will want to run the command below from there (and alter the paths as
necessary). For example, you may want to run this command from the directory of
the app you wish to test the server against.


```dart
dart ../dart_mcp/example/workflow_client.dart --server bin/main.exe
```

### With Cursor

Go to Cursor -> Settings -> Cursor Settings and select "MCP".

Then, click "Add new global MCP server". Put in the full path to the executable
you created in the first step as the "command".

If you are directly editing your mcp.json file, it should look like this:

```yaml
{
  "mcpServers": {
    "dart_mcp": {
      "command": "<path-to-compiled-exe>",
      "args": []
    }
  }
}
```

Each time you make changes to the server, you'll need to re-run
`dart compile exe bin/main.dart` and reload the Cursor window
(Developer: Reload Window from the Command Pallete) to see the changes.

## Development

For local development, use the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

1. Run the inspector with no arguments:
    ```shell
    npx @modelcontextprotocol/inspector
    ```

2. Open the MCP Inspector in the browser and enter the path to the server
executable in the "Command" field
(e.g. `/Users/me/path/to/ai/pkgs/dart_tooling_mcp_server/bin/main.exe`).

3. Click "Connect" to connect to the server and debug using the MCP Inspector.
