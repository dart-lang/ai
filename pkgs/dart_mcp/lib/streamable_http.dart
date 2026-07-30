// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The server side of the Streamable HTTP transport described by the
/// 2026-07-28 revision of the Model Context Protocol specification,
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http.
///
/// Every POST carries a single JSON-RPC request or notification along with
/// its own client context; there is no session state between requests. This
/// library only answers with JSON bodies; SSE response streams are not
/// implemented yet.
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';

import 'server.dart';
import 'src/utils/constants.dart';
import 'src/utils/json_rpc_2_object.dart';

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

/// The methods whose `name` or `uri` parameter is mirrored in the `Mcp-Name`
/// header, mapping each method to the parameter that carries it.
const _mcpNameParams = {
  CallToolRequest.methodName: Keys.name,
  GetPromptRequest.methodName: Keys.name,
  ReadResourceRequest.methodName: Keys.uri,
};

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
/// those bodies also echoes the message which produced it under
/// `error.data.request`, as the rest of this package does. A non-POST request
/// is answered with 405 and an `Allow` header but no body, which is all this
/// revision defines for `GET` and `DELETE`.
///
/// The `MCP-Protocol-Version` header is checked against the versions this
/// handler implements before the body is inspected. A client speaking another
/// revision cannot produce this revision's `_meta` envelope, so answering on
/// the header alone is what lets it receive the `supported` list it needs to
/// renegotiate with.
///
/// Notifications are acknowledged with `202 Accepted` and not dispatched,
/// since this protocol revision defines no client-to-server notifications
/// over HTTP. This handler reads the whole request body into memory, so
/// origin validation, authentication, and request size limits are the
/// embedding HTTP server's responsibility.
///
/// Responses produced by the dispatched server are written unchanged, so an
/// error a request handler throws reaches the client with whatever payload
/// `package:json_rpc_2` attached to it, including a Dart stack trace for
/// errors which are not an [RpcException]. Handlers which must not disclose
/// server internals to a remote client throw [RpcException]s instead.
///
/// If [serverFactory] or [MCPServer.initialize] throws, the request is
/// answered with 500 and an internal-error body, and the returned future then
/// completes with that error so an embedder which awaits it can log or rethrow
/// it.
///
/// `Mcp-Session-Id` and `Last-Event-ID` headers are ignored, and no session
/// id is ever minted: sessions and resumable streams were removed in this
/// revision. Headers this revision does not define, including the
/// `Mcp-Param-{Name}` headers a server opts into with `x-mcp-header`, are
/// ignored as RFC 9110 requires.
///
/// Notifications the server produces while handling the request are passed
/// to [onNotification]; a JSON response body cannot carry them, so without a
/// handler they are dropped.
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
  // even the notification acknowledgement.
  if (request.headers.contentType?.mimeType != ContentType.json.mimeType) {
    await request.drain<void>();
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
  // the client has to accept both shapes even though this handler only sends
  // the first.
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

  if (method == InitializeRequest.methodName ||
      method == InitializedNotification.methodName) {
    // The legacy lifecycle is not part of the request-scoped protocol, so its
    // methods are unknown here rather than dispatcher errors, which is also
    // what `handleRequestScopedMessage` requires of its callers. A legacy
    // client never reaches this point: it fails the version or header checks
    // above, which is the `400 Bad Request` the compatibility matrix
    // prescribes for a legacy client talking to a modern HTTP server.
    return _reject(
      response,
      HttpStatus.notFound,
      RpcException.methodNotFound(method),
      decoded,
    );
  }

  final Map<String, Object?>? result;
  try {
    result = await handleRequestScopedMessage(
      decoded,
      MCPServerInitialization(
        protocolVersion: protocolVersion,
        clientCapabilities: ClientCapabilities.fromMap(capabilities),
        clientInfo:
            clientInfo == null ? null : Implementation.fromMap(clientInfo),
      ),
      serverFactory,
      onNotification: onNotification,
    );
  } catch (_) {
    // The server could not be built for this request. Answer before the error
    // leaves this function, so an embedder which discards the returned future
    // does not leave the connection open.
    await _reject(
      response,
      HttpStatus.internalServerError,
      RpcException(
        error_code.INTERNAL_ERROR,
        'The server failed to initialize',
      ),
      decoded,
    );
    rethrow;
  }

  // Notifications returned above, so a dispatched request always has a
  // response.
  response.statusCode = _statusFor(result!);
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(result));
  await response.close();
}

/// The HTTP status for a dispatched JSON-RPC [response] map.
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
    _ => HttpStatus.ok,
  };
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
/// A recipient may combine repeated field lines into one comma separated
/// value (RFC 9110 section 5.3), which `dart:io` does, so for these headers a
/// comma is how a repeat arrives.
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
