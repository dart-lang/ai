// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:test/test.dart';

final class _ElicitingServer extends MCPServer
    with LoggingSupport, ToolsSupport, ElicitationRequestSupport {
  _ElicitingServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(name: 'test', version: '0.1.0'),
      ) {
    registerTool(Tool(name: 'test/ask', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await elicit(
        ElicitRequest(message: 'need input', requestedSchema: ObjectSchema()),
      );
      return CallToolResult(content: [TextContent(text: 'asked')]);
    });
    registerTool(Tool(name: 'test/no-mode', inputSchema: ObjectSchema()), (
      _,
    ) async {
      // The 2025-11-25 revision lets a server leave `mode` out of a form
      // request, and no constructor here builds one without it.
      await elicit(
        <String, Object?>{
              Keys.message: 'need input',
              Keys.requestedSchema: ObjectSchema(),
            }
            as ElicitRequest,
      );
      return CallToolResult(content: [TextContent(text: 'asked')]);
    });
    registerTool(Tool(name: 'test/unknown', inputSchema: ObjectSchema()), (
      _,
    ) async {
      // Cast the way `ServerConnection` does when it reads a request off the
      // wire, since no constructor here can name an unknown mode.
      await elicit(
        <String, Object?>{Keys.mode: 'voice', Keys.message: 'speak up'}
            as ElicitRequest,
      );
      return CallToolResult(content: [TextContent(text: 'asked')]);
    });
    registerTool(Tool(name: 'test/send', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await elicit(
        ElicitRequest.url(
          message: 'sign in',
          url: 'https://e.test',
          elicitationId: 'e1',
        ),
      );
      return CallToolResult(content: [TextContent(text: 'sent')]);
    });
  }
}

Future<Map<String, Object?>?> _call(
  String tool,
  ClientCapabilities capabilities, {
  ProtocolVersion protocolVersion = ProtocolVersion.v2025_11_25,
}) => handleRequestScopedMessage(
  {
    Keys.jsonrpc: '2.0',
    Keys.id: 1,
    Keys.method: CallToolRequest.methodName,
    Keys.params: {Keys.name: tool},
  },
  MCPServerInitialization(
    protocolVersion: protocolVersion,
    clientCapabilities: capabilities,
  ),
  _ElicitingServer.new,
);

const _missingCapability = McpErrorCodes.missingRequiredClientCapability;

Object? _errorCode(Map<String, Object?> result) =>
    (result[Keys.error] as Map<String, Object?>)[Keys.code];

/// On 2025-11-25, a call that clears the capability check reaches the
/// request-scoped transport and fails there.
final _clearedTheCheck = isNot(_missingCapability);

Object? _requiredCapabilities(Map<String, Object?> result) {
  expect(_errorCode(result), _missingCapability);
  final error = result[Keys.error] as Map<String, Object?>;
  // In memory the data skips the JSON round trip and stays an untyped map.
  return (error[Keys.data] as Map)[Keys.requiredCapabilities];
}

