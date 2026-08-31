// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:stream_channel/stream_channel.dart';
import 'package:stream_transform/stream_transform.dart';

import '../api/api.dart';
import '../utils/constants.dart';
import '../utils/json_rpc_2_object.dart';
import '../utils/sse.dart' show sseMessageStream;
import '../utils/streamable_http.dart';

/// Creates a [StreamChannel] which POSTs each JSON-RPC message to [uri].
///
/// [protocolVersion] must have [ProtocolVersion.supportsStreamableHttp] and is
/// written to `_meta` and `MCP-Protocol-Version`. [clientCapabilities] and
/// [clientInfo] merge into `_meta`. JSON replies use `jsonDecode` and SSE
/// replies use [sseMessageStream]. A failed POST is a JSON-RPC error for that
/// request id, or an error on the channel itself when it carried a
/// notification, which has no id to carry one. A response stream that ends
/// without answering the request fails it the same way. A `202` on a
/// notification is not an inbound message. Valid `x-mcp-header` annotations
/// from `tools/list` are mirrored on later `tools/call` requests; invalid tool
/// definitions are dropped. Does not send `initialize`.
StreamChannel<Map<String, Object?>> streamableHttpClientChannel(
  Uri uri, {
  required ProtocolVersion protocolVersion,
  required ClientCapabilities clientCapabilities,
  Implementation? clientInfo,
}) {
  if (!protocolVersion.supportsStreamableHttp) {
    final supportedVersions = ProtocolVersion.values
        .where((version) => version.supportsStreamableHttp)
        .map((version) => version.versionString)
        .join(', ');
    throw ArgumentError.value(
      protocolVersion.versionString,
      Keys.protocolVersion,
      'The Streamable HTTP client channel only allows one of: '
      '$supportedVersions',
    );
  }

  final controller = StreamChannelController<Map<String, Object?>>();
  final httpClient = HttpClient();
  final state = _StreamableHttpClientState();
  controller.local.stream
      .tap(null, onDone: () => httpClient.close(force: true))
      .concurrentAsyncExpand(
        (message) => _sendStreamableHttpMessage(
          httpClient,
          uri,
          message,
          protocolVersion,
          clientCapabilities,
          clientInfo,
          state,
        ),
      )
      .listen(
        controller.local.sink.add,
        onError: controller.local.sink.addError,
        onDone: controller.local.sink.close,
      );
  return controller.foreign;
}

