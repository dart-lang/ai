// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/streamable_http.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

/// Runs the client fixture used by the MCP conformance suite.
///
/// The suite appends its endpoint as the last argument and names the scenario
/// in `MCP_CONFORMANCE_SCENARIO`. Run the suite against this fixture with
///
/// ```sh
/// npx @modelcontextprotocol/conformance@0.2.0-alpha.11 \
///   client --command "dart run tool/conformance_client.dart" \
///   --requirements 2026-07-28
/// ```
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Expected the conformance endpoint as the last argument.');
    exitCode = 2;
    return;
  }
  final endpoint = Uri.parse(arguments.last);
  final environment = Platform.environment;
  final scenario = environment[_scenarioVariable];
  if (scenario == null) {
    stderr.writeln('Expected a scenario name in $_scenarioVariable.');
    exitCode = 2;
    return;
  }
  final rawContext = environment[_contextVariable];
  final context =
      rawContext == null
          ? const <String, Object?>{}
          : (jsonDecode(rawContext) as Map).cast<String, Object?>();

  var protocolVersion =
      ProtocolVersion.tryParse(environment[_versionVariable] ?? '') ??
      ProtocolVersion.v2026_07_28;
  // The request-metadata scenario turns down the first offered version.
  // Retrying once on a version from that reply is part of the scenario.
  for (var attempt = 0; ; attempt++) {
    try {
      await _run(scenario, endpoint, protocolVersion, context);
      return;
    } on RpcException catch (error) {
      final offered = attempt == 0 ? _offeredVersion(error) : null;
      if (offered == null) {
        stderr.writeln('$scenario: $error');
        exitCode = 1;
        return;
      }
      protocolVersion = offered;
    }
  }
}

const _scenarioVariable = 'MCP_CONFORMANCE_SCENARIO';
const _versionVariable = 'MCP_CONFORMANCE_PROTOCOL_VERSION';
const _contextVariable = 'MCP_CONFORMANCE_CONTEXT';

const _addNumbersTool = 'add_numbers';
const _echoStateTool = 'test_mrtr_echo_state';
const _noStateTool = 'test_mrtr_no_state';
const _unrelatedTool = 'test_mrtr_unrelated';
const _noResultTypeTool = 'test_mrtr_no_result_type';

