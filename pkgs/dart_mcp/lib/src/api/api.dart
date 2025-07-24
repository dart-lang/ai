// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Interfaces are based on
/// https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-06-18/schema.ts
library;

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

part 'completions.dart';
part 'elicitation.dart';
part 'initialization.dart';
part 'logging.dart';
part 'prompts.dart';
part 'resources.dart';
part 'roots.dart';
part 'sampling.dart';
part 'tools.dart';

/// Enum of the known protocol versions.
enum ProtocolVersion {
  v2024_11_05('2024-11-05'),
  v2025_03_26('2025-03-26'),
  v2025_06_18('2025-06-18');

  const ProtocolVersion(this.versionString);

  /// Returns the [ProtocolVersion] based on the [version] string, or `null` if
  /// it was not recognized.
  static ProtocolVersion? tryParse(String version) =>
      values.firstWhereOrNull((v) => v.versionString == version);

  /// The oldest version supported by the current API.
  static const oldestSupported = ProtocolVersion.v2024_11_05;

  /// The most recent version supported by the current API.
  static const latestSupported = ProtocolVersion.v2025_06_18;

  /// The version string used over the wire to identify this version.
  final String versionString;

  /// Whether or not this API is compatible with the current version.
  ///
  /// **Note**: There may be extra fields included.
  bool get isSupported => this >= oldestSupported && this <= latestSupported;

  bool operator <(ProtocolVersion other) => index < other.index;
  bool operator <=(ProtocolVersion other) => index <= other.index;
  bool operator >(ProtocolVersion other) => index > other.index;
  bool operator >=(ProtocolVersion other) => index >= other.index;
}

/// A progress token, used to associate progress notifications with the original
/// request.
extension type ProgressToken( /*String|int*/ Object _) {}

/// An opaque token used to represent a cursor for pagination.
extension type Cursor(String _) {}

/// Generic metadata passed with most requests.
///
/// Metadata reserved by MCP to allow clients and servers to attach additional
/// metadata to their interactions.
///
/// Certain key names are reserved by MCP for protocol-level metadata, as
/// specified below; implementations MUST NOT make assumptions about values at
/// these keys.
///
/// Additionally, definitions in the schema may reserve particular names for
/// purpose-specific metadata, as declared in those definitions.
///
/// Key name format: valid `_meta` key names have two segments: an optional
/// prefix, and a name.
///
/// - Prefix: If specified, MUST be a series of labels separated by dots
///   (`.`), followed by a slash (`/`). Labels MUST start with a letter and
///   end with a letter or digit; interior characters can be letters, digits,
///   or hyphens (`-`). Any prefix beginning with zero or more valid labels,
///   followed by `modelcontextprotocol` or `mcp`, followed by any valid
///   label, is reserved for MCP use. For example: `modelcontextprotocol.io/`,
///   `mcp.dev/`, `api.modelcontextprotocol.org/`, and `tools.mcp.com/` are
///   all reserved.
/// - Name: Unless empty, MUST begin and end with an alphanumeric character
///   (`[a-z0-9A-Z]`). MAY contain hyphens (`-`), underscores (`_`), dots
///   (`.`), and alphanumerics in between.
extension type Meta.fromMap(Map<String, Object?> _value) {}

/// Basic metadata required by multiple types.
///
/// Not to be confused with the `_meta` property in the spec, which has a
/// different purpose.
extension type BaseMetadata.fromMap(Map<String, Object?> _value)
    implements Meta {
  factory BaseMetadata({required String name, String? title}) =>
      BaseMetadata.fromMap({'name': name, 'title': title});

  /// Intended for programmatic or logical use, but used as a display name in
  /// past specs for fallback (if title isn't present).
  String get name {
    final name = _value['name'] as String?;
    if (name == null) {
      throw ArgumentError('Missing name field in $runtimeType');
    }
    return name;
  }

  /// A short title for this object.
  ///
  /// Intended for UI and end-user contexts — optimized to be human-readable and
  /// easily understood, even by those unfamiliar with domain-specific
  /// terminology.
  ///
  /// If not provided, the name should be used for display (except for Tool,
  /// where `annotations.title` should be given precedence over using `name`, if
  /// present).
  String? get title => _value['title'] as String?;
}

