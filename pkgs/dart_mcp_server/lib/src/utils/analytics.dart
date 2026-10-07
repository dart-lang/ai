// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';
import 'package:unified_analytics/unified_analytics.dart';

/// An interface class that provides a access to an [Analytics] instance, if
/// enabled.
///
/// The `DartMCPServer` class implements this class so that [Analytics]
/// methods can be easily mocked during testing.
abstract interface class AnalyticsSupport {
  Analytics? get analytics;
}

/// The environment variable name used to specify the agent plugin.
const agentPluginEnvVar = 'AGENT_PLUGIN';

/// Key used to store the agent plugin override in a [Zone].
const _agentPluginOverrideKey = #_agentPluginOverrideKey;

/// Runs [callback] in a zone where the agent plugin is overridden with
/// [agentPlugin].
@visibleForTesting
R withAgentPluginOverride<R>(String agentPlugin, R Function() callback) =>
    runZoned(callback, zoneValues: {_agentPluginOverrideKey: agentPlugin});

/// Returns the agent plugin name from the current [Zone] (if overridden) or
/// the environment.
String? get agentPlugin =>
    Zone.current[_agentPluginOverrideKey] as String? ??
    Platform.environment[agentPluginEnvVar];

/// Creates an [Event.dartMCPEvent] of the given [type].
///
/// All analytics events sent by this server should be created through this
/// function, so that the values which come from outside of the server (the
/// [clientInfo] and the [agentPlugin]) are always sanitized with
/// [sanitizeForAnalytics].
Event createDartMCPEvent({
  required Implementation clientInfo,
  required Implementation serverInfo,
  required String type,
  CustomMetrics? additionalData,
}) {
  final plugin = agentPlugin;
  return Event.dartMCPEvent(
    client: sanitizeForAnalytics(clientInfo.name),
    clientVersion: sanitizeForAnalytics(clientInfo.version),
    serverVersion: serverInfo.version,
    type: type,
    agentPlugin: plugin == null ? null : sanitizeForAnalytics(plugin),
    additionalData: additionalData,
  );
}

/// The maximum length of a value returned by [sanitizeForAnalytics].
///
/// Matches the maximum length of a GA4 event parameter value.
const maxSanitizedAnalyticsValueLength = 100;

/// Matches `${...}` interpolations, including unterminated ones.
final _interpolationPattern = RegExp(r'\$\{[^}]*\}?');

/// Matches runs of control characters and line terminators.
final _controlCharactersPattern = RegExp(r'[\x00-\x1F\x7F-\x9F\u2028\u2029]+');

/// Sanitizes a free-form [value] which comes from outside of this server, such
/// as the client name and version, so that it is safe to send in analytics.
///
/// - Removes all `${...}` interpolations and then any remaining `$`
///   characters, so that analytics dashboards (such as PLX) never treat any
///   part of the value as a variable substitution.
/// - Replaces each run of control characters (including newlines) with a
///   single space, and trims any leading and trailing whitespace.
/// - Truncates the result to [maxSanitizedAnalyticsValueLength] characters.
String sanitizeForAnalytics(String value) {
  final sanitized = value
      .replaceAll(_interpolationPattern, '')
      .replaceAll(r'$', '')
      .replaceAll(_controlCharactersPattern, ' ')
      .trim();
  final runes = sanitized.runes;
  if (runes.length <= maxSanitizedAnalyticsValueLength) return sanitized;
  return String.fromCharCodes(
    runes.take(maxSanitizedAnalyticsValueLength),
  ).trimRight();
}

enum AnalyticsEvent {
  callTool,
  initialize,
  listPrompts,
  listResources,
  listResourceTemplates,
  listTools,
  readResource,
  getPrompt,
}

/// The metrics for an initialize MCP handler.
final class InitializeMetrics extends CustomMetrics {
  final bool supportsElicitation;
  final bool supportsRoots;
  final bool supportsSampling;

  InitializeMetrics({
    required this.supportsElicitation,
    required this.supportsRoots,
    required this.supportsSampling,
  });

