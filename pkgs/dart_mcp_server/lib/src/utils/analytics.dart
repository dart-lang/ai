// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:unified_analytics/unified_analytics.dart';

/// An interface class that provides a access to an [Analytics] instance, if
/// enabled.
///
/// The `DartMCPServer` class implements this class so that [Analytics]
/// methods can be easily mocked during testing.
abstract interface class AnalyticsSupport {
  Analytics? get analytics;
}

enum AnalyticsEvent { callTool, readResource }

/// The metrics for a resources/read MCP handler.
final class ReadResourceMetrics extends CustomMetrics {
  /// The kind of resource that was read.
  ///
  /// We don't want to record the full URI.
  final ResourceKind kind;

  /// The length of the resource.
  final int length;

  /// The time it took to read the resource.
  final int elapsedMilliseconds;

  ReadResourceMetrics({
    required this.kind,
    required this.length,
    required this.elapsedMilliseconds,
  });

  @override
  Map<String, Object> toMap() => {
    _kind: kind.name,
    _length: length,
    _elapsedMilliseconds: elapsedMilliseconds,
  };
}

/// The metrics for a tools/call MCP handler.
final class CallToolMetrics extends CustomMetrics {
  /// The name of the tool that was invoked.
  final String tool;

  /// Whether or not the tool call succeeded.
  final bool success;

  /// The time it took to invoke the tool.
  final int elapsedMilliseconds;

  /// The reason for the failure, if [success] is `false`.
  final CallToolFailureReason? failureReason;

  CallToolMetrics({
    required this.tool,
    required this.success,
    required this.elapsedMilliseconds,
    required this.failureReason,
  });

  @override
  Map<String, Object> toMap() => {
    _tool: tool,
    _success: success,
    _elapsedMilliseconds: elapsedMilliseconds,
    _failureReason: ?failureReason?.name,
  };
}

enum ResourceKind { runtimeErrors }

/// Extension which tracks failure reasons for [CallToolResult] objects in an
/// [Expando].
extension WithFailureReason on CallToolResult {
  static final _expando = Expando<CallToolFailureReason>();

  CallToolFailureReason? get failureReason => _expando[this as Object];

  set failureReason(CallToolFailureReason? value) =>
      _expando[this as Object] = value;
}

/// Known reasons for failed tool calls.
enum CallToolFailureReason {
  argumentError,
  connectedAppServiceNotSupported,
  dtdAlreadyConnected,
  dtdNotConnected,
  flutterDriverNotEnabled,
  invalidPath,
  invalidRootPath,
  invalidRootScheme,
  noActiveDebugSession,
  noRootGiven,
  noRootsSet,
  noSuchCommand,
  nonZeroExitCode,
  webSocketException,
}

const _elapsedMilliseconds = 'elapsedMilliseconds';
const _failureReason = 'failureReason';
const _kind = 'kind';
const _length = 'length';
const _success = 'success';
const _tool = 'tool';
