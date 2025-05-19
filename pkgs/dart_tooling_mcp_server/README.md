The Dart Tooling MCP Server exposes Dart and Flutter development tool actions to compatible AI-assistant clients.

## Status

WIP. This package is still experimental and is likely to evolve quickly.

## Tools

| Tool Name | Feature Group | Description |
| --- | --- | --- |
| `analyze_files` | `static analysis` | Analyzes the entire project for errors. |
| `signature_help` | `static_analysis` | Gets signature information for usage at a given cursor position. |
| `hover` | `static_analysis` | Gets the hover information for a given cursor position. |
| `resolve_workspace_symbol` | `static analysis` | Look up a symbol or symbols in all workspaces by name. |
| `dart_fix` | `static tool` | Runs `dart fix --apply` for the given project roots. |
| `dart_format` | `static tool` | Runs `dart format .` for the given project roots. |
| `pub` | `static tool` | Runs a `dart pub` command for the given project roots. |
| `pub_dev_search` | `package search` | Searches pub.dev for packages relevant to a given search query. |
| `get_runtime_errors` | `runtime analysis` | Retrieves the list of runtime errors that have occurred in the active Dart or Flutter application. |
| `take_screenshot` | `runtime analysis` | Takes a screenshot of the active Flutter application in its current state. |
| `get_widget_tree` | `runtime analysis` | Retrieves the widget tree from the active Flutter application. |
| `get_selected_widget` | `runtime analysis` | Retrieves the selected widget from the active Flutter application. |
| `hot_reload` | `runtime tool` | Performs a hot reload of the active Flutter application. |
| `connect_dart_tooling_daemon`* | `configuration` | Connects to the locally running Dart Tooling Daemon. |
| `get_active_location` | `editor` | Gets the active cursor position in the connected editor (if available). |

> *Experimental: may be removed.

## Usage

This server only supports the STDIO transport mechanism and runs locally on
your machine. Many of the tools require that your MCP client has `roots`
support, and usage of the tools is scoped to only these directories.

The server entrypoint lives at `bin/main.dart`, and can be ran however you
choose, but the easiest way is to run it as a globally activated package.

You can globally activate it from path for local development:

```sh
dart pub global activate -s path .
```

Or from git:

```sh
dart pub global activate -s git https://github.com/dart-lang/ai.git \
  --git-path pkgs/dart_tooling_mcp_server/
```

And then, assuming the pub cache bin dir is [on your PATH][set-up-path], the
`dart_tooling_mcp_server` command will run it, and recompile as necessary.

[set-up-path]: https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path

**Note:**: For some clients, depending on how they launch the MCP server and how
tolerant they are, you may need to compile it to exe to avoid extra output on
stdout:

```sh
dart compile exe bin/main.dart
```

And then provide the path to the executable instead of using the globally
activated `dart_tooling_mcp_server` command.

### With the example WorkflowBot

After compiling the binary, you can run the example workflow chat bot to
interact with the server. Note that the workflow bot sets the current directory
as the root directory, so if your server expects a certain root directory you
will want to run the command below from there (and alter the paths as
necessary). For example, you may want to run this command from the directory of
the app you wish to test the server against.


```dart
dart ../dart_mcp/example/workflow_client.dart --server dart_tooling_mcp_server
```

### With Cursor

Go to Cursor -> Settings -> Cursor Settings and select "MCP".

Then, click "Add new global MCP server". Assuming you have already globally
activated the package and it is on  your path, you can add
`dart_tooling_mcp_server` as the command.

If you are directly editing your mcp.json file, it should look like this:

```yaml
{
  "mcpServers": {
    "dart_mcp": {
      "command": "dart_tooling_mcp_server",
      "args": []
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

2. Open the MCP Inspector in the browser and enter `dart_tooling_mcp_server` in
the "Command" field.

3. Click "Connect" to connect to the server and debug using the MCP Inspector.