void main() {
  test('a tool which elicits fails with the missing capability code', () async {
    final result = await _call('test/ask', ClientCapabilities());

    expect(_requiredCapabilities(result!), {
      Keys.elicitation: {Keys.form: <String, Object?>{}},
    });
    expect(
      (result[Keys.error] as Map<String, Object?>)[Keys.message],
      contains('elicitation.form'),
    );
    expect(result[Keys.result], isNull);
  });

  test('the error names the mode the request needs', () async {
    final result = await _call(
      'test/send',
      ClientCapabilities(elicitation: ElicitationCapability(form: {})),
    );

    expect(_requiredCapabilities(result!), {
      Keys.elicitation: {Keys.url: <String, Object?>{}},
    });
    expect(
      (result[Keys.error] as Map<String, Object?>)[Keys.message],
      contains('elicitation.url'),
    );
  });

  test('2026-07-28 rejects both modes before capability checks', () async {
    for (final (tool, capabilities) in [
      ('test/ask', ClientCapabilities()),
      (
        'test/ask',
        ClientCapabilities(elicitation: ElicitationCapability(form: {})),
      ),
      ('test/send', ClientCapabilities()),
      (
        'test/send',
        ClientCapabilities(elicitation: ElicitationCapability(url: {})),
      ),
      ('test/no-mode', ClientCapabilities()),
      ('test/unknown', ClientCapabilities()),
    ]) {
      final result = await _call(
        tool,
        capabilities,
        protocolVersion: ProtocolVersion.v2026_07_28,
      );

      expect(_errorCode(result!), error_code.INTERNAL_ERROR);
      expect(
        (result[Keys.error] as Map<String, Object?>)[Keys.message],
        allOf(
          contains(
            '2026-07-28 does not have '
            '${ElicitRequest.methodName}',
          ),
          contains('InputRequiredResult'),
        ),
      );
    }
  });

  test('a revision before 2025-06-18 rejects elicitation too', () async {
    for (final protocolVersion in [
      ProtocolVersion.v2024_11_05,
      ProtocolVersion.v2025_03_26,
    ]) {
      // The capability is declared, so reaching the version error shows the
      // version check runs before it on these revisions too.
      final result = await _call(
        'test/ask',
        ClientCapabilities(elicitation: ElicitationCapability(form: {})),
        protocolVersion: protocolVersion,
      );

      expect(_errorCode(result!), error_code.INTERNAL_ERROR);
      expect(
        (result[Keys.error] as Map<String, Object?>)[Keys.message],
        allOf(
          contains(
            '${protocolVersion.versionString} does not have '
            '${ElicitRequest.methodName}',
          ),
          // Neither revision has an `InputRequiredResult` to send instead, so
          // the error must not send the caller after one.
          isNot(contains('InputRequiredResult')),
        ),
      );
    }
  });

  test('naming one mode does not sign a client up for the other', () async {
    final result = await _call(
      'test/ask',
      ClientCapabilities(elicitation: ElicitationCapability(url: {})),
    );

    expect(_requiredCapabilities(result!), {
      Keys.elicitation: {Keys.form: <String, Object?>{}},
    });
  });

  test('a voice-only client does not clear the form check', () async {
    final result = await _call(
      'test/ask',
      ClientCapabilities(
        elicitation: ElicitationCapability.fromMap({
          'voice': <String, Object?>{},
        }),
      ),
    );

    expect(_requiredCapabilities(result!), {
      Keys.elicitation: {Keys.form: <String, Object?>{}},
    });
  });

  test('elicitation with no mode named clears the form check', () async {
    final result = await _call(
      'test/ask',
      ClientCapabilities(elicitation: ElicitationCapability()),
    );

    expect(_errorCode(result!), _clearedTheCheck);
  });

  test('naming both modes clears either check', () async {
    final capabilities = ClientCapabilities(
      elicitation: ElicitationCapability(form: {}, url: {}),
    );

    expect(
      _errorCode((await _call('test/ask', capabilities))!),
      _clearedTheCheck,
    );
    expect(
      _errorCode((await _call('test/send', capabilities))!),
      _clearedTheCheck,
    );
  });

  test('a url request needs the url mode, not just elicitation', () async {
    final noElicitation = await _call('test/send', ClientCapabilities());
    expect(_requiredCapabilities(noElicitation!), {
      Keys.elicitation: {Keys.url: <String, Object?>{}},
    });

    final noModeNamed = await _call(
      'test/send',
      ClientCapabilities(elicitation: ElicitationCapability()),
    );
    expect(_requiredCapabilities(noModeNamed!), {
      Keys.elicitation: {Keys.url: <String, Object?>{}},
    });
  });

  test('an omitted mode is held to the form capability', () async {
    final result = await _call(
      'test/no-mode',
      ClientCapabilities(elicitation: ElicitationCapability(url: {})),
    );

    expect(_requiredCapabilities(result!), {
      Keys.elicitation: {Keys.form: <String, Object?>{}},
    });
  });

  test('an unrecognized mode answers with invalid params', () async {
    for (final capabilities in [
      ElicitationCapability(url: {}),
      ElicitationCapability(form: {}),
    ]) {
      final result = await _call(
        'test/unknown',
        ClientCapabilities(elicitation: capabilities),
      );

      expect(_errorCode(result!), error_code.INVALID_PARAMS);
      expect(
        (result[Keys.error] as Map<String, Object?>)[Keys.message],
        allOf([
          contains('"voice"'),
          for (final mode in ElicitationMode.values) contains(mode.name),
        ]),
        reason: 'the rejection names the value and every mode it could be',
      );
    }
  });
}
