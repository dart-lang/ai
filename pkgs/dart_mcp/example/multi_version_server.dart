// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// One [MCPServer] subclass, serving one tool to 2026-07-28 clients and to
/// clients on the revisions before it.
///
/// With no arguments it serves stdio, where
/// `example/multi_version_client.dart` drives it. With `--http` it serves the
/// same class over Streamable HTTP, the transport 2026-07-28 added, and prints
/// two `curl` commands. The tool answers with an [InputRequiredResult] either
/// way; on stdio this package sends that as the `elicitation/create` an older
/// client has.
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:dart_mcp/streamable_http.dart';

void main(List<String> args) async {
  if (args.contains('--http')) return _serveStreamableHttp();
  // One long-lived server for the one connection stdio has.
  MCPServerWithInputRequired(stdioChannel(input: io.stdin, output: io.stdout));
}

/// Serves [MCPServerWithInputRequired] over Streamable HTTP on a free port.
///
/// `example/streamable_http_server.dart` is the example for this transport and
/// explains why the host checks the path and the `Origin` header itself.
Future<void> _serveStreamableHttp() async {
  const path = '/mcp';
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  final endpoint = 'http://${server.address.host}:${server.port}$path';

  server.listen((request) async {
    // The handler reads no path; the one this server answers on is the host's
    // to choose and to enforce.
    if (request.uri.path != path) {
      request.response
        ..statusCode = io.HttpStatus.notFound
        ..contentLength = 0;
      await request.response.close();
      return;
    }

    // No `Origin` is valid here: nothing in this example is meant to be
    // driven from a page. The peer example explains what that check is for.
    if (request.headers['origin'] != null) {
      request.response
        ..statusCode = io.HttpStatus.forbidden
        ..contentLength = 0;
      await request.response.close();
      return;
    }
    try {
      // Every POST gets its own server. The tool keeps nothing between its
      // two calls; the second one carries the answer.
      await handleStreamableHttpRequest(
        request,
        MCPServerWithInputRequired.new,
      );
    } catch (error) {
      io.stderr.writeln('request failed: $error');
    }
  });

  print(
    '''
Listening on $endpoint

# `greet` asks who to greet. This first call answers `input_required`.
${_callGreet(endpoint, 1, '')}
# The client answers and calls again, under the key the result asked on. The
# retry is an independent request, so it carries a new `id`. A stdio client is
# asked for the same thing as an `elicitation/create` request.
${_callGreet(endpoint, 2, '\n      "inputResponses": {"name": $_accepted},')}''',
  );
}

/// An accepted form elicitation, as a client sends one back.
const _accepted = '{"action": "accept", "content": {"name": "world"}}';

/// The `curl` command calling `greet` on [endpoint] as [id], with
/// [inputResponses].
///
/// The `_meta` envelope replaces the `initialize` handshake on this revision,
/// and the capabilities it carries have to cover what the tool asks for.
String _callGreet(String endpoint, int id, String inputResponses) => '''
curl -sS $endpoint \\
  -H 'Content-Type: application/json' \\
  -H 'Accept: application/json, text/event-stream' \\
  -H 'MCP-Protocol-Version: 2026-07-28' \\
  -H 'Mcp-Method: tools/call' -H 'Mcp-Name: greet' \\
  -d '{
    "jsonrpc": "2.0", "id": $id, "method": "tools/call",
    "params": {
      "name": "greet",$inputResponses
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": {"name": "curl", "version": "0"},
        "io.modelcontextprotocol/clientCapabilities": {
          "elicitation": {"form": {}}
        }
      }
    }
  }'
''';

/// A server with one tool that needs a value from the user before it can
/// answer.
///
/// The tool is written once, for 2026-07-28, and never reads
/// [MCPServer.protocolVersion].
base class MCPServerWithInputRequired extends MCPServer with ToolsSupport {
  MCPServerWithInputRequired(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server which serves several revisions',
          version: '0.1.0',
        ),
        instructions: 'Call `greet` and answer what it asks for',
      ) {
    registerTool(greetTool, _greet);
  }

  /// A tool that greets a name it asks the client to collect.
  final greetTool = Tool(
    name: 'greet',
    description: 'greets a name it asks the client to collect',
    inputSchema: Schema.object(),
  );

  /// The implementation of the `greet` tool, asking for a name on the first
  /// call and greeting the answer the second call carries.
  CallToolResponse _greet(CallToolRequest request) {
    if (request.elicitResult('name') case final answer?) {
      // `decline` and `cancel` both leave the tool without a name, as does an
      // `accept` that carries no content.
      final content =
          answer.action == ElicitationAction.accept ? answer.content : null;
      final name = content?['name'];
      return CallToolResult(
        content: [
          Content.text(
            text: name == null ? 'Nothing to greet.' : 'Hello, $name!',
          ),
        ],
        isError: name == null,
      );
    }
    final askForAName = ElicitRequest.form(
      message: 'Who should I greet?',
      requestedSchema: Schema.object(
        properties: {'name': Schema.string()},
        required: ['name'],
      ),
    );
    return InputRequiredResult(
      inputRequests: {'name': InputRequest.elicit(askForAName)},
    );
  }
}