/// Connects to [endpoint] and drives the traffic [scenario] scores.
Future<void> _run(
  String scenario,
  Uri endpoint,
  ProtocolVersion protocolVersion,
  Map<String, Object?> context,
) async {
  final client = _ConformanceClient();
  final connection = client.connectServer(
    streamableHttpClientChannel(
      endpoint,
      protocolVersion: protocolVersion,
      clientCapabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  // This revision settles the version on the transport outside the handshake,
  // and the multi-round retry path reads it off the connection.
  connection.protocolVersion = protocolVersion;
  try {
    // Every scenario lists first. The header scenarios score the list request
    // itself, and a later call mirrors the annotations the list carried.
    final tools = await connection.listTools();
    switch (scenario) {
      case 'tools_call':
        await connection.callTool(
          CallToolRequest(name: _addNumbersTool, arguments: {'a': 5, 'b': 7}),
        );
      case 'http-standard-headers':
        await _exerciseNamedMethods(connection, tools);
      case 'http-custom-headers':
        for (final call in _toolCalls(context)) {
          await connection.callTool(call);
        }
      case 'http-invalid-tool-headers':
        // The transport drops tools with invalid header annotations, so the
        // list only holds the ones it kept. Call each of them.
        for (final tool in tools.tools) {
          await connection.callTool(
            CallToolRequest(name: tool.name, arguments: const {}),
          );
        }
      case 'sep-2322-client-request-state':
        await _driveMultiRound(connection);
    }
  } finally {
    await client.shutdown();
  }
}

/// Calls each method that carries a name in a header.
///
/// The header scenario reads that name off `tools/call`, `resources/read` and
/// `prompts/get`. Each one has to be sent for its check to be scored.
Future<void> _exerciseNamedMethods(
  ServerConnection connection,
  ListToolsResult tools,
) async {
  if (tools.tools.isNotEmpty) {
    await connection.callTool(
      CallToolRequest(name: tools.tools.first.name, arguments: const {}),
    );
  }
  final resources = (await connection.listResources()).resources;
  if (resources.isNotEmpty) {
    await connection.readResource(
      ReadResourceRequest(uri: resources.first.uri),
    );
  }
  final prompts = (await connection.listPrompts()).prompts;
  if (prompts.isNotEmpty) {
    await connection.getPrompt(GetPromptRequest(name: prompts.first.name));
  }
}

/// Calls each tool the request-state scenario scores.
///
/// The unrelated call starts together with the multi-round one, so the
/// scenario can see that one call's state stays out of another's.
Future<void> _driveMultiRound(ServerConnection connection) async {
  await Future.wait([
    connection.callTool(CallToolRequest(name: _echoStateTool)),
    connection.callTool(CallToolRequest(name: _unrelatedTool)),
  ]);
  await connection.callTool(CallToolRequest(name: _noStateTool));
  await connection.callTool(CallToolRequest(name: _noResultTypeTool));
}

/// Reads the tool calls the suite asked for out of its scenario context.
Iterable<CallToolRequest> _toolCalls(Map<String, Object?> context) sync* {
  final calls = context['toolCalls'];
  if (calls is! List) return;
  for (final call in calls) {
    if (call is! Map) continue;
    final name = call['name'];
    if (name is! String) continue;
    final arguments = call['arguments'];
    yield CallToolRequest(
      name: name,
      arguments: arguments is Map ? arguments.cast<String, Object?>() : null,
    );
  }
}

/// Picks a version this transport can speak out of a rejected handshake.
ProtocolVersion? _offeredVersion(RpcException error) {
  if (error.code != McpErrorCodes.unsupportedProtocolVersion) return null;
  final data = error.data;
  final supported = data is Map ? data['supported'] : null;
  if (supported is! List) return null;
  for (final version in supported) {
    if (version is! String) continue;
    final parsed = ProtocolVersion.tryParse(version);
    if (parsed != null && parsed.supportsStreamableHttp) return parsed;
  }
  return null;
}

/// A client that answers the input requests a multi-round result carries.
///
/// The mixins declare the roots, sampling and elicitation capabilities the
/// metadata scenario reads back out of `_meta`.
final class _ConformanceClient extends MCPClient
    with RootsSupport, SamplingSupport, ElicitationFormSupport {
  _ConformanceClient()
    : super(
        Implementation(name: 'dart_mcp conformance client', version: '0.1.0'),
      );

  @override
  ElicitResult handleElicitation(
    ElicitRequest request,
    ServerConnection connection,
  ) => ElicitResult(
    action: ElicitationAction.accept,
    content: _filled(request.requestedSchema),
  );

  @override
  CreateMessageResult handleCreateMessage(
    CreateMessageRequest request,
    Implementation serverInfo,
  ) => CreateMessageResult(
    role: Role.assistant,
    content: TextContent(text: 'conformance'),
    model: 'conformance',
  );
}

/// Answers every property [schema] asks for with a value of its type.
Map<String, Object?> _filled(ObjectSchema? schema) {
  final properties = schema?.properties;
  if (properties == null) return const {};
  final content = <String, Object?>{};
  for (final MapEntry(:key, :value) in properties.entries) {
    final type = (value as Map<String, Object?>)['type'];
    content[key] = switch (type) {
      final String type when type == JsonType.bool.typeName => true,
      final String type when type == JsonType.int.typeName => 1,
      final String type when type == JsonType.num.typeName => 1.0,
      _ => 'conformance',
    };
  }
  return content;
}
