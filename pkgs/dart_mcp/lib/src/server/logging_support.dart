// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which support the `logging` capability.
///
/// See https://spec.modelcontextprotocol.io/specification/2025-03-26/server/utilities/logging/.
base mixin LoggingSupport on MCPServer {
  /// The current logging level, defaults to [LoggingLevel.warning].
  LoggingLevel loggingLevel = LoggingLevel.warning;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    registerRequestHandler(SetLevelRequest.methodName, handleSetLevel);

    return (await super.initialize(request))
      ..capabilities.logging ??= Logging();
  }

  /// Sends a [LoggingMessageNotification] to the client, if the [loggingLevel]
  /// is <= [level].
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
    if (loggingLevel > level) return;

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
  FutureOr<EmptyResult> handleSetLevel(SetLevelRequest request) {
    loggingLevel = request.level;
    return EmptyResult();
  }
}
