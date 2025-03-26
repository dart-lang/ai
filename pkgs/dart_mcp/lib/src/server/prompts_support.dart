// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which support the `prompts` capability.
///
/// Supports `listChanged` notifications for the prompts list.
///
/// See https://modelcontextprotocol.io/docs/concepts/prompts.
mixin PromptsSupport on MCPServer {
  final Map<String, Prompt> _prompts = {};
  final Map<String, FutureOr<GetPromptResult> Function(GetPromptRequest)>
  _promptImpls = {};

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    _peer.registerMethod(
      ListPromptsRequest.methodName,
      convertParameters(_listPrompts),
    );

    _peer.registerMethod(
      GetPromptRequest.methodName,
      convertParameters(_getPrompt),
    );

    final result = await super.initialize(request);
    (result.capabilities.prompts ??= Prompts()).listChanged = true;
    return result;
  }

  /// Lists the available prompts.
  ListPromptsResult _listPrompts(ListPromptsRequest request) =>
      ListPromptsResult(prompts: _prompts.values.toList());

  /// Gets the response for a given prompt.
  FutureOr<GetPromptResult> _getPrompt(GetPromptRequest request) {
    final impl = _promptImpls[request.name];
    if (impl == null) {
      throw ArgumentError.value(request.name, 'name', 'Prompt not found');
    }
    return impl(request);
  }

  /// Adds a prompt and notifies clients that the list has changed.
  void addPrompt(
    Prompt prompt,
    FutureOr<GetPromptResult> Function(GetPromptRequest) impl,
  ) {
    if (_prompts.containsKey(prompt.name)) {
      throw StateError(
        'Failed to add prompt ${prompt.name}, it already exists',
      );
    }
    _prompts[prompt.name] = prompt;
    _promptImpls[prompt.name] = impl;
    if (ready) {
      _notifyPromptListChanged();
    }
  }

  /// Removes a prompt and notifies clients that the list has changed.
  void removePrompt(String name) {
    _prompts.remove(name);
    _promptImpls.remove(name);
    if (ready) {
      _notifyPromptListChanged();
    }
  }

  /// Notifies clients that the prompts list has changed.
  void _notifyPromptListChanged() {
    _peer.sendNotification(
      PromptListChangedNotification.methodName,
      PromptListChangedNotification(),
    );
  }
}