/// A "mixin"-like extension type for any extension type that might contain a
/// [ProgressToken] at the key "progressToken".
///
/// Should be "mixed in" by implementing this type from other extension types.
extension type WithProgressToken.fromMap(Map<String, Object?> _value) {
  ProgressToken? get progressToken => _value['progressToken'] as ProgressToken?;
}

/// A [Meta] object with a known progress token key.
///
/// Has arbitrary other keys.
extension type MetaWithProgressToken.fromMap(Map<String, Object?> _value)
    implements Meta, WithProgressToken {
  factory MetaWithProgressToken({ProgressToken? progressToken}) =>
      MetaWithProgressToken.fromMap({'progressToken': progressToken});
}

/// Base interface for all types that can have arbitrary metadata attached.
///
/// Should not be constructed directly, and has no public constructor.
extension type WithMetadata._fromMap(Map<String, Object?> _value) {
  /// The `_meta` property/parameter is reserved by MCP to allow clients and
  /// servers to attach additional metadata to their interactions.
  ///
  /// See [Meta] for more information about the format of these values.
  Meta? get meta => _value['_meta'] as Meta?;
}

/// Base interface for all request types.
///
/// Should not be constructed directly, and has no public constructor.
extension type Request._fromMap(Map<String, Object?> _value)
    implements WithMetadata {
  /// If specified, the caller is requesting out-of-band progress notifications
  /// for this request (as represented by notifications/progress).
  ///
  /// The value of this parameter is an opaque token that will be attached to
  /// any subsequent notifications. The receiver is not obligated to provide
  /// these notifications.
  MetaWithProgressToken? get meta => _value['_meta'] as MetaWithProgressToken?;
}

/// Base interface for all notifications.
extension type Notification(Map<String, Object?> _value) {
  /// This parameter name is reserved by MCP to allow clients and servers to
  /// attach additional metadata to their notifications.
  Meta? get meta => _value['_meta'] as Meta?;
}

/// Base interface for all responses to requests.
extension type Result._(Map<String, Object?> _value) {
  Meta? get meta => _value['_meta'] as Meta?;
}

/// A response that indicates success but carries no data.
extension type EmptyResult.fromMap(Map<String, Object?> _) implements Result {
  factory EmptyResult() => EmptyResult.fromMap(const {});
}

/// This notification can be sent by either side to indicate that it is
/// cancelling a previously-issued request.
///
/// The request SHOULD still be in-flight, but due to communication latency, it
/// is always possible that this notification MAY arrive after the request has
/// already finished.
///
/// This notification indicates that the result will be unused, so any
/// associated processing SHOULD cease.
///
/// A client MUST NOT attempt to cancel its `initialize` request.
extension type CancelledNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/cancelled';

  factory CancelledNotification({
    required RequestId requestId,
    String? reason,
    Meta? meta,
  }) {
    return CancelledNotification.fromMap({
      'requestId': requestId,
      if (reason != null) 'reason': reason,
      if (meta != null) '_meta': meta,
    });
  }

  /// The ID of the request to cancel.
  ///
  /// This MUST correspond to the ID of a request previously issued in the same
  /// direction.
  RequestId? get requestId => _value['requestId'] as RequestId?;

  /// An optional string describing the reason for the cancellation. This MAY be
  /// logged or presented to the user.
  String? get reason => _value['reason'] as String?;
}

/// An opaque request ID.
extension type RequestId( /*String|int*/ Parameter _) {}

/// A ping, issued by either the server or the client, to check that the other
/// party is still alive.
///
/// The receiver must promptly respond, or else may be disconnected.
///
/// The request itself has no parameters.
extension type PingRequest._(Map<String, Object?> _) implements Request {
  static const methodName = 'ping';

  factory PingRequest({MetaWithProgressToken? meta}) =>
      PingRequest._({if (meta != null) '_meta': meta});
}

