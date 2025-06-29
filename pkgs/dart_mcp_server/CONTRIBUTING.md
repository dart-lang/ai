## Development

For local development, use the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

1. Run the inspector with no arguments:
    ```shell
    npx @modelcontextprotocol/inspector
    ```

2. Open the MCP Inspector in the browser and enter `dart_mcp_server` in
the "Command" field.

3. Click "Connect" to connect to the server and debug using the MCP Inspector.

## Testing your changes with an MCP client

### Running the server from source

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

After compiling the binary, you can run the example [workflow client][workflow_client]
to interact with the server. Note that the workflow bot sets the current
directory as the root directory, so if your server expects a certain root
directory you will want to run the command below from there (and alter the
paths as necessary). For example, you may want to run this command from the
directory of the app you wish to test the server against.

[workflow_client]: https://github.com/dart-lang/ai/tree/main/mcp_examples/bin/workflow_client.dart


```dart
dart pub add "dart_mcp_examples:{git: {url: https://github.com/dart-lang/ai.git, path: mcp_examples}}"
dart run dart_mcp_examples:workflow_client --server dart_mcp_server
```

### With Cursor

Modify your `mcp.json` file to run your locally compiled server instead of using the
server from the Dart SDK.

Each time you make changes to the server, you'll need to restart the server on
the MCP configuration page or reload the Cursor window (**Developer: Reload Window**
from the Command Palette) to see the changes.