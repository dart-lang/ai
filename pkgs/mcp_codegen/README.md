# MCP Codegen

[![Dart Build Status](https://img.shields.io/github/actions/workflow/status/dart-lang/ai/dart.yml?label=build)](https://github.com/dart-lang/ai/actions)

A [build_runner](https://pub.dev/packages/build_runner) generator that turns
`mcp_annotations` into concrete Model Context Protocol implementations.

Given a Dart package that uses `@MCPTool` or `@MCPServerApp` from
[`mcp_annotations`](../mcp_annotations/), this builder produces:

* **JSON tool descriptors** that can be read by any MCP-compatible client.
* **Handler stubs** that route an MCP invocation to your annotated Dart
  function.
* **Boot-strapped MCPServer** subclasses that wire everything together.

---

## Installing

Add the generator and its companion annotations package to your project:

```yaml
# pubspec.yaml
name: my_app
# ...
dependencies:
  mcp_annotations: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.0
  mcp_codegen: ^0.1.0
```

> **Note** – `mcp_codegen` should *only* appear under `dev_dependencies` as it is
> never used at runtime.

## Running the generator

```shell
# One-off build
$ dart run build_runner build

# Continuous build
$ dart run build_runner watch
```

## Configuration

The generator exposes a single option, `output_extensions`, allowing you to
change the suffix for generated files.  The default is `.mcp.g.dart`.

```yaml
# build.yaml
builders:
  mcp_codegen|mcpBuilder:
    options:
      output_extensions: '.my_mcp.g.dart'
```

## Contributing

Please see the top-level [CONTRIBUTING.md](../../CONTRIBUTING.md) file for
guidance on how to file bugs and submit pull-requests. 