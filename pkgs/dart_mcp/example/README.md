# Client and Server examples

For each client or server feature, there is a corresponding example here with
the {feature}_client.dart and {feature}_server.dart file names. Sometimes
multiple features are demonstrated together where appropriate, in which case the
file name will indicate this.

To run the examples, run the client file directly, so for instance
`dart run example/tools_client.dart` with run the example client which invokes
tools, connected to the example server that provides tools
(at `example/tools_server.dart`).

`streamable_http_server.dart` and `streamable_http_client.dart` are a pair.
Run the server first. It prints its URL. Then run
`dart run example/streamable_http_client.dart <url>` to list tools and call
`greet`. `streamableHttpClientChannel` in
`package:dart_mcp/streamable_http.dart` is the client transport.

`multi_version_server.dart` and `multi_version_client.dart` are a pair. The
client spawns the server over stdio and answers the `elicitation/create`
request that this package converts the tool's `input_required` result into.
Run the server with `--http` and it prints two `curl` commands that ask a
2026-07-28 client for the same name with an `input_required` result.

# Full Featured Examples

See https://github.com/dart-lang/ai/tree/main/mcp_examples for some more full
featured examples using gemini to automatically invoke tools.

The example client there is also useful for testing your own server.