/// Sends one JSON-RPC [message] and emits each message in its response.
Stream<Map<String, Object?>> _sendStreamableHttpMessage(
  HttpClient httpClient,
  Uri uri,
  Map<String, Object?> message,
  ProtocolVersion protocolVersion,
  ClientCapabilities clientCapabilities,
  Implementation? clientInfo,
  _StreamableHttpClientState state,
) async* {
  // Shape errors happen before this turns true, transport errors after.
  var posting = false;
  try {
    final object = JsonRpc2Object.fromMap(message);
    final method = object.method;
    if (object.kind == JsonRpc2Kind.response || method == null) {
      throw ArgumentError.value(
        message,
        Keys.message,
        'Streamable HTTP only allows JSON-RPC requests or notifications. '
        'Got ${object.kind.name} with method $method.',
      );
    }

    final params = (message[Keys.params] as Map?)?.cast<String, Object?>();
    final meta = (params?[Keys.meta] as Map?)?.cast<String, Object?>();
    final body = <String, Object?>{
      ...message,
      Keys.params: <String, Object?>{
        ...?params,
        Keys.meta: <String, Object?>{
          ...?meta,
          Keys.protocolVersionMeta: protocolVersion.versionString,
          Keys.clientCapabilitiesMeta: clientCapabilities,
          if (clientInfo != null) Keys.clientInfoMeta: clientInfo,
        },
      },
    };

    final nameParam =
        object.kind == JsonRpc2Kind.request ? mcpNameParams[method] : null;
    final rawName = nameParam == null ? null : params?[nameParam];
    if (nameParam != null && rawName is! String) {
      throw ArgumentError.value(
        rawName,
        nameParam,
        '$method requires a String $nameParam parameter. '
        'Got ${rawName.runtimeType}.',
      );
    }

    state.recordOutgoing(message, method);
    // Resolve mirrored headers before opening the POST so a shape error does
    // not leave an unsent request hanging.
    final extraHeaders =
        object.kind == JsonRpc2Kind.request
            ? state.headersFor(message)
            : const <String, String>{};
    posting = true;
    final request = await httpClient.postUrl(uri);
    request.headers
      ..contentType = ContentType.json
      ..set(
        HttpHeaders.acceptHeader,
        '${ContentType.json.mimeType}, $eventStreamMimeType',
      )
      ..set(protocolVersionHeader, protocolVersion.versionString);

    if (object.kind == JsonRpc2Kind.request) {
      request.headers.set(mcpMethodHeader, method);
      if (rawName is String) {
        request.headers.set(mcpNameHeader, _encodeSentinel(rawName));
      }
      for (final MapEntry(:key, :value) in extraHeaders.entries) {
        request.headers.set(key, value);
      }
    }

    request.write(jsonEncode(body));
    final response = await request.close();
    if (response.statusCode == HttpStatus.accepted) {
      await response.drain<void>();
      if (object.kind == JsonRpc2Kind.notification) return;
      throw StateError(
        'A Streamable HTTP request must return application/json or '
        'text/event-stream. Got HTTP ${HttpStatus.accepted}.',
      );
    }

    final responseType = response.headers.contentType?.mimeType;
    final wantsResponse = message.containsKey(Keys.id);
    if (responseType == ContentType.json.mimeType) {
      final decoded =
          (jsonDecode(await utf8.decodeStream(response)) as Map)
              .cast<String, Object?>();
      if (!wantsResponse) {
        throw StateError(
          'A notification must be answered with ${HttpStatus.accepted}. Got '
          'HTTP ${response.statusCode} with a ${ContentType.json.mimeType} '
          'body instead.',
        );
      }
      if (decoded[Keys.id] != message[Keys.id]) {
        throw StateError(
          'The JSON response for request ${message[Keys.id]} carried id '
          '${decoded[Keys.id]} instead.',
        );
      }
      yield state.recordIncoming(decoded);
      return;
    }
    if (responseType == eventStreamMimeType) {
      var answered = false;
      await for (final event in sseMessageStream(response)) {
        if (event[Keys.id] == message[Keys.id] &&
            (event.containsKey(Keys.result) || event.containsKey(Keys.error))) {
          answered = true;
        }
        yield state.recordIncoming(event);
      }
      if (wantsResponse && !answered) {
        throw StateError(
          'The response stream for request ${message[Keys.id]} ended without '
          'a response.',
        );
      }
      return;
    }
    final responseBody = await utf8.decodeStream(response);
    throw UnsupportedError(
      'A Streamable HTTP request must return ${ContentType.json.mimeType} or '
      '$eventStreamMimeType. Got HTTP ${response.statusCode} '
      '"$responseType" with body "$responseBody".',
    );
  } catch (error, stackTrace) {
    if (!message.containsKey(Keys.id)) {
      // A notification has no id to attach a JSON-RPC error to. A message this
      // client never sent is the caller's to fix, but a POST that failed on
      // the wire has nothing else to report it.
      if (posting) Error.throwWithStackTrace(error, stackTrace);
      return;
    }
    yield state.recordIncoming({
      Keys.jsonrpc: '2.0',
      Keys.id: message[Keys.id],
      Keys.error: {
        Keys.code: error_code.SERVER_ERROR,
        Keys.message: error.toString(),
      },
    });
  }
}

/// Request state shared by the POSTs on one client channel.
final class _StreamableHttpClientState {
  final _listToolsRequestIds = <Object?, bool>{};
  final _toolHeaders = <String, List<_McpHeaderDeclaration>>{};

  void recordOutgoing(Map<String, Object?> message, String method) {
    if (method == ListToolsRequest.methodName && message.containsKey(Keys.id)) {
      final params = message[Keys.params];
      final cursor =
          params is Map<String, Object?> ? params[Keys.cursor] : null;
      _listToolsRequestIds[message[Keys.id]] = cursor == null;
    }
  }

  Map<String, String> headersFor(Map<String, Object?> message) {
    if (message[Keys.method] != CallToolRequest.methodName) return const {};
    final params = message[Keys.params];
    if (params is! Map<String, Object?>) {
      throw ArgumentError.value(
        params,
        Keys.params,
        '${CallToolRequest.methodName} requires a params object. '
        'Got ${params.runtimeType}.',
      );
    }
    final name = params[Keys.name];
    final arguments = params[Keys.arguments];
    if (arguments is! Map<String, Object?>?) {
      throw ArgumentError.value(
        arguments,
        Keys.arguments,
        '${CallToolRequest.methodName} requires ${Keys.arguments} to be an '
        'object. Got ${arguments.runtimeType}.',
      );
    }
    if (name is! String || arguments == null) return const {};
    final declarations = _toolHeaders[name];
    if (declarations == null) return const {};
    final headers = <String, String>{};
    for (final declaration in declarations) {
      final value = _valueAtPath(arguments, declaration.path);
      final encoded = switch ((declaration.type, value)) {
        (final String type, final String value)
            when type == JsonType.string.typeName =>
          _encodeSentinel(value),
        (final String type, final num value)
            when type == JsonType.int.typeName &&
                value.isFinite &&
                value == value.roundToDouble() &&
                value >= _minimumSafeInteger &&
                value <= _maximumSafeInteger =>
          '${value.toInt()}',
        (final String type, final bool value)
            when type == JsonType.bool.typeName =>
          '$value',
        _ => null,
      };
      if (encoded == null) {
        if (value == null) continue;
        throw ArgumentError.value(
          value,
          declaration.path.join('.'),
          'cannot be mirrored onto ${declaration.header}. The tool declares '
          'it as ${declaration.type}.',
        );
      }
      headers['$mcpParamHeaderPrefix${declaration.header}'] = encoded;
    }
    return headers;
  }

