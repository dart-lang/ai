// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The Streamable HTTP transport described by the 2026-07-28 revision of the
/// Model Context Protocol specification,
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http.
///
/// Every POST carries a single JSON-RPC request or notification along with
/// its own client context; there is no session state between requests. A
/// request is answered on an SSE response stream if its handler emits related
/// notifications, and with a JSON body otherwise. The list and resource change
/// notifications reach `onNotification` alone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';

import 'server.dart';
import 'src/utils/constants.dart';
import 'src/utils/json_rpc_2_object.dart';

/// Decodes the `message` events in a Streamable HTTP SSE response [bytes].
///
/// Consecutive `data` fields are joined with a line feed before the JSON
/// object is decoded. An omitted or empty `event` field means the `message`
/// type. Other event types, comment lines, and events which carry no data are
/// ignored.
///
/// A frame whose data does not decode to a JSON object arrives as a
/// [FormatException] error event, and the frames behind it are still
/// delivered. An error on [bytes] itself ends the stream, since there is
/// nothing left to read.
Stream<Map<String, Object?>> sseMessageStream(Stream<List<int>> bytes) =>
    _sseMessageData(bytes).map<Map<String, Object?>>((source) {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        throw FormatException(
          'SSE data must be a JSON object, got ${decoded.runtimeType}',
          source,
        );
      }
      return decoded;
    });

