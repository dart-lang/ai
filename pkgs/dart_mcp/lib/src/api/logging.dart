// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// Extension type for the `logging` capability.
extension type Logging.fromMap(Map<String, Object?> _value) {
  factory Logging() => Logging.fromMap({});
}

/// A request from the client to the server, to enable or adjust logging.
extension type SetLevelRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'logging/setLevel';

  factory SetLevelRequest({
    required LoggingLevel level,
    MetaWithProgressToken? meta,
  }) => SetLevelRequest.fromMap({
    'level': level.name,
    if (meta != null) '_meta': meta,
  });

  /// The level of logging that the client wants to receive from the server.
  ///
  /// The server should send all logs at this level and higher (i.e., more
  /// severe) to the client as notifications/message.
  LoggingLevel get level {
    final levelName = _value['level'];
    final foundLevel = LoggingLevel.values.firstWhereOrNull(
      (level) => level.name == levelName,
    );
    if (foundLevel == null) {
      throw ArgumentError(
        "Invalid level field in $SetLevelRequest: didn't find level $levelName",
      );
    }
    return foundLevel;
  }
}

/// Notification of a log message passed from server to client.
///
/// If no logging/setLevel request has been sent from the client, the server
/// MAY decide which messages to send automatically.
extension type LoggingMessageNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/message';

  factory LoggingMessageNotification({
    required LoggingLevel level,
    String? logger,
    required Object data,
    Meta? meta,
  }) => LoggingMessageNotification.fromMap({
    'level': level.name,
    if (logger != null) 'logger': logger,
    'data': data,
    if (meta != null) '_meta': meta,
  });

  /// The severity of this log message.
  LoggingLevel get level =>
      LoggingLevel.values.firstWhere((level) => level.name == _value['level']);

  /// An optional name of the logger issuing this message.
  String? get logger => _value['logger'] as String?;

  /// The data to be logged, such as a string message or an object.
  ///
  /// Any JSON serializable type is allowed here.
  Object get data => _value['data'] as Object;
}

/// The severity of a log message.
///
/// These map to syslog message severities, as specified in RFC-5424:
/// https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.1
enum LoggingLevel {
  debug,
  info,
  notice,
  warning,
  error,
  critical,
  alert,
  emergency;

  bool operator <(LoggingLevel other) => index < other.index;
  bool operator >(LoggingLevel other) => index > other.index;
  bool operator >=(LoggingLevel other) => index >= other.index;
}
