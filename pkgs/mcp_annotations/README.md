# MCP Annotations

A lightweight annotation library for declaring [Model Context Protocol](https://modelcontextprotocol.io) (MCP) servers, tools, and parameter metadata in pure Dart.

This package is **build-time only** – it contains no runtime dependencies and should be included as a regular `dependencies:` entry in your `pubspec.yaml` alongside [`mcp_codegen`](../mcp_codegen/).

---

## Getting started

```yaml
# pubspec.yaml
name: my_app
# ...
dependencies:
  mcp_annotations: ^0.1.0
  # Only required during development / code-gen – omit on publish.
  build_runner: ^2.4.0
  mcp_codegen: ^0.1.0
```

1. Add the annotations and generator to your project as shown above.
2. Annotate your functions, methods, or `main()` entry-point.
3. Run `dart run build_runner build` (or `watch`) to generate the MCP server / tool boilerplate.

## Available annotations

| Annotation | Use-case |
| --- | --- |
| `@MCPTool` | Marks a top-level function or static method as an MCP *tool*. Optional fields let you override the tool name, description, and parameter metadata. |
| `@MCPParameter` | Provides richer metadata (title / description) for an individual parameter defined in a `@MCPTool`. |
| `@MCPServerApp` | Marks a **class or top-level function** as the entry-point for an MCP *server*. The generator emits a concrete `MCPServer` subclass, bootstrap helpers, and – for classes – an extension `run()` method for easy launching. |

See the API docs for the full list of fields and defaults.

## Example

```dart
import 'package:mcp_annotations/mcp_annotations.dart';

@MCPServerApp(name: 'demo_server', version: '0.1.0')
class MCPDemoServer {
  const MCPDemoServer();

  @MCPTool(description: 'Adds two numbers.')
  num add(num a, num b) => a + b;
}

void main(List<String> args) {
  final server = MCPDemoServer();
  server.run(args);
}
```


You can now compile the generated server and use it with any MCP-compatible client.

## Contributing

Contributions are welcome!  Please read the [CONTRIBUTING.md](../../CONTRIBUTING.md) guide before submitting a pull-request. 