  @override
  Map<String, Object> toMap() => {
    _supportsElicitation: supportsElicitation,
    _supportsRoots: supportsRoots,
    _supportsSampling: supportsSampling,
  };
}

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

/// The metrics for a prompts/get MCP handler.
final class GetPromptMetrics extends CustomMetrics {
  /// The name of the prompt that was retrieved.
  ///
  /// This is `null` if the client asked for a prompt that isn't one of the
  /// prompts set up by this server, because we never log other prompt names.
  final String? name;

  /// Whether or not the prompt was given with arguments.
  final bool withArguments;

  /// The time it took to generate the prompt.
  final int elapsedMilliseconds;

  /// Whether or not the prompt call succeeded.
  final bool success;

  /// The reason for the failure, if [success] is `false` and it is known.
  final GetPromptFailureReason? failureReason;

  GetPromptMetrics({
    required this.name,
    required this.withArguments,
    required this.elapsedMilliseconds,
    required this.success,
    this.failureReason,
  });

  @override
  Map<String, Object> toMap() => {
    _name: ?name,
    _withArguments: withArguments,
    _elapsedMilliseconds: elapsedMilliseconds,
    _success: success,
    _failureReason: ?failureReason?.name,
  };
}

/// Known reasons for failed prompts/get calls.
enum GetPromptFailureReason {
  /// The client asked for a prompt that isn't one of the prompts set up by
  /// this server.
  noSuchPrompt,
}

/// The metrics for a tools/call MCP handler.
final class CallToolMetrics extends CustomMetrics {
  /// The name of the tool that was invoked.
  ///
  /// If the tool was invoked with one of the known values of its `command`
  /// parameter, then that command is appended to the name, separated by a `.`.
  ///
  /// This is always the name of a registered tool, because we never log tool
  /// names or commands that we don't recognize.
  final String tool;

  /// Whether or not the tool call succeeded.
  final bool success;

  /// The time it took to invoke the tool.
  final int elapsedMilliseconds;

  /// The reason for the failure, if [success] is `false`.
  final CallToolFailureReason? failureReason;

  /// Extra metrics reported by the given tool that was called.
  final CustomMetrics? extraToolMetrics;

  /// The runtime type of an exception if thrown.
  final String? errorType;

  CallToolMetrics({
    required this.tool,
    required this.success,
    required this.elapsedMilliseconds,
    required this.failureReason,
    required this.extraToolMetrics,
    required this.errorType,
  });

  @override
  Map<String, Object> toMap() => {
    _tool: tool,
    _success: success,
    _elapsedMilliseconds: elapsedMilliseconds,
    _failureReason: ?failureReason?.name,
    _errorType: ?errorType,
    ...?extraToolMetrics?.toMap(),
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
  alreadyDisconnected,
  ambiguousServiceMethod,
  applicationNotFound,
  argumentError,
  connectedAppServiceNotSupported,
  dtdAlreadyConnected,
  dtdNotConnected,
  flutterDriverNotEnabled,
  givenVmServiceUri,
  httpClientException,
  invalidPath,
  invalidRootPath,
  invalidRootScheme,
  lspStartupFailed,
  noActiveDebugSession,
  noPackageConfigFound,
  noRootGiven,
  noRootsSet,
  noSuchCommand,
  nonZeroExitCode,
  mustSpecifyDtdUri,
  processException,
  rpcError,
  timeout,
  unhandledError,
  webSocketException,
  wrappedServiceIssue,
}

extension WithCustomMetrics on CallToolResult {
  static final _expando = Expando<CustomMetrics>();

  CustomMetrics? get customMetrics => _expando[this as Object];

  set customMetrics(CustomMetrics? value) => _expando[this as Object] = value;
}

const _elapsedMilliseconds = 'elapsedMilliseconds';
const _errorType = 'errorType';
const _failureReason = 'failureReason';
const _kind = 'kind';
const _length = 'length';
const _name = 'name';
const _success = 'success';
const _tool = 'tool';
const _withArguments = 'withArguments';
const _supportsElicitation = 'supportsElicitation';
const _supportsRoots = 'supportsRoots';
const _supportsSampling = 'supportsSampling';
