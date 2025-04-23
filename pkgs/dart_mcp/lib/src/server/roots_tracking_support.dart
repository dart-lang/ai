// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// Mix this in to any MCPServer to add support tracking the [Root]s as given
/// by the client in an opinionated way.
///
/// Listens to change events and updates the set of [roots].
base mixin RootsTrackingSupport on LoggingSupport {
  /// All known workspace [Root]s from the last call to [listRoots].
  ///
  /// May be a [Future] if we are currently requesting the roots.
  FutureOr<List<Root>> get roots => switch (_rootsState) {
    _RootsState.upToDate => _roots!,
    _RootsState.pending => _rootsCompleter!.future,
  };

  /// The current state of [roots], whether it is up to date or waiting on
  /// updated values.
  _RootsState _rootsState = _RootsState.pending;

  /// The list of [roots] if [_rootsState] is [_RootsState.upToDate],
  /// otherwise `null`.
  List<Root>? _roots;

  /// Completer for any pending [listRoots] call if [_rootsState] is
  /// [_RootsState.pending], otherwise `null`.
  Completer<List<Root>>? _rootsCompleter = Completer();

  /// Whether or not the connected client supports [listRoots].
  ///
  /// Only safe to call after calling [initialize] on `super` since this is
  /// based on the client capabilities.
  bool get supportsRoots => clientCapabilities.roots != null;

  /// Whether or not the connected client supports reporting changes to the
  /// list of roots.
  ///
  /// Only safe to call after calling [initialize] on `super` since this is
  /// based on the client capabilities.
  bool get supportsRootsChanged =>
      clientCapabilities.roots?.listChanged == true;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    initialized.then((_) async {
      if (!supportsRoots) {
        log(
          LoggingLevel.warning,
          'Client does not support the roots capability, some functionality '
          'may be disabled.',
        );
      } else {
        if (supportsRootsChanged) {
          rootsListChanged!.listen((event) {
            updateRoots();
          });
        }
        await updateRoots();
      }
    });
    return super.initialize(request);
  }

  /// Updates the list of [roots] by calling [listRoots].
  ///
  /// If the current [_rootsCompleter] was not yet completed, then we wait to
  /// complete it until we get an updated list of roots, so that we don't get
  /// stale results from [listRoots] requests that are still in flight during
  /// a change notification.
  @mustCallSuper
  Future<void> updateRoots() async {
    _rootsState = _RootsState.pending;
    final previousCompleter = _rootsCompleter;

    // Always create a new completer so we can handle race conditions by
    // checking completer identity.
    final newCompleter = _rootsCompleter = Completer();
    _roots = null;

    if (previousCompleter != null) {
      // Complete previously scheduled completers with our completers value.
      previousCompleter.complete(newCompleter.future);
    }

    final result = await listRoots(ListRootsRequest());

    // Only complete the completer if it's still the one we created. Otherwise
    // we wait for the next result to come back and throw away this result.
    if (_rootsCompleter == newCompleter) {
      newCompleter.complete(result.roots);
      _roots = result.roots;
      _rootsCompleter = null;
      _rootsState = _RootsState.upToDate;
    }
  }
}

/// The current state of the roots information.
enum _RootsState {
  /// No change notification since our last update.
  upToDate,

  /// Waiting for a `listRoots` response.
  pending,
}
