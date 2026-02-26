// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that makes an elicitation request to the client using the
/// [ElicitationRequestSupport] mixin.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';
import 'dart:math' show Random;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithElicitation(stdioChannel(input: io.stdin, output: io.stdout));
}

/// This server uses the [ElicitationRequestSupport] mixin to make elicitation
/// requests to the client.
base class MCPServerWithElicitation extends MCPServer
    with LoggingSupport, ElicitationRequestSupport, ToolsSupport {
  /// Whether or not we got approval to run the `needs_permission` tool..
  bool approved = false;

  MCPServerWithElicitation(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server which makes elicitations',
          version: '0.1.0',
        ),
        instructions: 'Handle the elicitations and ask the user for the values',
      );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(
      Tool(
        name: 'needs_permission',
        description: 'A tool that requires permission to run',
        inputSchema: Schema.object(),
      ),
      _handleNeedsPermissionTool,
    );
    return super.initialize(request);
  }

  Future<CallToolResult> _handleNeedsPermissionTool(
    CallToolRequest request,
  ) async {
    if (!approved) {
      final elicitationId = Random.secure().nextInt(999999).toString();
      // Start a simple web server on a random port.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        server.listen((HttpRequest request) async {
          switch (request.method) {
            case 'GET':
              request.response
                ..statusCode = 200
                ..headers.contentType = ContentType.html
                ..write(_permissionWebPage);
              break;
            case 'POST':
              // Read the permission radio button value from the form.
              final formContents =
                  Uri(
                    query:
                        await request
                            .cast<List<int>>()
                            .transform(const Utf8Decoder())
                            .join(),
                  ).queryParameters;
              approved = formContents['permission'] == 'yes';
              notifyElicitationComplete(
                ElicitationCompleteNotification(elicitationId: elicitationId),
              );
              await server.close();
              break;
            default:
              request.response.statusCode = HttpStatus.methodNotAllowed;
              break;
          }
          await request.response.close();
        });
      } catch (e) {
        log(LoggingLevel.warning, 'Error waiting for approval: $e');
      }

      // See https://modelcontextprotocol.io/specification/draft/client/elicitation#url-elicitation-required-error
      throw RpcException(
        McpErrorCodes.urlElicitationRequired,
        'Permission must be granted first',
        data:
            ElicitRequest.url(
                  message: 'This tool requires approval to run',
                  url: 'http://${server.address.address}:${server.port}',
                  elicitationId: elicitationId,
                )
                as Map<String, Object?>,
      );
    }

    await _startElicitationFlow();
    return CallToolResult(content: [Content.text(text: 'Success!')]);
  }

  Future<void> _startElicitationFlow() async {
    // You must wait for initialization to complete before you can make an
    // elicitation request.
    await initialized;
    ({String name, int age, String gender})? userInfo;
    while (userInfo == null) {
      userInfo = await _elicitInfo();
    }
    await _elicitUrl(userInfo, '12345');
  }

  /// Elicits a name from the user, and logs a message based on the response.
  Future<({String name, int age, String gender})?> _elicitInfo() async {
    final response = await elicit(
      ElicitRequest.form(
        message: 'I would like to ask you some personal information.',
        requestedSchema: Schema.object(
          properties: {
            'name': Schema.string(),
            'age': Schema.int(),
            'gender': Schema.string(enumValues: ['male', 'female', 'other']),
          },
        ),
      ),
    );
    switch (response.action) {
      case ElicitationAction.accept:
        final {'age': int age, 'name': String name, 'gender': String gender} =
            (response.content as Map<String, dynamic>);
        log(
          LoggingLevel.warning,
          'Hello $name! I see that you are $age years '
          'old and identify as $gender',
        );
        return (name: name, age: age, gender: gender);
      case ElicitationAction.decline:
        log(LoggingLevel.warning, 'Request for name was declined');
      case ElicitationAction.cancel:
        log(LoggingLevel.warning, 'Request for name was cancelled');
    }
    return null;
  }

  /// Elicits a URL from the user, asking them to navigate to a URL, and
  /// then logging when we get the request.
  Future<void> _elicitUrl(
    ({String name, int age, String gender}) userInfo,
    String elicitationId,
  ) async {
    // Start a simple web server on a random port.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      server.listen((HttpRequest request) async {
        switch (request.method) {
          case 'GET':
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write(_apiKeyWebPage);
            break;
          case 'POST':
            // Read the posted api key from the form.
            final formContents =
                Uri(
                  query:
                      await request
                          .cast<List<int>>()
                          .transform(const Utf8Decoder())
                          .join(),
                ).queryParameters;
            // Do not log this in real code of course!
            log(LoggingLevel.warning, 'Form Contents: $formContents');
            notifyElicitationComplete(
              ElicitationCompleteNotification(elicitationId: elicitationId),
            );
            await server.close();
            break;
          default:
            request.response.statusCode = HttpStatus.methodNotAllowed;
            break;
        }
        await request.response.close();
      });

      final response = await elicit(
        ElicitRequest.url(
          message: 'Please navigate to a URL',
          url: 'http://${server.address.address}:${server.port}',
          elicitationId: elicitationId,
        ),
      );
      switch (response.action) {
        case ElicitationAction.accept:
          log(LoggingLevel.warning, 'Request to navigate to URI was accepted');
        case ElicitationAction.decline:
          log(LoggingLevel.warning, 'Request to navigate to URI was declined');
        case ElicitationAction.cancel:
          log(LoggingLevel.warning, 'Request to navigate to URI was cancelled');
      }
    } catch (e) {
      log(LoggingLevel.warning, 'Error during URL elicitation: $e');
      await server.close();
    }
  }
}

/// The basic web page to elicit an API key from the user.
final String _apiKeyWebPage = '''
<!DOCTYPE html>
<html>
<head>
  <title>API Key Elicitation Example</title>
</head>
<body>
<form action="" method="post">
  <label for="api_key">API Key:</label>
  <input type="password" name="api_key" />
  <input type="submit" />
</form>
</body>
</html>
''';

final String _permissionWebPage = '''
<!DOCTYPE html>
<html>
<head>
  <title>Permission Elicitation Example</title>
</head>
<body>
<form action="" method="post">
  <strong>Do we have permission to run this tool?</strong><br />
  <label for="yes">Yes</label><input type="radio" name="permission" id="yes" value="yes" /><br />
  <label for="no">No</label><input type="radio" name="permission" id="no" value="no" checked /><br />
  <input type="submit" />
</form>
</body>
</html>
''';
