// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// Sent from the server to request a list of root URIs from the client.
///
/// Roots allow servers to ask for specific directories or files to operate on.
/// A common example for roots is providing a set of repositories or directories
/// a server should operate on.
///
/// This request is typically used when the server needs to understand the
/// file system structure or access specific locations that the client has
/// permission to read from.
extension type ListRootsRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'roots/list';

  factory ListRootsRequest({MetaWithProgressToken? meta}) =>
      ListRootsRequest.fromMap({if (meta != null) '_meta': meta});
}

/// The client's response to a roots/list request from the server.
///
/// This result contains a list of [Root] objects, each representing a root
/// directory or file that the server can operate on.
extension type ListRootsResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory ListRootsResult({required List<Root> roots, Meta? meta}) =>
      ListRootsResult.fromMap({
        'roots': roots,
        if (meta != null) '_meta': meta,
      });

  List<Root> get roots {
    final roots = _value['roots'] as List?;
    if (roots == null) {
      throw ArgumentError('Missing roots field in $ListRootsResult.');
    }
    return roots.cast<Root>();
  }
}

/// Represents a root directory or file that the server can operate on.
extension type Root.fromMap(Map<String, Object?> _value)
    implements WithMetadata {
  factory Root({required String uri, String? name, Meta? meta}) =>
      Root.fromMap({
        'uri': uri,
        if (name != null) 'name': name,
        if (meta != null) '_meta': meta,
      });

  /// The URI identifying the root.
  ///
  /// This *must* start with file:// for now. This restriction may be relaxed
  /// in future versions of the protocol to allow other URI schemes.
  String get uri {
    final uri = _value['uri'] as String?;
    if (uri == null) {
      throw ArgumentError('Missing uri field in $Root.');
    }
    return uri;
  }

  /// An optional name for the root.
  ///
  /// This can be used to provide a human-readable identifier for the root,
  /// which may be useful for display purposes or for referencing the root in
  /// other parts of the application.
  String? get name => _value['name'] as String?;
}

/// A notification from the client to the server, informing it that the list
/// of roots has changed.
///
/// This notification should be sent whenever the client adds, removes, or
/// modifies any root.
/// The server should then request an updated list of roots using the
/// [ListRootsRequest].
extension type RootsListChangedNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/roots/list_changed';

  factory RootsListChangedNotification({Meta? meta}) =>
      RootsListChangedNotification.fromMap({if (meta != null) '_meta': meta});
}
