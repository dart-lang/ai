// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../utils/analytics.dart';
import '../utils/names.dart';

/// A mixin which intercepts various MCP calls to track analytics.
base mixin AnalyticsEvents
    on ToolsSupport, PromptsSupport, ResourcesSupport, LoggingSupport
    implements AnalyticsSupport {
  @override
  /// Tracks [initialize] calls, so we can detect clients that connect but
  /// never interact with the server directly.
  Future<InitializeResult> initialize(InitializeRequest request) async {
    final result = await super.initialize(request);
    analytics?.send(
      _createDartMCPEvent(
        type: AnalyticsEvent.initialize.name,
        additionalData: InitializeMetrics(
          supportsElicitation: request.capabilities.elicitation != null,
          supportsRoots: request.capabilities.roots != null,
          supportsSampling: request.capabilities.sampling != null,
        ),
      ),
    );
    return result;
  }

  @override
  FutureOr<ListPromptsResult> listPrompts([ListPromptsRequest? request]) {
    trySendAnalyticsEvent(
      _createDartMCPEvent(type: AnalyticsEvent.listPrompts.name),
    );
    return super.listPrompts(request);
  }

  /// The names of the prompts that are set up by this server.
  ///
  /// Prompt names in requests come directly from the client, so these are the
  /// only ones that we log.
  static final _knownPromptNames = {
    for (final prompt in PromptNames.values) prompt.name,
  };

  @override
  Future<GetPromptResult> getPrompt(GetPromptRequest request) async {
    final watch = Stopwatch()..start();
    final isKnownPrompt = _knownPromptNames.contains(request.name);
    GetPromptResult? result;
    try {
      return result = await super.getPrompt(request);
    } finally {
      watch.stop();
      trySendAnalyticsEvent(
        _createDartMCPEvent(
          type: AnalyticsEvent.getPrompt.name,
          additionalData: GetPromptMetrics(
            name: isKnownPrompt ? request.name : null,
            success: result != null && result.messages.isNotEmpty,
            elapsedMilliseconds: watch.elapsedMilliseconds,
            withArguments: request.arguments?.isNotEmpty == true,
            failureReason: isKnownPrompt
                ? null
                : GetPromptFailureReason.noSuchPrompt,
          ),
        ),
      );
    }
  }

  @override
  FutureOr<ListResourcesResult> listResources([ListResourcesRequest? request]) {
    trySendAnalyticsEvent(
      _createDartMCPEvent(type: AnalyticsEvent.listResources.name),
    );
    return super.listResources(request);
  }

  @override
  FutureOr<ListResourceTemplatesResult> listResourceTemplates([
    ListResourceTemplatesRequest? request,
  ]) {
    trySendAnalyticsEvent(
      _createDartMCPEvent(type: AnalyticsEvent.listResourceTemplates.name),
    );
    return super.listResourceTemplates(request);
  }

  @override
  Future<ListToolsResult> listTools([ListToolsRequest? request]) async {
    trySendAnalyticsEvent(
      _createDartMCPEvent(type: AnalyticsEvent.listTools.name),
    );
    return super.listTools(request);
  }

  @override
  /// We override this with our own validation and error handling for analytics
  /// purposes.
  void registerTool(
    Tool tool,
    FutureOr<CallToolResult> Function(CallToolRequest) impl, {
    bool validateArguments = true,
  }) {
    final knownCommands = _knownCommands(tool);
    super.registerTool(tool, (request) async {
      final watch = Stopwatch()..start();
      // The command comes directly from the client, so we only log it if it is
      // one of the known commands for this tool.
      final command = request.arguments?[ParameterNames.command];
      final isKnownCommand = knownCommands.contains(command);
      final isUnknownCommand =
          command != null && knownCommands.isNotEmpty && !isKnownCommand;
      CallToolResult? result;
      if (validateArguments) {
        final errors = tool.inputSchema.validate(
          request.arguments ?? const <String, Object?>{},
        );
        if (errors.isNotEmpty) {
          final failureReason = isUnknownCommand
              ? CallToolFailureReason.noSuchCommand
              : CallToolFailureReason.argumentError;
          result = CallToolResult(
            content: [
              Content.text(
                text:
                    'Invalid tool arguments, make sure to read the schema '
                    'and try again:',
              ),
              for (final error in errors)
                Content.text(text: error.toErrorString()),
            ],
            isError: true,
          )..failureReason = failureReason;
        }
      }
      String? errorType;
      try {
        // Only call the tool if we don't already have an error result.
        return result ??= await impl(request);
      } catch (e) {
        errorType = e.runtimeType.toString();
        rethrow;
      } finally {
        watch.stop();
        trySendAnalyticsEvent(
          _createDartMCPEvent(
            type: AnalyticsEvent.callTool.name,
            additionalData: CallToolMetrics(
              tool: isKnownCommand ? '${tool.name}.$command' : tool.name,
              success: result != null && result.isError != true,
              elapsedMilliseconds: watch.elapsedMilliseconds,
              failureReason:
                  result?.failureReason ??
                  (errorType != null
                      ? CallToolFailureReason.unhandledError
                      : null),
              extraToolMetrics: result?.customMetrics,
              errorType: errorType,
            ),
          ),
        );
      }
    }, validateArguments: false);
  }

  Event _createDartMCPEvent({
    required String type,
    CustomMetrics? additionalData,
  }) => createDartMCPEvent(
    clientInfo: clientInfo,
    serverInfo: implementation,
    type: type,
    additionalData: additionalData,
  );

  void trySendAnalyticsEvent(Event event) {
    try {
      analytics?.send(event);
    } catch (e) {
      log(LoggingLevel.warning, 'Error sending analytics event: $e');
    }
  }
}

/// The values allowed for the `command` parameter of [tool], according to the
/// `enum` in its input schema.
///
/// Returns an empty set if [tool] has no `command` parameter, or if that
/// parameter doesn't declare an `enum`.
Set<String> _knownCommands(Tool tool) {
  final commandSchema = tool.inputSchema.properties?[ParameterNames.command];
  if (commandSchema == null) return const {};
  return {...?(commandSchema as StringSchema).enumValues};
}
