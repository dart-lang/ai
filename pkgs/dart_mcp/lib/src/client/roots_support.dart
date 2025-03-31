// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

/// Adds support for "roots" to an [MCPClient].
///
/// Supports "listChanged" notifications.
///
/// See https://spec.modelcontextprotocol.io/specification/2025-03-26/client/roots/.
base mixin RootsSupport on MCPClient {
  /// The known roots by URI.
  ///
  /// These are compared using only the [Root.uri].
  final _roots = HashSet<Root>(
    equals: (a, b) => a.uri == b.uri,
    hashCode: (a) => a.uri.hashCode,
  );

  @override
  void initialize() {
    (capabilities.roots ??= RootsCapabilities()).listChanged = true;
    super.initialize();
  }

  /// Adds a [Root] to the set of roots.
  ///
  /// Returns `true` if [root] was added, and `false` if a [Root] with
  /// the same URI was already present.
  ///
  /// Notifies all connected servers of the change to the list of roots, if the
  /// [root] was added.
  bool addRoot(Root root) {
    var changed = _roots.add(root);
    if (changed) _notifyRootsListChanged();
    return changed;
  }

  /// Removes a [Root] by it's [Root.uri].
  ///
  /// Returns `true` if [root] was removed, and `false` if no [Root] with
  /// a matching URI was present.
  ///
  /// Notifies all connected servers of the change to the list of roots, if
  /// a root was in fact removed.
  bool removeRoot(Root root) {
    var removed = _roots.remove(root);
    if (removed) _notifyRootsListChanged();
    return removed;
  }

  /// Called whenever the list of roots changes, it is the job of the server to
  /// then ask for the list of roots.
  void _notifyRootsListChanged() {
    for (var server in _connections.values) {
      server.sendNotification(
        RootsListChangedNotification.methodName,
        RootsListChangedNotification(),
      );
    }
  }

  /// Handler for [ListRootsRequest]s - returns the available [Root]s.
  FutureOr<ListRootsResult> handleListRoots(ListRootsRequest request) =>
      ListRootsResult(roots: _roots.toList());
}
