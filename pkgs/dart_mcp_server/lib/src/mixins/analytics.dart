// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../utils/analytics.dart';

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
      Event.dartMCPEvent(
        client: clientInfo.name,
        clientVersion: clientInfo.version,
        serverVersion: implementation.version,
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
      Event.dartMCPEvent(
        client: clientInfo.name,
        clientVersion: clientInfo.version,
        serverVersion: implementation.version,
        type: AnalyticsEvent.listPrompts.name,
      ),
    );
    return super.listPrompts(request);
  }

  @override
  Future<GetPromptResult> getPrompt(GetPromptRequest request) async {
    final watch = Stopwatch()..start();
    GetPromptResult? result;
    try {
      return result = await super.getPrompt(request);
    } finally {
      watch.stop();
      trySendAnalyticsEvent(
        Event.dartMCPEvent(
          client: clientInfo.name,
          clientVersion: clientInfo.version,
          serverVersion: implementation.version,
          type: AnalyticsEvent.getPrompt.name,
          additionalData: GetPromptMetrics(
            name: request.name,
            success: result != null && result.messages.isNotEmpty,
            elapsedMilliseconds: watch.elapsedMilliseconds,
            withArguments: request.arguments?.isNotEmpty == true,
          ),
        ),
      );
    }
  }

  @override
  FutureOr<ListResourcesResult> listResources([ListResourcesRequest? request]) {
    trySendAnalyticsEvent(
      Event.dartMCPEvent(
        client: clientInfo.name,
        clientVersion: clientInfo.version,
        serverVersion: implementation.version,
        type: AnalyticsEvent.listResources.name,
      ),
    );
    return super.listResources(request);
  }

  @override
  FutureOr<ListResourceTemplatesResult> listResourceTemplates([
    ListResourceTemplatesRequest? request,
  ]) {
    trySendAnalyticsEvent(
      Event.dartMCPEvent(
        client: clientInfo.name,
        clientVersion: clientInfo.version,
        serverVersion: implementation.version,
        type: AnalyticsEvent.listResourceTemplates.name,
      ),
    );
    return super.listResourceTemplates(request);
  }

  @override
  Future<ListToolsResult> listTools([ListToolsRequest? request]) async {
    trySendAnalyticsEvent(
      Event.dartMCPEvent(
        client: clientInfo.name,
        clientVersion: clientInfo.version,
        serverVersion: implementation.version,
        type: AnalyticsEvent.listTools.name,
      ),
    );
    return super.listTools(request);
  }

  @override
  /// We override this to do our own validation - this is mostly a copy of the
  /// normal implementation except we also attach a failure reason for
  /// analytics purposes.
  void registerTool(
    Tool tool,
    FutureOr<CallToolResult> Function(CallToolRequest) impl, {
    bool validateArguments = true,
  }) {
    super.registerTool(
      tool,
      validateArguments
          ? (request) {
              final errors = tool.inputSchema.validate(
                request.arguments ?? const <String, Object?>{},
              );
              if (errors.isNotEmpty) {
                return CallToolResult(
                  content: [
                    for (final error in errors)
                      Content.text(text: error.toErrorString()),
                  ],
                  isError: true,
                )..failureReason = CallToolFailureReason.argumentError;
              }
              return impl(request);
            }
          : impl,
      validateArguments: false,
    );
  }

  @override
  Future<CallToolResult> callTool(CallToolRequest request) async {
    final watch = Stopwatch()..start();
    CallToolResult? result;
    try {
      return result = await super.callTool(request);
    } finally {
      watch.stop();
      trySendAnalyticsEvent(
        Event.dartMCPEvent(
          client: clientInfo.name,
          clientVersion: clientInfo.version,
          serverVersion: implementation.version,
          type: AnalyticsEvent.callTool.name,
          additionalData: CallToolMetrics(
            tool: request.name,
            success: result != null && result.isError != true,
            elapsedMilliseconds: watch.elapsedMilliseconds,
            failureReason: result?.failureReason,
          ),
        ),
      );
    }
  }

  void trySendAnalyticsEvent(Event event) {
    try {
      analytics?.send(event);
    } catch (e) {
      log(LoggingLevel.warning, 'Error sending analytics event: $e');
    }
  }
}
