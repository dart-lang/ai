Experimental MCP server which exposes Dart development tool actions to clients.

## Status

WIP

## Using this package

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

## Debugging MCP Servers

For local development, use the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

1. Run the inspector with no arguments:
    ```shell
    npx @modelcontextprotocol/inspector
    ```

2. Open the MCP Inspector in the browser and enter the path to the server
executable in the "Command" field
(e.g. `/Users/me/path/to/ai/pkgs/dart_tooling_mcp_server/bin/main.exe`).

3. Click "Connect" to connect to the server and debug using the MCP Inspector.
