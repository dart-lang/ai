// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which support the `logging` capability.
///
/// See https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging/.
base mixin LoggingSupport on MCPServer {
  /// The level at or above which [log] sends messages, or `null` to send none.
  ///
  /// On 2026-07-28 `initialize` sets this to
  /// [MCPServerInitialization.logLevel], overwriting any default the server
  /// chose for itself. Earlier revisions keep that default, start at
  /// [LoggingLevel.warning] when there is none, and serve `logging/setLevel`
  /// to move it.
  LoggingLevel? loggingLevel;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) async {
    if (initialization.protocolVersion < ProtocolVersion.v2026_07_28) {
      loggingLevel ??= LoggingLevel.warning;
      registerRequestHandler(SetLevelRequest.methodName, handleSetLevel);
    } else {
      // Assign instead of `??=`. 2026-07-28 took `logging/setLevel` out, so a
      // default the server picked for itself would otherwise survive here and
      // log on a request that asked for no level.
      loggingLevel = initialization.logLevel;
    }

    await super.initialize(initialization);
    capabilities.logging ??= Logging();
  }

  /// Sends a [LoggingMessageNotification] to the client, if [loggingLevel] is
  /// set and is <= [level].
  ///
  /// The [data] must either be some json serializable object, or a function
  /// which takes no arguments and returns some json serializable object.
  ///
  /// if [data] is a function then it must take zero arguments and return a
  /// non-nullable result. It will only be invoked if the log message
  /// will actually be sent.
  ///
  /// If [data] is any other type of function, an [ArgumentError] will be
  /// thrown.
  void log(LoggingLevel level, Object data, {String? logger, Meta? meta}) {
    final threshold = loggingLevel;
    if (threshold == null || threshold > level) return;

    if (data is Function) {
      if (data is Object Function()) {
        data = data();
      } else {
        throw ArgumentError.value(
          data,
          'data',
          'When logging a lazily evaluated function, it must be of type '
              '`Object Function()`, but the given function type was '
              '`${data.runtimeType}`.',
        );
      }
    }

    sendNotification(
      LoggingMessageNotification.methodName,
      LoggingMessageNotification(
        level: level,
        data: data,
        logger: logger,
        meta: meta,
      ),
    );
  }

  /// Handle a client request to change the logging level.
  ///
  /// Registered for `logging/setLevel` on the revisions that still have the
  /// method, and not on 2026-07-28. `handleStreamableHttpRequest` answers it
  /// with `404` on that revision anyway, so this is what a transport calling
  /// `handleRequestScopedMessage` on its own gets instead.
  FutureOr<EmptyResult> handleSetLevel(SetLevelRequest request) {
    loggingLevel = request.level;
    return EmptyResult();
  }
}
