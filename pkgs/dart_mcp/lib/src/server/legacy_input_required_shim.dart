// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// Replays an `input_required` handler through the request style of older
/// protocol revisions.
///
/// Runs when [MCPServer.protocolVersion] is before 2026-07-28. Each
/// [InputRequest] is sent as that revision's own request by
/// [_sendLegacyInputRequest]. The handler is then rerun with the answers
/// under the same keys in `inputResponses` and the echoed `requestState`.
/// Reruns stop at [MCPServer.maxInputRequiredRounds] and fail as an
/// [RpcException]. On 2026-07-28 the dispatcher performs the same checks.
final class _LegacyInputRequiredShim {
  _LegacyInputRequiredShim(this._server);

  final MCPServer _server;

  /// Counts the URL elicitations this server has made. The revision that takes
  /// them asks for an `elicitationId` unique to the server and opaque to the
  /// client, and a count is both.
  var _elicitations = 0;

  /// Reruns [handler] until it answers or the round limit is exceeded.
  ///
  /// On revisions before 2026-07-28 each [InputRequest] is sent as that
  /// revision's own request. The handler is rerun with the answers under the
  /// same keys and the echoed `requestState`. On 2026-07-28 this returns the
  /// handler result unchanged. Exceeding [MCPServer.maxInputRequiredRounds]
  /// is an [RpcException].
  Future<Result> fulfill(
    String methodName,
    WithInputResponses request,
    FutureOr<Result> Function(WithInputResponses) handler,
  ) async {
    var result = await handler(request);
    if (_server.protocolVersion >= ProtocolVersion.v2026_07_28) {
      return result;
    }

    for (var round = 0; ; round++) {
      if (!result.isInputRequired) return result;
      if (round >= _server.maxInputRequiredRounds) {
        throw RpcException(
          error_code.INTERNAL_ERROR,
          'The server returned input_required after '
          '$round retries for $methodName, which has exceeded the maximum.',
        );
      }

      // (1) Read what the handler asked for.
      final inputRequired = result as InputRequiredResult;
      final inputRequests = inputRequired.inputRequests;
      final requestState = inputRequired.requestState;
      if (inputRequests != null) {
        for (final inputRequest in inputRequests.values) {
          _rejectRemovedMethod(inputRequest.method, _server.protocolVersion);
        }
      }
      final refusal = _inputRequiredResultRefusal(
        inputRequired as Map<String, Object?>,
        methodName,
        _server.clientCapabilities,
      );
      if (refusal != null) throw refusal;
      if (!_server._serverRequestsSupported) {
        throw RpcException(
          error_code.INTERNAL_ERROR,
          'This request-scoped transport cannot send requests from the server '
          'to the client.',
        );
      }

      // (2) Send each request on the legacy path.
      final responses = <String, Result>{};
      if (inputRequests != null && inputRequests.isNotEmpty) {
        final fulfilled = await Future.wait<MapEntry<String, Result>>(
          inputRequests.entries.map(
            (entry) async => MapEntry<String, Result>(
              entry.key,
              await _sendLegacyInputRequest(entry.value),
            ),
          ),
        );
        responses.addEntries(fulfilled);
      }

      // (3) Rerun with the answers and the echoed requestState.
      final retryRequest =
          <String, Object?>{
                for (final entry in (request as Map<String, Object?>).entries)
                  if (entry.key != Keys.inputResponses &&
                      entry.key != Keys.requestState)
                    entry.key: entry.value,
                if (responses.isNotEmpty) Keys.inputResponses: responses,
                if (requestState != null) Keys.requestState: requestState,
              }
              as WithInputResponses;
      result = await handler(retryRequest);
    }
  }

  /// Translates [inputRequest] into that revision's own request.
  ///
  /// Form and URL elicitation go as `elicitation/create`, sampling as
  /// `sampling/createMessage`, and roots as `roots/list`. A URL elicitation
  /// missing `elicitationId` gets one, which 2025-11-25 requires.
  Future<Result> _sendLegacyInputRequest(InputRequest inputRequest) async {
    switch (inputRequest.method) {
      case ElicitRequest.methodName:
        var request = inputRequest.params as ElicitRequest;
        if (request.mode == ElicitationMode.url &&
            request.elicitationId == null) {
          final value = Map<String, Object?>.from(
            request as Map<String, Object?>,
          )..[Keys.elicitationId] = 'elicitation-${_elicitations++}';
          request = value as ElicitRequest;
        }
        return await _server.sendRequest<ElicitResult>(
          ElicitRequest.methodName,
          request,
        );
      case CreateMessageRequest.methodName:
        return await _server.sendRequest<CreateMessageResult>(
          CreateMessageRequest.methodName,
          inputRequest.params as CreateMessageRequest,
        );
      case ListRootsRequest.methodName:
        return await _server.sendRequest<ListRootsResult>(
          ListRootsRequest.methodName,
          inputRequest.params as ListRootsRequest?,
        );
      default:
        throw ArgumentError(
          'The input request method was "${inputRequest.method}", which is '
          'not one of: ${InputRequest.methodNames.join(', ')}.',
        );
    }
  }
}
