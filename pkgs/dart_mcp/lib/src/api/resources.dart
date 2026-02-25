// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// Sent from the client to request a list of resources the server has.
extension type ListResourcesRequest.fromMap(Map<String, Object?> _value)
    implements PaginatedRequest {
  static const methodName = 'resources/list';

  factory ListResourcesRequest({Cursor? cursor, MetaWithProgressToken? meta}) =>
      ListResourcesRequest.fromMap({
        if (cursor != null) Keys.cursor: cursor,
        if (meta != null) Keys.meta: meta,
      });
}

/// The server's response to a resources/list request from the client.
extension type ListResourcesResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListResourcesResult({
    required List<Resource> resources,
    Cursor? nextCursor,
    Meta? meta,
  }) => ListResourcesResult.fromMap({
    Keys.resources: resources,
    if (nextCursor != null) Keys.nextCursor: nextCursor,
    if (meta != null) Keys.meta: meta,
  });

  List<Resource> get resources =>
      (_value[Keys.resources] as List).cast<Resource>();
}

/// Sent from the client to request a list of resource templates the server
/// has.
extension type ListResourceTemplatesRequest.fromMap(Map<String, Object?> _value)
    implements PaginatedRequest {
  static const methodName = 'resources/templates/list';

  factory ListResourceTemplatesRequest({
    Cursor? cursor,
    MetaWithProgressToken? meta,
  }) => ListResourceTemplatesRequest.fromMap({
    if (cursor != null) Keys.cursor: cursor,
    if (meta != null) Keys.meta: meta,
  });
}

/// The server's response to a resources/templates/list request from the client.
extension type ListResourceTemplatesResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListResourceTemplatesResult({
    required List<ResourceTemplate> resourceTemplates,
    Cursor? nextCursor,
    Meta? meta,
  }) => ListResourceTemplatesResult.fromMap({
    Keys.resourceTemplates: resourceTemplates,
    if (nextCursor != null) Keys.nextCursor: nextCursor,
    if (meta != null) Keys.meta: meta,
  });

  List<ResourceTemplate> get resourceTemplates =>
      (_value[Keys.resourceTemplates] as List).cast<ResourceTemplate>();
}

/// Sent from the client to the server, to read a specific resource URI.
extension type ReadResourceRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'resources/read';

  factory ReadResourceRequest({
    required String uri,
    MetaWithProgressToken? meta,
  }) => ReadResourceRequest.fromMap({
    Keys.uri: uri,
    if (meta != null) Keys.meta: meta,
  });

  /// The URI of the resource to read. The URI can use any protocol; it is
  /// up to the server how to interpret it.
  String get uri {
    final uri = _value[Keys.uri] as String?;
    if (uri == null) {
      throw ArgumentError('Missing ${Keys.uri} field in $ReadResourceRequest.');
    }
    return uri;
  }
}

/// The server's response to a resources/read request from the client.
extension type ReadResourceResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory ReadResourceResult({
    required List<ResourceContents> contents,
    Meta? meta,
  }) => ReadResourceResult.fromMap({
    Keys.contents: contents,
    if (meta != null) Keys.meta: meta,
  });

  List<ResourceContents> get contents =>
      (_value[Keys.contents] as List).cast<ResourceContents>();
}

/// An optional notification from the server to the client, informing it that
/// the list of resources it can read from has changed.
///
/// This may be issued by servers without any previous subscription from the
/// client.
extension type ResourceListChangedNotification.fromMap(
  Map<String, Object?> _value
)
    implements Notification {
  static const methodName = 'notifications/resources/list_changed';

  factory ResourceListChangedNotification({Meta? meta}) =>
      ResourceListChangedNotification.fromMap({
        if (meta != null) Keys.meta: meta,
      });
}

/// Sent from the client to request resources/updated notifications from the
/// server whenever a particular resource changes.
extension type SubscribeRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'resources/subscribe';

  factory SubscribeRequest({
    required String uri,
    MetaWithProgressToken? meta,
  }) => SubscribeRequest.fromMap({
    Keys.uri: uri,
    if (meta != null) Keys.meta: meta,
  });

  /// The URI of the resource to subscribe to. The URI can use any protocol;
  /// it is up to the server how to interpret it.
  String get uri {
    final uri = _value[Keys.uri] as String?;
    if (uri == null) {
      throw ArgumentError('Missing ${Keys.uri} field in $SubscribeRequest.');
    }
    return uri;
  }
}

/// Sent from the client to request cancellation of resources/updated
/// notifications from the server.
///
/// This should follow a previous resources/subscribe request.
extension type UnsubscribeRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'resources/unsubscribe';

  factory UnsubscribeRequest({
    required String uri,
    MetaWithProgressToken? meta,
  }) => UnsubscribeRequest.fromMap({
    Keys.uri: uri,
    if (meta != null) Keys.meta: meta,
  });

  /// The URI of the resource to unsubscribe from.
  String get uri {
    final uri = _value[Keys.uri] as String?;
    if (uri == null) {
      throw ArgumentError('Missing uri field in $UnsubscribeRequest.');
    }
    return uri;
  }
}