/// Handles one Streamable HTTP POST [request] by validating its headers and
/// `_meta` envelope, dispatching the decoded message to a fresh server
/// created by [serverFactory] via [handleRequestScopedMessage], and writing
/// the HTTP response.
///
/// Spec-defined failures are answered with their JSON-RPC error codes and
/// HTTP statuses: 400 for a malformed message, a failed header or envelope
/// validation, an `Accept` header which is absent or does not cover both
/// response shapes, or a `Content-Type` which is not `application/json`, and
/// 404 for a method this transport does not serve. The specification requires
/// `400 Bad Request` on every `HeaderMismatch` body and names no other status
/// for content negotiation, so 406 and 415 are not used. Every one of
/// those bodies also carries the message which produced it under
/// `error.data.request`, as the rest of this package does: the decoded
/// message when there is one, the raw body text when it was not valid JSON,
/// and `null` when the body was never read into text. A non-POST request
/// is answered with 405 and an `Allow` header but no body, which is all this
/// revision defines for `GET` and `DELETE`.
///
/// The `MCP-Protocol-Version` header is checked against the versions this
/// handler implements before the `_meta` envelope is validated. A client
/// speaking another revision cannot produce this revision's `_meta` envelope,
/// so answering on the header alone is what lets it receive the `supported`
/// list it needs to renegotiate with.
///
/// Notifications are acknowledged with `202 Accepted` and not dispatched,
/// since this protocol revision defines no client-to-server notifications
/// over HTTP. This handler reads the whole request body into memory, and it
/// does not read the `Origin` header, which the specification requires a
/// server to validate and answer with 403: that check needs deployment
/// knowledge this handler does not have, so it belongs to the embedding
/// HTTP server, along with authentication and request size limits.
///
/// Responses produced by the dispatched server are written unchanged, so an
/// error a request handler throws reaches the client with whatever payload
/// `package:json_rpc_2` attached to it, including a Dart stack trace for
/// errors which are not an [RpcException]. Handlers which must not disclose
/// server internals to a remote client throw [RpcException]s instead. Until
/// something has been written the status such a body gets follows its error
/// code: an internal or server error is a 500, so a failing handler is visible
/// to intermediaries that never read the body, and a code the specification
/// has not mapped to a status keeps 200. Once a notification has gone out on
/// the stream the status was spent on it at 200, and the error goes out as the
/// last event of the stream instead.
///
/// If [serverFactory] or [MCPServer.initialize] throws, the request gets an
/// internal-error body, on the stream when one is open and with a 500 when it
/// is not, and the returned future then completes with that error so an
/// embedder awaiting it can log or rethrow it. If a client disconnects while
/// its body is still arriving there is nothing to answer, so the returned
/// future completes normally without writing a response.
///
/// `Mcp-Session-Id` and `Last-Event-ID` headers are ignored, and no session
/// id is ever minted: sessions and resumable streams were removed in this
/// revision. The `Mcp-Param-{Name}` headers this revision defines are not
/// supported either: nothing here opts into `x-mcp-header`, so no such
/// header is ever recognized, and it is ignored along with every other
/// header this handler does not read.
///
/// Notifications the server produces while handling the request go out on an
/// SSE response stream. The first one commits `text/event-stream`, and the
/// result follows it as the last event. A request answered without one gets a
/// JSON body instead. The long-lived change notifications this revision
/// delivers on a `subscriptions/listen` stream are held back from the response
/// stream, since a server emits several of them without choosing to.
/// [onNotification] sees every notification either way, held back or not.
Future<void> handleStreamableHttpRequest(
  HttpRequest request,
  MCPServerFactory serverFactory, {
  void Function(Map<String, Object?> notification)? onNotification,
}) async {
  final response = request.response;
  if (request.method != 'POST') {
    response
      ..statusCode = HttpStatus.methodNotAllowed
      ..headers.set(HttpHeaders.allowHeader, 'POST')
      ..contentLength = 0;
    await response.close();
    return;
  }

  // A body cannot be parsed before its media type is known, so this precedes
  // even the notification acknowledgement. dart:io parses the header lazily
  // and throws right here on a value it cannot parse, which is as much of a
  // mismatch as a wrong one.
  ContentType? contentType;
  try {
    contentType = request.headers.contentType;
  } on HttpException {
    contentType = null;
  }
  if (contentType?.mimeType != ContentType.json.mimeType) {
    try {
      await request.drain<void>();
    } on IOException {
      // The client disconnected before its body arrived; there is no
      // response left to write.
      return;
    }
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.headerMismatch,
        'The request body must be sent as ${ContentType.json.mimeType}',
      ),
      null,
    );
  }

  final Object? decoded;
  String? body;
  try {
    body = await utf8.decodeStream(request);
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(error_code.PARSE_ERROR, 'Invalid JSON: ${e.message}'),
      body,
    );
  } on IOException {
    // The client disconnected before its body arrived; there is no response
    // left to write.
    return;
  }

  if (decoded is List) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        error_code.INVALID_REQUEST,
        'Batch messages are not supported. Batching was removed in MCP '
        'specification version 2025-06-18.',
      ),
      decoded,
    );
  }
  if (decoded is! Map<String, Object?>) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        error_code.INVALID_REQUEST,
        'A message must be a JSON object',
      ),
      decoded,
    );
  }

  final object = JsonRpc2Object.fromMap(decoded);
  if (object.kind == JsonRpc2Kind.response) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        error_code.INVALID_REQUEST,
        'The client must not send JSON-RPC responses over this transport',
      ),
      decoded,
    );
  }

  final method = decoded[Keys.method];
  if (method is! String) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        error_code.INVALID_REQUEST,
        'A message requires a String method',
      ),
      decoded,
    );
  }

  if (object.kind == JsonRpc2Kind.notification) {
    // This protocol revision defines no client-to-server notifications over
    // HTTP, so there is no server to deliver them to; acknowledge and drop.
    // This acknowledgement deliberately precedes the header checks below:
    // per the specification, "header requirements for notification POSTs are
    // not defined by this revision".
    response
      ..statusCode = HttpStatus.accepted
      ..contentLength = 0;
    await response.close();
    return;
  }

  if (object.id == null) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        error_code.INVALID_REQUEST,
        'The request id must not be null',
      ),
      decoded,
    );
  }

  // A request may be answered with either a JSON object or an SSE stream, so
  // the client has to accept both shapes.
  if (!_accepts(request, ContentType.json.mimeType) ||
      !_accepts(request, _eventStreamMimeType)) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.headerMismatch,
        'A request must accept both ${ContentType.json.mimeType} and '
        '$_eventStreamMimeType',
      ),
      decoded,
    );
  }

  final headerVersion = _singleTokenHeader(request, _protocolVersionHeader);
  if (headerVersion == null) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.headerMismatch,
        'A single $_protocolVersionHeader header is required',
      ),
      decoded,
    );
  }
  final protocolVersion = ProtocolVersion.tryParse(headerVersion);
  if (protocolVersion == null ||
      !_supportedVersions.contains(protocolVersion)) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.unsupportedProtocolVersion,
        'Unsupported protocol version',
        data: {
          Keys.supported: [
            for (final supported in _supportedVersions) supported.versionString,
          ],
          Keys.requested: headerVersion,
        },
      ),
      decoded,
    );
  }

  final headerMethod = _singleTokenHeader(request, _mcpMethodHeader);
  if (headerMethod == null) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.headerMismatch,
        'A single $_mcpMethodHeader header is required',
      ),
      decoded,
    );
  }

  final params = decoded[Keys.params];
  final meta = params is Map<String, Object?> ? params[Keys.meta] : null;
  if (params is! Map<String, Object?> || meta is! Map<String, Object?>) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException.invalidParams(
        'The request requires a params.${Keys.meta} envelope object',
      ),
      decoded,
    );
  }
  final bodyVersion = meta[Keys.protocolVersionMeta];
  if (bodyVersion is! String) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException.invalidParams(
        'The envelope requires a ${Keys.protocolVersionMeta} String',
      ),
      decoded,
    );
  }
  final capabilities = meta[Keys.clientCapabilitiesMeta];
  if (capabilities is! Map<String, Object?>) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException.invalidParams(
        'The envelope requires a ${Keys.clientCapabilitiesMeta} object',
      ),
      decoded,
    );
  }
  final clientInfo = meta[Keys.clientInfoMeta];
  if (clientInfo is! Map<String, Object?>?) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException.invalidParams(
        'The envelope ${Keys.clientInfoMeta} must be an object',
      ),
      decoded,
    );
  }
  final rawLogLevel = meta[Keys.logLevelMeta];
  LoggingLevel? logLevel;
  if (rawLogLevel != null) {
    logLevel = LoggingLevel.values.firstWhereOrNull(
      (level) => level.name == rawLogLevel,
    );
    if (logLevel == null) {
      return _reject(
        response,
        HttpStatus.badRequest,
        RpcException.invalidParams(
          'The envelope ${Keys.logLevelMeta} was "$rawLogLevel", which is not '
          'one of the logging levels: '
          '${LoggingLevel.values.map((level) => level.name).join(', ')}',
        ),
        decoded,
      );
    }
  }

  if (headerVersion != bodyVersion) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.headerMismatch,
        'The $_protocolVersionHeader header does not match the '
        '${Keys.protocolVersionMeta} envelope value',
      ),
      decoded,
    );
  }
  if (headerMethod != method) {
    return _reject(
      response,
      HttpStatus.badRequest,
      RpcException(
        McpErrorCodes.headerMismatch,
        'The $_mcpMethodHeader header does not match the request method',
      ),
      decoded,
    );
  }

  final nameParam = _mcpNameParams[method];
  if (nameParam != null) {
    final headerName = _singleHeader(request, _mcpNameHeader);
    if (headerName == null) {
      return _reject(
        response,
        HttpStatus.badRequest,
        RpcException(
          McpErrorCodes.headerMismatch,
          'A single $_mcpNameHeader header is required for $method',
        ),
        decoded,
      );
    }
    final String decodedName;
    try {
      decodedName = _decodeSentinel(headerName);
    } on FormatException {
      return _reject(
        response,
        HttpStatus.badRequest,
        RpcException(
          McpErrorCodes.headerMismatch,
          'The $_mcpNameHeader header is not valid base64',
        ),
        decoded,
      );
    }
    if (decodedName != params[nameParam]) {
      return _reject(
        response,
        HttpStatus.badRequest,
        RpcException(
          McpErrorCodes.headerMismatch,
          'The $_mcpNameHeader header does not match params.$nameParam',
        ),
        decoded,
      );
    }
  }

  if (!protocolVersion.methodIsValid(method) && _someRevisionDefines(method)) {
    // A method an earlier revision defined and this one took out is unknown
    // here, not a dispatcher error. A mixin or a capability registers handlers
    // for several of them, so a request would reach one without this check. A
    // method no revision defines goes to the dispatcher, which is what lets a
    // server answer its own.
    // A legacy client never gets here: it fails the version or header checks
    // above, which is the `400 Bad Request` the compatibility matrix
    // prescribes for a legacy client talking to a modern HTTP server.
    return _reject(
      response,
      HttpStatus.notFound,
      RpcException.methodNotFound(method),
      decoded,
    );
  }

  final answer = _Answer(response);
  final Map<String, Object?>? result;
  try {
    result = await handleRequestScopedMessage(
      decoded,
      MCPServerInitialization(
        protocolVersion: protocolVersion,
        clientCapabilities: ClientCapabilities.fromMap(capabilities),
        clientInfo:
            clientInfo == null ? null : Implementation.fromMap(clientInfo),
        logLevel: logLevel,
      ),
      serverFactory,
      onNotification: (notification) {
        if (!_listenStreamNotifications.contains(notification[Keys.method])) {
          answer.notify(notification);
        }
        onNotification?.call(notification);
      },
    );
  } catch (_) {
    // The server could not be built for this request. Answer before the error
    // leaves this function, so an embedder which discards the returned future
    // does not leave the connection open. A server that emitted a notification
    // while initializing has already committed the stream, and headers cannot
    // be set on it a second time. The answer goes out on the stream instead of
    // starting a fresh response.
    await answer.finish(
      RpcException(
        error_code.INTERNAL_ERROR,
        'The server failed to initialize',
      ).serialize(decoded),
    );
    rethrow;
  }

  // Notifications returned above, so a dispatched request always has a
  // response.
  await answer.finish(result!);
}

