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
        if (cursor != null) Keys.cursor: cursor,
        if (meta != null) Keys.meta: meta,
      });
}

/// The server's response to a prompts/list request from the client.
extension type ListPromptsResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListPromptsResult({
    required List<Prompt> prompts,
    Cursor? nextCursor,
    Meta? meta,
  }) => ListPromptsResult.fromMap({
    Keys.prompts: prompts,
    if (nextCursor != null) Keys.nextCursor: nextCursor,
    if (meta != null) Keys.meta: meta,
  });

  List<Prompt> get prompts => (_value[Keys.prompts] as List).cast<Prompt>();
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
    Keys.name: name,
    if (arguments != null) Keys.arguments: arguments,
    if (meta != null) Keys.meta: meta,
  });

  /// The name of the prompt or prompt template.
  String get name {
    final name = _value[Keys.name] as String?;
    if (name == null) {
      throw ArgumentError('Missing ${Keys.name} field in $GetPromptRequest.');
    }
    return name;
  }

  /// Arguments to use for templating the prompt.
  Map<String, Object?>? get arguments =>
      (_value[Keys.arguments] as Map?)?.cast<String, Object?>();
}

/// The server's response to a prompts/get request from the client.
extension type GetPromptResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory GetPromptResult({
    String? description,
    required List<PromptMessage> messages,
    Meta? meta,
  }) => GetPromptResult.fromMap({
    if (description != null) Keys.description: description,
    Keys.messages: messages,
    if (meta != null) Keys.meta: meta,
  });

  /// An optional description for the prompt.
  String? get description => _value[Keys.description] as String?;

  /// All the messages in this prompt.
  ///
  /// Prompts may be entire conversation flows between users and assistants.
  List<PromptMessage> get messages =>
      (_value[Keys.messages] as List).cast<PromptMessage>();
}

/// A prompt or prompt template that the server offers.
extension type Prompt.fromMap(Map<String, Object?> _value)
    implements BaseMetadata, WithMetadata {
  factory Prompt({
    required String name,
    String? title,
    String? description,
    List<PromptArgument>? arguments,
    List<Icon>? icons,
    Meta? meta,
  }) => Prompt.fromMap({
    Keys.name: name,
    if (title != null) Keys.title: title,
    if (description != null) Keys.description: description,
    if (arguments != null) Keys.arguments: arguments,
    if (icons != null) Keys.icons: icons,
    if (meta != null) Keys.meta: meta,
  });

  /// An optional description of what this prompt provides.
  String? get description => _value[Keys.description] as String?;

  /// A list of arguments to use for templating the prompt.
  List<PromptArgument>? get arguments =>
      (_value[Keys.arguments] as List?)?.cast();

  /// Optional set of sized icons that the client can display in a user
  /// interface.
  List<Icon>? get icons => (_value[Keys.icons] as List?)?.cast<Icon>();
}

/// Describes an argument that a prompt can accept.
extension type PromptArgument.fromMap(Map<String, Object?> _value)
    implements BaseMetadata {
  factory PromptArgument({
    required String name,
    String? title,
    String? description,
    bool? required,
  }) => PromptArgument.fromMap({
    Keys.name: name,
    if (title != null) Keys.title: title,
    if (description != null) Keys.description: description,
    if (required != null) Keys.required: required,
  });

  /// A human-readable description of the argument.
  String? get description => _value[Keys.description] as String?;

  /// Whether this argument must be provided.
  bool? get required => _value[Keys.required] as bool?;
}

/// The sender or recipient of messages and data in a conversation.
enum Role { user, assistant }

/// Describes a message returned as part of a prompt.
///
/// This is similar to `SamplingMessage`, but also supports the embedding of
/// resources from the MCP server.
extension type PromptMessage.fromMap(Map<String, Object?> _value) {
  factory PromptMessage({required Role role, required Content content}) =>
      PromptMessage.fromMap({Keys.role: role.name, Keys.content: content});

  /// The expected [Role] for this message in the prompt (multi-message
  /// prompt flows may outline a back and forth between users and assistants).
  Role get role =>
      Role.values.firstWhere((value) => value.name == _value[Keys.role]);

  /// The content of the message, see [Content] docs for the possible types.
  Content get content => _value[Keys.content] as Content;
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
      PromptListChangedNotification.fromMap({
        if (meta != null) Keys.meta: meta,
      });
}
