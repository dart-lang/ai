# Client and Server examples

For each client or server feature, there is a corresponding example here with
the {feature}_client.dart and {feature}_server.dart file names. Sometimes
multiple features are demonstrated together where appropriate, in which case the
file name will indicate this.

To run the examples, run the client file directly, so for instance
`dart run example/tools_client.dart` with run the example client which invokes
tools, connected to the example server that provides tools
(at `example/tools_server.dart`).

`streamable_http_server.dart` has no client pair, since this package does not
have an HTTP client yet. Run it directly and it prints a `curl` command which
calls its tool. The package does not implement `server/discover` either, which
the 2026-07-28 revision requires of servers; a client that calls it gets
`-32601` back, though it can skip the call and use the server anyway.

# Full Featured Examples

See https://github.com/dart-lang/ai/tree/main/mcp_examples for some more full
featured examples using gemini to automatically invoke tools.

The example client there is also useful for testing your own server.
