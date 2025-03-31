// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// Sent from the client to request a list of tools the server has.
extension type ListToolsRequest.fromMap(Map<String, Object?> _value)
    implements PaginatedRequest {
  static const methodName = 'tools/list';

  factory ListToolsRequest({Cursor? cursor, MetaWithProgressToken? meta}) =>
      ListToolsRequest.fromMap({
        if (cursor != null) 'cursor': cursor,
        if (meta != null) '_meta': meta,
      });
}

/// The server's response to a tools/list request from the client.
extension type ListToolsResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListToolsResult({
    required List<Tool> tools,
    Cursor? cursor,
    Meta? meta,
  }) => ListToolsResult.fromMap({
    'tools': tools,
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });

  List<Tool> get tools => (_value['tools'] as List).cast<Tool>();
}

/// The server's response to a tool call.
///
/// Any errors that originate from the tool SHOULD be reported inside the result
/// object, with `isError` set to true, _not_ as an MCP protocol-level error
/// response. Otherwise, the LLM would not be able to see that an error occurred
/// and self-correct.
///
/// However, any errors in _finding_ the tool, an error indicating that the
/// server does not support tool calls, or any other exceptional conditions,
/// should be reported as an MCP error response.
extension type CallToolResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory CallToolResult({
    Meta? meta,
    required List<Content> content,
    bool? isError,
  }) => CallToolResult.fromMap({
    'content': content,
    if (isError != null) 'isError': isError,
    if (meta != null) '_meta': meta,
  });

  /// The type of content, either [TextContent], [ImageContent],
  /// or [EmbeddedResource],
  List<Content> get content => (_value['content'] as List).cast<Content>();

  /// Whether the tool call ended in an error.
  ///
  /// If not set, this is assumed to be false (the call was successful).
  bool? get isError => _value['isError'] as bool?;
}

/// Could be either [TextContent], [ImageContent] or [EmbeddedResource].
///
/// Use [isText], [isImage] and [isEmbeddedResource] before casting to the more
/// specific types, or switch on the [type] and then cast.
///
/// Doing `is` checks does not work because these are just extension types, they
/// all have the same runtime type (`Map<String, Object?>`).
extension type Content._(Map<String, Object?> _value) {
  factory Content.fromMap(Map<String, Object?> value) {
    assert(value.containsKey('type'));
    return Content._(value);
  }

  /// Whether or not this is a [TextContent].
  bool get isText => _value['type'] == TextContent.expectedType;

  /// Whether or not this is a [ImageContent].
  bool get isImage => _value['type'] == ImageContent.expectedType;

  /// Whether or not this is an [EmbeddedResource].
  bool get isEmbeddedResource =>
      _value['type'] == EmbeddedResource.expectedType;

  /// The type of content.
  ///
  /// You can use this in a switch to handle the various types (see the static
  /// `expectedType` getters), or you can use [isText], [isImage], and
  /// [isEmbeddedResource] to determine the type and then do the cast.
  String get type => _value['type'] as String;
}

/// Text provided to an LLM.
///
// TODO: implement `Annotated`.
extension type TextContent.fromMap(Map<String, Object?> _value)
    implements Content {
  static const expectedType = 'text';

  factory TextContent({required String text}) =>
      TextContent.fromMap({'text': text, 'type': expectedType});

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The text content.
  String get text => _value['text'] as String;
}

/// An image provided to an LLM.
///
// TODO: implement `Annotated`.
extension type ImageContent.fromMap(Map<String, Object?> _value)
    implements Content {
  static const expectedType = 'image';

  factory ImageContent({required String data, required String mimeType}) =>
      ImageContent.fromMap({
        'data': data,
        'mimeType': mimeType,
        'type': expectedType,
      });

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// If the [type] is `image`, this is the base64 encoded image data.
  String get data => _value['data'] as String;

  /// If the [type] is `image`, the MIME type of the image. Different providers
  /// may support different image types.
  String get mimeType => _value['mimeType'] as String;
}

/// The contents of a resource, embedded into a prompt or tool call result.
///
/// It is up to the client how best to render embedded resources for the benefit
/// of the LLM and/or the user.
///
// TODO: implement `Annotated`.
extension type EmbeddedResource.fromMap(Map<String, Object?> _value)
    implements Content {
  static const expectedType = 'resource';

  factory EmbeddedResource({required Content resource}) =>
      EmbeddedResource.fromMap({'resource': resource, 'type': expectedType});

  String get type {
    final type = _value['resource'] as String;
    assert(type == expectedType);
    return type;
  }

  /// Either [TextResourceContents] or [BlobResourceContents].
  ResourceContents get resource => _value['resource'] as ResourceContents;

  String? get mimeType => _value['mimeType'] as String?;
}

/// Used by the client to invoke a tool provided by the server.
extension type CallToolRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'tools/call';

  factory CallToolRequest({
    required String name,
    Map<String, Object?>? arguments,
    MetaWithProgressToken? meta,
  }) => CallToolRequest._fromMap({
    'name': name,
    if (arguments != null) 'arguments': arguments,
    if (meta != null) '_meta': meta,
  });

  /// The name of the method to invoke.
  String get name => _value['name'] as String;

  /// The arguments to pass to the method.
  Map<String, Object?>? get arguments =>
      (_value['arguments'] as Map?)?.cast<String, Object?>();
}

/// An optional notification from the server to the client, informing it that
/// the list of tools it offers has changed.
///
/// This may be issued by servers without any previous subscription from the
/// client.
extension type ToolListChangedNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/tools/list_changed';

  factory ToolListChangedNotification({Meta? meta}) =>
      ToolListChangedNotification.fromMap({if (meta != null) '_meta': meta});
}

/// Definition for a tool the client can call.
extension type Tool.fromMap(Map<String, Object?> _value) {
  factory Tool({
    required String name,
    String? description,
    required InputSchema inputSchema,
  }) => Tool.fromMap({
    'name': name,
    if (description != null) 'description': description,
    'inputSchema': inputSchema,
  });

  /// The name of the tool.
  String get name => _value['name'] as String;

  /// A human-readable description of the tool.
  String? get description => _value['description'] as String?;

  /// A JSON Schema object defining the expected parameters for the tool.
  InputSchema get inputSchema => _value['inputSchema'] as InputSchema;
}

/// A JSON Schema object defining the expected parameters for the tool.
extension type InputSchema.fromMap(Map<String, Object?> _value) {
  factory InputSchema({
    Map<String, Object?>? properties,
    List<String>? required,
  }) => InputSchema.fromMap({
    'type': 'object',
    if (properties != null) 'properties': properties,
    if (required != null) 'required': required,
  });

  String get type => _value['type'] as String;

  Map<String, Object?>? get properties =>
      (_value['properties'] as Map?)?.cast<String, Object?>();

  List<String>? get required => (_value['required'] as List?)?.cast<String>();
}
