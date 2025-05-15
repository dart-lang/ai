# Simple Client and Server

See `bin/simple_client.dart` and `bin/simple_server.dart` for a basic example of
how to use the `MCPClient` and `MCPServer` classes. These don't use any LLM to
invoke tools.

# LLM Client Integration

For a more full featured client/server example, see `bin/workflow_client.dart`.

This client accepts any number of STDIO servers to connect to via the
`--server <path>` arguments, and is a good way to test out your servers.

For example, you can use the example file system server with it as follows:

```sh
dart bin/workflow_client.dart --server "dart bin/file_system_server.dart"
```

This client uses gemini to invoke tools, and requires a gemini api key.
