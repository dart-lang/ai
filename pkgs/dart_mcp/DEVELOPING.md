# Developing dart_mcp

The repository's [contributing guide](../../CONTRIBUTING.md) covers the CLA and
code review. This file covers what is specific to this package.

## Schema

The types under `lib/src/api/` follow the schema files in the MCP specification
repository, one directory per revision:
https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema.
`ProtocolVersion` in `lib/src/api/api.dart` lists the revisions the package
knows, with the methods each one added or removed.

The stdio transport negotiates a revision from that list during `initialize`.
The Streamable HTTP transport serves 2026-07-28 only.

## Checks

CI runs these from `pkgs/dart_mcp` on the stable and dev SDKs:

```sh
dart pub get
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
dart test -p chrome,vm -c dart2wasm,dart2js,kernel,exe
```

The format check runs on the dev SDK only. Format with a dev SDK before sending
a change. The browser legs compile with dart2js and dart2wasm. Run at least one
of them locally after touching `lib/`.

## Conformance

`tool/conformance_server.dart` and `tool/conformance_client.dart` are the
fixtures for the MCP conformance suite. Each file says how to run the suite
against it.

## Changelog

Notes for unreleased work go under the top heading of `CHANGELOG.md`. Its
version carries a `-wip` suffix until release, the same as `pubspec.yaml`.