/// An out-of-band notification used to inform the receiver of a progress
/// update for a long-running request.
extension type ProgressNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/progress';

  factory ProgressNotification({
    required ProgressToken progressToken,
    required num progress,
    num? total,
    Meta? meta,
    String? message,
  }) => ProgressNotification.fromMap({
    'progressToken': progressToken,
    'progress': progress,
    if (total != null) 'total': total,
    if (meta != null) '_meta': meta,
    if (message != null) 'message': message,
  });

  /// The progress token which was given in the initial request, used to
  /// associate this notification with the request that is proceeding.
  ProgressToken get progressToken => _value['progressToken'] as ProgressToken;

  /// The progress thus far.
  ///
  /// This should increase every time progress is made, even if the total is
  /// unknown.
  num get progress => _value['progress'] as num;

  /// Total number of items to process (or total progress required), if
  /// known.
  num? get total => _value['total'] as num?;

  /// An optional message describing the current progress.
  String? get message => _value['message'] as String?;
}

/// A "mixin"-like extension type for any request that contains a [Cursor] at
/// the key "cursor".
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
extension type PaginatedRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  /// An opaque token representing the current pagination position.
  ///
  /// If provided, the server should return results starting after this cursor.
  Cursor? get cursor => _value['cursor'] as Cursor?;
}

/// A "mixin"-like extension type for any result type that contains a [Cursor]
/// at the key "cursor".
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
extension type PaginatedResult._fromMap(Map<String, Object?> _value)
    implements Result {
  Cursor? get nextCursor => _value['nextCursor'] as Cursor?;
}

/// Could be either [TextContent], [ImageContent], [AudioContent] or
/// [EmbeddedResource].
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

  /// Alias for [TextContent.new].
  static const text = TextContent.new;

  /// Alias for [ImageContent.new].
  static const image = ImageContent.new;

  /// Alias for [AudioContent.new].
  static const audio = AudioContent.new;

  /// Alias for [EmbeddedResource.new].
  static const embeddedResource = EmbeddedResource.new;

  /// Whether or not this is a [TextContent].
  bool get isText => _value['type'] == TextContent.expectedType;

  /// Whether or not this is an [ImageContent].
  bool get isImage => _value['type'] == ImageContent.expectedType;

  /// Whether or not this is an [AudioContent].
  bool get isAudio => _value['type'] == AudioContent.expectedType;

  /// Whether or not this is an [EmbeddedResource].
  bool get isEmbeddedResource =>
      _value['type'] == EmbeddedResource.expectedType;

  /// The type of content.
  ///
  /// You can use this in a switch to handle the various types (see the static
  /// `expectedType` getters), or you can use [isText], [isImage], [isAudio] and
  /// [isEmbeddedResource] to determine the type and then do the cast.
  String get type => _value['type'] as String;
}

/// Text provided to or from an LLM.
extension type TextContent.fromMap(Map<String, Object?> _value)
    implements Content, Annotated, WithMetadata {
  static const expectedType = 'text';

  factory TextContent({
    required String text,
    Annotations? annotations,
    Meta? meta,
  }) => TextContent.fromMap({
    'text': text,
    'type': expectedType,
    if (annotations != null) 'annotations': annotations,
    if (meta != null) '_meta': meta,
  });

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The text content.
  String get text => _value['text'] as String;
}

/// An image provided to or from an LLM.
extension type ImageContent.fromMap(Map<String, Object?> _value)
    implements Content, Annotated, WithMetadata {
  static const expectedType = 'image';

  factory ImageContent({
    required String data,
    required String mimeType,
    Annotations? annotations,
    Meta? meta,
  }) => ImageContent.fromMap({
    'data': data,
    'mimeType': mimeType,
    'type': expectedType,
    if (annotations != null) 'annotations': annotations,
    if (meta != null) '_meta': meta,
  });

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The base64 encoded image data.
  String get data => _value['data'] as String;

  /// The MIME type of the image.
  ///
  /// Different providers may support different image types.
  String get mimeType => _value['mimeType'] as String;
}

/// Audio provided to or from an LLM.
///
/// Only supported since version [ProtocolVersion.v2025_03_26].
extension type AudioContent.fromMap(Map<String, Object?> _value)
    implements Content, Annotated, WithMetadata {
  static const expectedType = 'audio';

  factory AudioContent({
    required String data,
    required String mimeType,
    Annotations? annotations,
    Meta? meta,
  }) => AudioContent.fromMap({
    'data': data,
    'mimeType': mimeType,
    'type': expectedType,
    if (annotations != null) 'annotations': annotations,
    if (meta != null) '_meta': meta,
  });

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The base64 encoded audio data.
  String get data => _value['data'] as String;

  /// The MIME type of the audio.
  ///
  /// Different providers may support different audio types.
  String get mimeType => _value['mimeType'] as String;
}