/// The HTTP status for a dispatched JSON-RPC [response] map.
///
/// Unmapped codes keep 200 rather than falling back to an error status: the
/// specification reserves `-32020` to `-32099` for itself, and a revision
/// which allocates a code from there names the status it wants with it.
int _statusFor(Map<String, Object?> response) {
  final error = response[Keys.error];
  if (error is! Map<String, Object?>) return HttpStatus.ok;
  return switch (error[Keys.code]) {
    error_code.PARSE_ERROR ||
    error_code.INVALID_REQUEST ||
    error_code.INVALID_PARAMS ||
    McpErrorCodes.headerMismatch ||
    McpErrorCodes.missingRequiredClientCapability ||
    McpErrorCodes.unsupportedProtocolVersion => HttpStatus.badRequest,
    error_code.METHOD_NOT_FOUND => HttpStatus.notFound,
    error_code.INTERNAL_ERROR ||
    error_code.SERVER_ERROR => HttpStatus.internalServerError,
    _ => HttpStatus.ok,
  };
}

/// The notifications this revision delivers on the stream of a
/// `subscriptions/listen` request, so a response stream never carries them.
///
/// The four are the notifications `SubscriptionFilter` names.
///
/// [handleStreamableHttpRequest] passes them to its `onNotification` instead,
/// where an embedder serving a listen stream picks them up. See
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http.
const _listenStreamNotifications = {
  ToolListChangedNotification.methodName,
  PromptListChangedNotification.methodName,
  ResourceListChangedNotification.methodName,
  ResourceUpdatedNotification.methodName,
};

