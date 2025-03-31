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
        if (cursor != null) 'cursor': cursor,
        if (meta != null) '_meta': meta,
      });
}

/// The server's response to a resources/list request from the client.
extension type ListResourcesResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListResourcesResult({
    required List<Resource> resources,
    Cursor? cursor,
    Meta? meta,
  }) => ListResourcesResult.fromMap({
    'resources': resources,
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });

  List<Resource> get resources =>
      (_value['resources'] as List).cast<Resource>();
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
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });
}

/// The server's response to a resources/templates/list request from the client.
extension type ListResourceTemplatesResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListResourceTemplatesResult({
    required List<ResourceTemplate> resourceTemplates,
    Cursor? cursor,
    Meta? meta,
  }) => ListResourceTemplatesResult.fromMap({
    'resourceTemplates': resourceTemplates,
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });

  List<ResourceTemplate> get resourceTemplates =>
      (_value['resourceTemplates'] as List).cast<ResourceTemplate>();
}

/// Sent from the client to the server, to read a specific resource URI.
extension type ReadResourceRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'resources/read';

  factory ReadResourceRequest({
    required String uri,
    MetaWithProgressToken? meta,
  }) => ReadResourceRequest.fromMap({
    'uri': uri,
    if (meta != null) '_meta': meta,
  });

  /// The URI of the resource to read. The URI can use any protocol; it is
  /// up to the server how to interpret it.
  String get uri => _value['uri'] as String;
}

/// The server's response to a resources/read request from the client.
extension type ReadResourceResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory ReadResourceResult({
    required List<ResourceContents> contents,
    Meta? meta,
  }) => ReadResourceResult.fromMap({
    'contents': contents,
    if (meta != null) '_meta': meta,
  });

  List<ResourceContents> get contents =>
      (_value['contents'] as List).cast<ResourceContents>();
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
        if (meta != null) '_meta': meta,
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
  }) => SubscribeRequest.fromMap({'uri': uri, if (meta != null) '_meta': meta});

  /// The URI of the resource to subscribe to. The URI can use any protocol;
  /// it is up to the server how to interpret it.
  String get uri => _value['uri'] as String;
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
  }) =>
      UnsubscribeRequest.fromMap({'uri': uri, if (meta != null) '_meta': meta});

  /// The URI of the resource to unsubscribe from.
  String get uri => _value['uri'] as String;
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
        'uri': uri,
        if (meta != null) '_meta': meta,
      });

  /// The URI of the resource that has been updated.
  ///
  /// This might be a sub-resource of the one that the client actually
  /// subscribed to.
  String get uri => _value['uri'] as String;
}

/// A known resource that the server is capable of reading.
extension type Resource.fromMap(Map<String, Object?> _value)
    implements Annotated {
  factory Resource({
    required String uri,
    required String name,
    Annotations? annotations,
    String? description,
    String? mimeType,
    int? size,
  }) => Resource.fromMap({
    'uri': uri,
    'name': name,
    if (annotations != null) 'annotations': annotations,
    if (description != null) 'description': description,
    if (mimeType != null) 'mimeType': mimeType,
    if (size != null) 'size': size,
  });

  /// The URI of this resource.
  String get uri => _value['uri'] as String;

  /// A human-readable name for this resource.
  ///
  /// This can be used by clients to populate UI elements.
  String get name => _value['name'] as String;

  /// A description of what this resource represents.
  ///
  /// This can be used by clients to improve the LLM's understanding of
  /// available resources. It can be thought of like a "hint" to the model.
  String? get description => _value['description'] as String?;

  /// The MIME type of this resource, if known.
  String? get mimeType => _value['mimeType'] as String?;

  /// The size of the raw resource content, in bytes (i.e., before base64
  /// encoding or any tokenization), if known.
  ///
  /// This can be used by Hosts to display file sizes and estimate context
  /// window usage.
  int? get size => _value['size'] as int;
}

/// A template description for resources available on the server.
extension type ResourceTemplate.fromMap(Map<String, Object?> _value)
    implements Annotated {
  factory ResourceTemplate({
    required String uriTemplate,
    required String name,
    Annotations? annotations,
    String? description,
    String? mimeType,
  }) => ResourceTemplate.fromMap({
    'uriTemplate': uriTemplate,
    'name': name,
    if (annotations != null) 'annotations': annotations,
    if (description != null) 'description': description,
    if (mimeType != null) 'mimeType': mimeType,
  });

  /// A URI template (according to RFC 6570) that can be used to construct
  /// resource URIs.
  String get uriTemplate => _value['uriTemplate'] as String;

  /// A human-readable name for the type of resource this template refers to.
  ///
  /// This can be used by clients to populate UI elements.
  String get name => _value['name'] as String;

  /// A description of what this template is for.
  ///
  /// This can be used by clients to improve the LLM's understanding of
  /// available resources. It can be thought of like a "hint" to the model.
  String? get description => _value['description'] as String?;

  /// The MIME type for all resources that match this template.
  ///
  /// This should only be included if all resources matching this template have
  /// the same type.
  String? get mimeType => _value['mimeType'] as String?;
}

/// Base class for the contents of a specific resource or sub-resource.
///
/// Could be either [TextResourceContents] or [BlobResourceContents],
/// use [isText] and [isBlob] before casting to the more specific type.
extension type ResourceContents.fromMap(Map<String, Object?> _value) {
  /// Whether or not this represents [TextResourceContents].
  bool get isText => _value.containsKey('text');

  /// Whether or not this represents [BlobResourceContents].
  bool get isBlob => _value.containsKey('blob');

  /// The URI of this resource.
  String get uri => _value['uri'] as String;

  /// The MIME type of this resource, if known.
  String? get mimeType => _value['mimeType'] as String?;
}

/// A [ResourceContents] that contains text.
extension type TextResourceContents.fromMap(Map<String, Object?> _value)
    implements ResourceContents {
  factory TextResourceContents({
    required String uri,
    required String text,
    String? mimeType,
  }) => TextResourceContents.fromMap({
    'uri': uri,
    'text': text,
    if (mimeType != null) 'mimeType': mimeType,
  });

  /// The text of the item.
  ///
  /// This must only be set if the item can actually be represented as text
  /// (not binary data).
  String get text => _value['text'] as String;
}

/// A [ResourceContents] that contains binary data encoded as base64.
extension type BlobResourceContents.fromMap(Map<String, Object?> _value)
    implements ResourceContents {
  factory BlobResourceContents({
    required String uri,
    required String blob,
    String? mimeType,
  }) => BlobResourceContents.fromMap({
    'uri': uri,
    'blob': blob,
    if (mimeType != null) 'mimeType': mimeType,
  });

  /// A base64-encoded string representing the binary data of the item.
  String get blob => _value['blob'] as String;
}
