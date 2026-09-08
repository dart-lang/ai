// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// How many rounds a handler may answer `input_required` before the shim gives
/// up. This guards against a handler that never settles, so it is not a knob.
const _legacyInputRequiredMaxRounds = 8;

/// Replays an input-required handler through the request style of older
/// protocol revisions.
final class _LegacyInputRequiredShim {
  _LegacyInputRequiredShim(this._server);

  final MCPServer _server;

  /// Counts the URL elicitations this server has named. The revision that takes
  /// them asks for an `elicitationId` unique to the server and opaque to the
  /// client, and a count is both.
  var _elicitations = 0;

  Future<T> fulfill<T extends Result>(
    String methodName,
    WithInputResponses request,
    FutureOr<T> Function(WithInputResponses) handler,
  ) async {
    var result = await handler(request) as Result;
    if (_server.protocolVersion >= ProtocolVersion.v2026_07_28) {
      return result as T;
    }

    for (var round = 0; result.isInputRequired; round++) {
      if (round >= _legacyInputRequiredMaxRounds) {
        throw RpcException(
          error_code.INTERNAL_ERROR,
          'The server returned input_required after '
          '$round retries for $methodName.',
        );
      }

      final inputRequired = result as InputRequiredResult;
      final inputRequests = inputRequired.inputRequests;
      final requestState = inputRequired.requestState;
      if ((inputRequests == null || inputRequests.isEmpty) &&
          requestState == null) {
        throw ArgumentError(
          'The server returned input_required without '
          'inputRequests or requestState.',
        );
      }

      final responses = <String, Result>{};
      if (inputRequests != null && inputRequests.isNotEmpty) {
        for (final inputRequest in inputRequests.values) {
          _validateInputRequest(inputRequest);
        }
        final fulfilled = await Future.wait<MapEntry<String, Result>>(
          inputRequests.entries.map(
            (entry) async => MapEntry<String, Result>(
              entry.key,
              await _sendInputRequest(entry.value),
            ),
          ),
        );
        responses.addEntries(fulfilled);
      }

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
      result = await handler(retryRequest) as Result;
    }
    return result as T;
  }

  void _validateInputRequest(InputRequest inputRequest) {
    switch (inputRequest.method) {
      case ElicitRequest.methodName:
        final request = inputRequest.params as ElicitRequest?;
        if (request == null) {
          throw ArgumentError(
            'The elicitation/create input request requires params.',
          );
        }
        _validateElicitation(request);
      case CreateMessageRequest.methodName:
        final request = inputRequest.params as CreateMessageRequest?;
        if (request == null) {
          throw ArgumentError(
            'The sampling/createMessage input request requires params.',
          );
        }
        _rejectRemovedMethod(
          CreateMessageRequest.methodName,
          _server.protocolVersion,
        );
        if (!_server.supportsSampling) throw _missingSampling;
      case ListRootsRequest.methodName:
        _rejectRemovedMethod(
          ListRootsRequest.methodName,
          _server.protocolVersion,
        );
        if (!_server.supportsRoots) throw _missingRoots;
        inputRequest.params as ListRootsRequest?;
      default:
        throw ArgumentError(
          'The input request method was "${inputRequest.method}", which is '
          'not one of: ${InputRequest.methodNames.join(', ')}.',
        );
    }
    if (!_server._serverRequestsSupported) {
      throw RpcException(
        error_code.INTERNAL_ERROR,
        'This request-scoped transport cannot send requests from the server '
        'to the client.',
      );
    }
  }

  void _validateElicitation(ElicitRequest request) {
    _rejectRemovedMethod(ElicitRequest.methodName, _server.protocolVersion);
    final rawMode = request.rawMode;
    if (rawMode != null &&
        !ElicitationMode.values.any((mode) => mode.name == rawMode)) {
      throw RpcException.invalidParams(
        'The elicitation mode was "$rawMode", which is not one of: '
        '${ElicitationMode.values.map((mode) => mode.name).join(', ')}',
      );
    }
    switch (request.mode) {
      case ElicitationMode.url:
        if (!_server.clientCapabilities.supportsUrlElicitation) {
          throw _missingUrlElicitation;
        }
      case ElicitationMode.form:
        if (!_server.clientCapabilities.supportsFormElicitation) {
          throw _missingFormElicitation;
        }
    }
  }

  Future<Result> _sendInputRequest(InputRequest inputRequest) async {
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