/// Frames [message] as one SSE `event: message` block.
String _sseEvent(Map<String, Object?> message) =>
    'event: message\ndata: ${jsonEncode(message)}\n\n';

/// The joined `data` of each `message` event in an SSE response [bytes].
///
/// An event with no data has nothing to decode, so it never reaches the
/// stream.
Stream<String> _sseMessageData(Stream<List<int>> bytes) async* {
  var event = '';
  final data = <String>[];
  await for (final line in const LineSplitter().bind(
    utf8.decoder.bind(bytes),
  )) {
    if (line.isEmpty) {
      final source = data.join('\n');
      if (source.isNotEmpty && (event.isEmpty || event == Keys.message)) {
        yield source;
      }
      event = '';
      data.clear();
      continue;
    }

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      event = value;
    } else if (field == Keys.data) {
      data.add(value);
    }
  }
}

/// Answers one request, choosing between a JSON body and an SSE stream.
///
/// The choice is deferred. As long as nothing has been written the answer is a
/// JSON body with the status [_statusFor] maps, keeping the `400` and `404`
/// answers this revision defines available. The first notification
/// commits `text/event-stream`, since a JSON body has nowhere to put one.
/// Committing settles the status at `200`. An error raised after that goes out
/// as the stream's last event, and the mapped status
/// no longer applies to it, including the `400` this revision requires of a
/// missing client capability.
class _Answer {
  _Answer(this._response);

  final HttpResponse _response;
  bool _committed = false;