/// A notification from the server to the client, informing it that a resource
/// has changed and may need to be read again.
///
/// This should only be sent if the client previously sent a
/// resources/subscribe request.
extension type ResourceUpdatedNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/resources/updated';

  factory ResourceUpdatedNotification({required String uri, Meta? meta}) =>
      ResourceUpdatedNotification.fromMap({
        Keys.uri: uri,
        if (meta != null) Keys.meta: meta,
      });

  /// The URI of the resource that has been updated.
  ///
  /// This might be a sub-resource of the one that the client actually
  /// subscribed to.
  String get uri => _value[Keys.uri] as String;
}

/// A known resource that the server is capable of reading.
extension type Resource.fromMap(Map<String, Object?> _value)
    implements Annotated, BaseMetadata, WithMetadata {
  factory Resource({
    required String uri,
    required String name,
    Annotations? annotations,
    String? description,
    String? mimeType,
    int? size,
    Meta? meta,
    List<Icon>? icons,
  }) => Resource.fromMap({
    Keys.uri: uri,
    Keys.name: name,
    if (annotations != null) Keys.annotations: annotations,
    if (description != null) Keys.description: description,
    if (mimeType != null) Keys.mimeType: mimeType,
    if (size != null) Keys.size: size,
    if (meta != null) Keys.meta: meta,
    if (icons != null) Keys.icons: icons,
  });

  /// The URI of this resource.
  String get uri => _value[Keys.uri] as String;

  /// A description of what this resource represents.
  ///
  /// This can be used by clients to improve the LLM's understanding of
  /// available resources. It can be thought of like a "hint" to the model.
  String? get description => _value[Keys.description] as String?;

  /// The MIME type of this resource, if known.
  String? get mimeType => _value[Keys.mimeType] as String?;

  /// The size of the raw resource content, in bytes (i.e., before base64
  /// encoding or any tokenization), if known.
  ///
  /// This can be used by Hosts to display file sizes and estimate context
  /// window usage.
  int? get size => _value[Keys.size] as int;

  /// Optional set of sized icons that the client can display in a user
  /// interface.
  List<Icon>? get icons => (_value[Keys.icons] as List?)?.cast<Icon>();
}

/// A template description for resources available on the server.
extension type ResourceTemplate.fromMap(Map<String, Object?> _value)
    implements Annotated, BaseMetadata, WithMetadata {
  factory ResourceTemplate({
    required String uriTemplate,
    required String name,
    String? title,
    String? description,
    Annotations? annotations,
    String? mimeType,
    Meta? meta,
    List<Icon>? icons,
  }) => ResourceTemplate.fromMap({
    Keys.uriTemplate: uriTemplate,
    Keys.name: name,
    if (title != null) Keys.title: title,
    if (description != null) Keys.description: description,
    if (annotations != null) Keys.annotations: annotations,
    if (mimeType != null) Keys.mimeType: mimeType,
    if (meta != null) Keys.meta: meta,
    if (icons != null) Keys.icons: icons,
  });

  /// A URI template (according to RFC 6570) that can be used to construct
  /// resource URIs.
  String get uriTemplate => _value[Keys.uriTemplate] as String;

  /// A description of what this template is for.
  ///
  /// This can be used by clients to improve the LLM's understanding of
  /// available resources. It can be thought of like a "hint" to the model.
  String? get description => _value[Keys.description] as String?;

  /// The MIME type for all resources that match this template.
  ///
  /// This should only be included if all resources matching this template have
  /// the same type.
  String? get mimeType => _value[Keys.mimeType] as String?;

  /// Optional set of sized icons that the client can display in a user
  /// interface.
  List<Icon>? get icons => (_value[Keys.icons] as List?)?.cast<Icon>();
}

/// Base class for the contents of a specific resource or sub-resource.
///
/// Could be either [TextResourceContents] or [BlobResourceContents],
/// use [isText] and [isBlob] before casting to the more specific type.
extension type ResourceContents.fromMap(Map<String, Object?> _value)
    implements WithMetadata {
  /// Whether or not this represents [TextResourceContents].
  bool get isText => _value.containsKey(Keys.text);

  /// Whether or not this represents [BlobResourceContents].
  bool get isBlob => _value.containsKey(Keys.blob);

  /// The URI of this resource.
  String get uri => _value[Keys.uri] as String;

  /// The MIME type of this resource, if known.
  String? get mimeType => _value[Keys.mimeType] as String?;
}

/// A [ResourceContents] that contains text.
extension type TextResourceContents.fromMap(Map<String, Object?> _value)
    implements ResourceContents {
  factory TextResourceContents({
    required String uri,
    required String text,
    String? mimeType,
    Meta? meta,
  }) => TextResourceContents.fromMap({
    Keys.uri: uri,
    Keys.text: text,
    if (mimeType != null) Keys.mimeType: mimeType,
    if (meta != null) Keys.meta: meta,
  });

  /// The text of the item.
  ///
  /// This must only be set if the item can actually be represented as text
  /// (not binary data).
  String get text => _value[Keys.text] as String;
}

/// A [ResourceContents] that contains binary data encoded as base64.
extension type BlobResourceContents.fromMap(Map<String, Object?> _value)
    implements ResourceContents {
  factory BlobResourceContents({
    required String uri,
    required String blob,
    String? mimeType,
    Meta? meta,
  }) => BlobResourceContents.fromMap({
    Keys.uri: uri,
    Keys.blob: blob,
    if (mimeType != null) Keys.mimeType: mimeType,
    if (meta != null) Keys.meta: meta,
  });

  /// A base64-encoded string representing the binary data of the item.
  String get blob => _value[Keys.blob] as String;
}