  Map<String, Object?> recordIncoming(Map<String, Object?> message) {
    if (message[Keys.method] == ToolListChangedNotification.methodName) {
      _toolHeaders.clear();
      return message;
    }
    final firstPage = _listToolsRequestIds.remove(message[Keys.id]);
    if (firstPage == null) return message;
    final result = message[Keys.result];
    if (result is! Map<String, Object?>) return message;
    final tools = result[Keys.tools];
    if (tools is! List) return message;
    // A page carrying no cursor is a fresh snapshot, so anything it leaves out
    // is gone, not waiting on a later page.
    if (firstPage) _toolHeaders.clear();
    final validTools = <Object?>[];
    for (final tool in tools) {
      if (tool is! Map<String, Object?>) continue;
      final name = tool[Keys.name];
      final inputSchema = tool[Keys.inputSchema];
      if (name is! String || inputSchema is! Map<String, Object?>) continue;
      final declarations = _mcpHeaderDeclarations(inputSchema);
      if (declarations == null) continue;
      _toolHeaders[name] = declarations;
      validTools.add(tool);
    }
    return {
      ...message,
      Keys.result: {...result, Keys.tools: validTools},
    };
  }
}

typedef _McpHeaderDeclaration =
    ({List<String> path, String header, String type});

/// Reads valid custom header annotations from a tool input [schema].
List<_McpHeaderDeclaration>? _mcpHeaderDeclarations(
  Map<String, Object?> schema,
) {
  final declarations = <_McpHeaderDeclaration>[];
  final seen = <String>{};
  bool visit(Object? node, List<String> path, {required bool reachable}) {
    if (node is! Map<String, Object?>) return true;
    if (node.containsKey(Keys.xMcpHeader)) {
      final header = node[Keys.xMcpHeader];
      final type = node[Keys.type];
      if (!reachable ||
          path.isEmpty ||
          header is! String ||
          !_httpToken.hasMatch(header) ||
          (type != JsonType.string.typeName &&
              type != JsonType.int.typeName &&
              type != JsonType.bool.typeName) ||
          !seen.add(header.toLowerCase())) {
        return false;
      }
      declarations.add((path: path, header: header, type: type as String));
    }
    final properties = node[Keys.properties];
    if (properties is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in properties.entries) {
        if (!visit(value, [...path, key], reachable: reachable)) return false;
      }
    }
    for (final keyword in _subschemaKeywords) {
      final subschema = node[keyword];
      if (subschema == null) continue;
      final branches =
          subschema is List
              ? subschema
              : subschema is Map<String, Object?> &&
                  _mapValuedSubschemaKeywords.contains(keyword)
              ? subschema.values
              : [subschema];
      for (final branch in branches) {
        if (!visit(branch, [...path, keyword], reachable: false)) return false;
      }
    }
    return true;
  }

  return visit(schema, const [], reachable: true) ? declarations : null;
}

Object? _valueAtPath(Map<String, Object?> arguments, List<String> path) {
  Object? node = arguments;
  for (final key in path) {
    if (node is! Map<String, Object?>) return null;
    node = node[key];
  }
  return node;
}

const _subschemaKeywords = {
  Keys.items,
  Keys.prefixItems,
  Keys.additionalProperties,
  Keys.unevaluatedProperties,
  Keys.unevaluatedItems,
  Keys.propertyNames,
  Keys.patternProperties,
  Keys.oneOf,
  Keys.anyOf,
  Keys.allOf,
  Keys.not,
  'contains',
  'contentSchema',
  'dependencies',
  'additionalItems',
  'dependentSchemas',
  'if',
  'then',
  'else',
  r'$defs',
  'definitions',
};

const _mapValuedSubschemaKeywords = {
  Keys.patternProperties,
  'dependencies',
  'dependentSchemas',
  r'$defs',
  'definitions',
};

final _httpToken = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

const _minimumSafeInteger = -9007199254740991;
const _maximumSafeInteger = 9007199254740991;

/// Encodes [value] when it is not a safe plain ASCII header value.
String _encodeSentinel(String value) {
  final matchesSentinel = value.startsWith('=?base64?') && value.endsWith('?=');
  final needsEncoding =
      value.isEmpty ||
      value != value.trim() ||
      matchesSentinel ||
      value.codeUnits.any(
        (unit) => unit != 0x09 && (unit < 0x20 || unit > 0x7e),
      );
  return needsEncoding
      ? '=?base64?${base64.encode(utf8.encode(value))}?='
      : value;
}