  /// Sends [notification] on the stream, committing to it if this is the first.
  void notify(Map<String, Object?> notification) {
    if (!_committed) _commit();
    _response.write(_sseEvent(notification));
  }

  void _commit() {
    _committed = true;
    _response
      ..statusCode = HttpStatus.ok
      ..bufferOutput = false
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform')
      ..headers.set('x-accel-buffering', 'no');
  }

  /// Sends [result] and closes.
  Future<void> finish(Map<String, Object?> result) async {
    if (_committed) {
      _response.write(_sseEvent(result));
    } else {
      _response
        ..statusCode = _statusFor(result)
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(result));
    }
    await _response.close();
  }
}

/// Writes [exception] serialized against [origin] as a JSON body with
/// [status] and closes the response.
Future<void> _reject(
  HttpResponse response,
  int status,
  RpcException exception,
  Object? origin,
) async {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(exception.serialize(origin)));
  await response.close();
}

/// Returns the single value of [name], or `null` if it is missing or was sent
/// more than once as separate values.
String? _singleHeader(HttpRequest request, String name) {
  final values = request.headers[name];
  return values == null || values.length != 1 ? null : values.single;
}

/// Returns the single value of [name] when it is a token which cannot contain
/// a comma, and `null` if it is missing or was sent more than once.
///
/// A sender may combine repeated field lines into one comma separated value
/// (RFC 9110 section 5.3), which `dart:io`'s own client does, so for these
/// headers a comma is one way a repeat arrives. Separate field lines are the
/// other, which `dart:io`'s server keeps separate and [_singleHeader] counts.
String? _singleTokenHeader(HttpRequest request, String name) {
  final value = _singleHeader(request, name);
  return value == null || value.contains(',') ? null : value;
}

/// Whether the `Accept` header of [request] covers [mimeType], either by
/// listing it or through the `type/*` or `*/*` wildcards.
///
/// Quality values are not weighed; a media range which appears at all counts
/// as accepted. A request without an `Accept` header accepts nothing here,
/// because the spec requires clients to send one.
bool _accepts(HttpRequest request, String mimeType) {
  final values = request.headers[HttpHeaders.acceptHeader];
  if (values == null) return false;
  final wildcard = '${mimeType.split('/').first}/*';
  return values.any(
    (value) => value
        .split(',')
        .map((range) => range.split(';').first.trim().toLowerCase())
        .any(
          (range) => range == mimeType || range == wildcard || range == '*/*',
        ),
  );
}

/// Decodes the `=?base64?...?=` sentinel encoding, passing other values
/// through unchanged.
///
/// Throws a [FormatException] if the sentinel payload is not valid base64.
String _decodeSentinel(String value) =>
    // The `=?base64?` prefix is 9 characters and the `?=` suffix is 2; under
    // 11 characters they overlap, so guard the length before slicing.
    value.length >= 11 && value.startsWith('=?base64?') && value.endsWith('?=')
        ? utf8.decode(base64.decode(value.substring(9, value.length - 2)))
        : value;

// Header field names are case insensitive, so these are used both to look
// headers up and to name them in error messages, in the casing the
// specification writes them in.
const _protocolVersionHeader = 'MCP-Protocol-Version';
const _mcpMethodHeader = 'Mcp-Method';
const _mcpNameHeader = 'Mcp-Name';

/// The media type of the SSE response streams this protocol revision allows a
/// server to answer with.
const _eventStreamMimeType = 'text/event-stream';

/// The protocol versions this handler implements.
///
/// The legacy handshake negotiates [ProtocolVersion.latestSupported] instead;
/// the request-scoped protocol this transport speaks was introduced later, so
/// the two sets are deliberately separate.
const _supportedVersions = {ProtocolVersion.v2026_07_28};

/// Whether any revision of the protocol defines [method].
///
/// A method none of them define belongs to the server, not to the protocol,
/// so the transport leaves it to the dispatcher.
bool _someRevisionDefines(String method) =>
    ProtocolVersion.values.any((v) => v.addedMethods.contains(method));

/// The methods whose `name` or `uri` parameter is mirrored in the `Mcp-Name`
/// header, mapping each method to the parameter that carries it.
const _mcpNameParams = {
  CallToolRequest.methodName: Keys.name,
  GetPromptRequest.methodName: Keys.name,
  ReadResourceRequest.methodName: Keys.uri,
};
