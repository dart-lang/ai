// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// Sent from the client to request a list of prompts and prompt templates the
/// server has.
extension type ListPromptsRequest.fromMap(Map<String, Object?> _value)
    implements PaginatedRequest {
  static const methodName = 'prompts/list';

  factory ListPromptsRequest({Cursor? cursor, MetaWithProgressToken? meta}) =>
      ListPromptsRequest.fromMap({
        if (cursor != null) 'cursor': cursor,
        if (meta != null) '_meta': meta,
      });
}

/// The server's response to a prompts/list request from the client.
extension type ListPromptsResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListPromptsResult({
    required List<Prompt> prompts,
    Cursor? cursor,
    Meta? meta,
  }) => ListPromptsResult.fromMap({
    'prompts': prompts,
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });

  List<Prompt> get prompts => (_value['prompts'] as List).cast<Prompt>();
}

/// Used by the client to get a prompt provided by the server.
extension type GetPromptRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'prompts/get';

  factory GetPromptRequest({
    required String name,
    Map<String, Object?>? arguments,
    MetaWithProgressToken? meta,
  }) => GetPromptRequest.fromMap({
    'name': name,
    if (arguments != null) 'arguments': arguments,
    if (meta != null) '_meta': meta,
  });

  /// The name of the prompt or prompt template.
  String get name => _value['name'] as String;

  /// Arguments to use for templating the prompt.
  Map<String, Object?>? get arguments =>
      (_value['arguments'] as Map?)?.cast<String, Object?>();
}

/// The server's response to a prompts/get request from the client.
extension type GetPromptResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory GetPromptResult({
    String? description,
    required List<PromptMessage> messages,
    Meta? meta,
  }) => GetPromptResult.fromMap({
    if (description != null) 'description': description,
    'messages': messages,
    if (meta != null) '_meta': meta,
  });

  /// An optional description for the prompt.
  String? get description => _value['description'] as String?;

  /// All the messages in this prompt.
  ///
  /// Prompts may be entire conversation flows between users and assistants.
  List<PromptMessage> get messages =>
      (_value['messages'] as List).cast<PromptMessage>();
}

/// A prompt or prompt template that the server offers.
extension type Prompt.fromMap(Map<String, Object?> _value) {
  factory Prompt({
    required String name,
    String? description,
    List<PromptArgument>? arguments,
  }) => Prompt.fromMap({
    'name': name,
    if (description != null) 'description': description,
    if (arguments != null) 'arguments': arguments,
  });

  /// The name of the prompt or prompt template.
  String get name => _value['name'] as String;

  /// An optional description of what this prompt provides.
  String? get description => _value['description'] as String?;

  /// A list of arguments to use for templating the prompt.
  List<PromptArgument>? get arguments => (_value['arguments'] as List?)?.cast();
}

/// Describes an argument that a prompt can accept.
extension type PromptArgument.fromMap(Map<String, Object?> _value) {
  factory PromptArgument({
    required String name,
    String? description,
    bool? required,
  }) => PromptArgument.fromMap({
    'name': name,
    if (description != null) 'description': description,
    if (required != null) 'required': required,
  });

  /// The name of the argument.
  String get name => _value['name'] as String;

  /// A human-readable description of the argument.
  String? get description => _value['description'] as String?;

  /// Whether this argument must be provided.
  bool? get required => _value['required'] as bool?;
}

/// The sender or recipient of messages and data in a conversation.
enum Role { user, assistant }

/// Describes a message returned as part of a prompt.
///
/// This is similar to `SamplingMessage`, but also supports the embedding of
/// resources from the MCP server.
extension type PromptMessage.fromMap(Map<String, Object?> _value) {
  factory PromptMessage({required Role role, required List<Content> content}) =>
      PromptMessage.fromMap({'role': role.name, 'content': content});

  /// The expected [Role] for this message in the prompt (multi-message
  /// prompt flows may outline a back and forth between users and assistants).
  Role get role =>
      Role.values.firstWhere((role) => role.name == _value['role']);

  /// The content of the message, see [Content] docs for the possible types.
  Content get content => _value['content'] as Content;
}

/// An optional notification from the server to the client, informing it that
/// the list of prompts it offers has changed.
///
/// This may be issued by servers without any previous subscription from the
/// client.
extension type PromptListChangedNotification.fromMap(
  Map<String, Object?> _value
)
    implements Notification {
  static const methodName = 'notifications/prompts/list_changed';

  factory PromptListChangedNotification({Meta? meta}) =>
      PromptListChangedNotification.fromMap({if (meta != null) '_meta': meta});
}
