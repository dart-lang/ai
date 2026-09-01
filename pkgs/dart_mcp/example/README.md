# Client and Server examples

For each client or server feature, there is a corresponding example here with
the {feature}_client.dart and {feature}_server.dart file names. Sometimes
multiple features are demonstrated together where appropriate, in which case the
file name will indicate this.

To run the examples, run the client file directly, so for instance
`dart run example/tools_client.dart` with run the example client which invokes
tools, connected to the example server that provides tools
(at `example/tools_server.dart`).

`streamable_http_server.dart` has no client pair. Run it directly and it prints
a `curl` command which calls its tool. `streamableHttpClientChannel` in
`package:dart_mcp/streamable_http.dart` is the client transport.

# Full Featured Examples

See https://github.com/dart-lang/ai/tree/main/mcp_examples for some more full
featured examples using gemini to automatically invoke tools.

The example client there is also useful for testing your own server.
