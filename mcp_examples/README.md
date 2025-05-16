# LLM MCP Client Integration

This repo has an example Gemini client at `bin/workflow_client.dart`, as well
as a simple file system server at `bin/file_system_server.dart`.

This client accepts any number of STDIO servers to connect to via the
`--server <path>` arguments, and is a good way to test out your servers.

For example, you can use the example file system server with it as follows:

```sh
dart bin/workflow_client.dart --server "dart bin/file_system_server.dart"
```

This client uses gemini to invoke tools, and requires a gemini api key.