/// The contents of a resource, embedded into a prompt or tool call result.
///
/// It is up to the client how best to render embedded resources for the benefit
/// of the LLM and/or the user.
extension type EmbeddedResource.fromMap(Map<String, Object?> _value)
    implements Content, Annotated, WithMetadata {
  static const expectedType = 'resource';

  factory EmbeddedResource({
    required Content resource,
    Annotations? annotations,
    Meta? meta,
  }) => EmbeddedResource.fromMap({
    'resource': resource,
    'type': expectedType,
    if (annotations != null) 'annotations': annotations,
    if (meta != null) '_meta': meta,
  });

  String get type {
    final type = _value['resource'] as String;
    assert(type == expectedType);
    return type;
  }

  /// Either [TextResourceContents] or [BlobResourceContents].
  ResourceContents get resource => _value['resource'] as ResourceContents;

  String? get mimeType => _value['mimeType'] as String?;
}

/// A resource link returned from a tool.
///
/// Resource links returned by tools are not guaranteed to appear in the results
/// of a `resources/list` request.
extension type ResourceLink.fromMap(Map<String, Object?> _value)
    implements Content, Annotated, WithMetadata, BaseMetadata {
  static const expectedType = 'resource_link';

  factory ResourceLink({
    required String name,
    String? title,
    required String description,
    required String uri,
    required String mimeType,
    Annotations? annotations,
    Meta? meta,
  }) => ResourceLink.fromMap({
    'name': name,
    if (title != null) 'title': title,
    'description': description,
    'uri': uri,
    'mimeType': mimeType,
    'type': expectedType,
    if (annotations != null) 'annotations': annotations,
    if (meta != null) '_meta': meta,
  });

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The description of the resource.
  String get description {
    final description = _value['description'] as String?;
    if (description == null) {
      throw ArgumentError('Missing description field in $ResourceLink.');
    }
    return description;
  }

  /// The URI of the resource.
  String get uri {
    final uri = _value['uri'] as String?;
    if (uri == null) {
      throw ArgumentError('Missing uri field in $ResourceLink.');
    }
    return uri;
  }

  /// The MIME type of the resource.
  String get mimeType {
    final mimeType = _value['mimeType'] as String?;
    if (mimeType == null) {
      throw ArgumentError('Missing mimeType field in $ResourceLink.');
    }
    return mimeType;
  }
}

/// Base type for objects that include optional annotations for the client.
///
/// The client can use annotations to inform how objects are used or displayed.
extension type Annotated._fromMap(Map<String, Object?> _value) {
  /// Annotations for this object.
  Annotations? get annotations => _value['annotations'] as Annotations?;
}

/// The annotations for an [Annotated] object.
extension type Annotations.fromMap(Map<String, Object?> _value) {
  factory Annotations({
    List<Role>? audience,
    DateTime? lastModified,
    double? priority,
  }) {
    assert(priority == null || (priority >= 0 && priority <= 1));
    return Annotations.fromMap({
      if (audience != null) 'audience': [for (var role in audience) role.name],
      if (lastModified != null) 'lastModified': lastModified.toIso8601String(),
      if (priority != null) 'priority': priority,
    });
  }

  /// Describes who the intended customer of this object or data is.
  ///
  /// It can include multiple entries to indicate content useful for
  /// multiple audiences (e.g., `[Role.user, Role.assistant]`).
  List<Role>? get audience {
    final audience = _value['audience'] as List?;
    if (audience == null) return null;
    return [
      for (var role in audience) Role.values.firstWhere((e) => e.name == role),
    ];
  }

  /// Describes when this data was last modified.
  ///
  /// The moment the resource was last modified.
  ///
  /// Examples: last activity timestamp in an open file, timestamp when the
  /// resource was attached, etc.
  DateTime? get lastModified {
    final lastModified = _value['lastModified'] as String?;
    if (lastModified == null) return null;
    return DateTime.parse(lastModified);
  }

  /// Describes how important this data is for operating the server.
  ///
  /// A value of 1 means "most important," and indicates that the data is
  /// effectively required, while 0 means "least important," and indicates
  /// that the data is entirely optional.
  ///
  /// Must be between 0 and 1.
  double? get priority => _value['priority'] as double?;
}
