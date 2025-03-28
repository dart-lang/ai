// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

/// A mixin for MCP servers which support the `resources` capability.
///
/// Servers should add resources using the [addResource] method, typically
/// inside the [initialize] method, but they may also be added after
/// initialization if needed.
///
/// Resources can later be removed using [removeResource], or the client can be
/// notified of updates using [updateResource].
///
/// Implements the `subscribe` and `listChanges` capabilities for clients, so
/// they can be notified of changes to resources.
///
/// See https://modelcontextprotocol.io/docs/concepts/resources.
base mixin ResourcesSupport on MCPServer {
  /// The current resources by URI.
  final Map<String, Resource> _resources = {};

  /// The current resource implementations by URI.
  final Map<String, FutureOr<ReadResourceResult> Function(ReadResourceRequest)>
  _resourceImpls = {};

  /// The list of currently subscribed resources by URI.
  final Set<String> _subscribedResources = {};

  /// Invoked by the client as a part of initialization.
  ///
  /// Resources should usually be added in this function using [addResource]
  /// when possible.
  ///
  /// If resources are added, updated, or removed after [initialized] completes,
  /// then the client will be notified of the changes based on their
  /// subscription preferences.
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    _peer.registerMethod(
      ListResourcesRequest.methodName,
      convertParameters(_listResources),
    );

    _peer.registerMethod(
      ReadResourceRequest.methodName,
      convertParameters(_readResource),
    );

    _peer.registerMethod(
      SubscribeRequest.methodName,
      convertParameters(_subscribeResource),
    );
    _peer.registerMethod(
      UnsubscribeRequest.methodName,
      convertParameters(_unsubscribeResource),
    );

    var result = await super.initialize(request);
    (result.capabilities.resources ??= Resources())
      ..listChanged = true
      ..subscribe = true;
    return result;
  }

  /// Register [resource] to call [impl] when invoked.
  ///
  /// If this server is already initialized and still connected to a client,
  /// then the client will be notified that the resources list has changed.
  ///
  /// Throws a [StateError] if there is already a [Tool] registered with the
  /// same name.
  void addResource(
    Resource resource,
    FutureOr<ReadResourceResult> Function(ReadResourceRequest) impl,
  ) {
    if (_resources.containsKey(resource.uri)) {
      throw StateError(
        'Failed to add resource ${resource.name}, there is already a '
        'resource that exists at the URI ${resource.uri}.',
      );
    }
    _resources[resource.uri] = resource;
    _resourceImpls[resource.uri] = impl;

    if (ready) {
      _notifyResourceListChanged();
    }
  }

  /// Notifies the client that [resource] has been updated.
  ///
  /// The implementation of that resource can optionally be updated, otherwise
  /// the previous implementation will be used.
  ///
  /// Throws a [StateError] if [resource] does not exist.
  void updateResource(
    Resource resource, {
    FutureOr<ReadResourceResult> Function(ReadResourceRequest)? impl,
  }) {
    if (!_resources.containsKey(resource.uri)) {
      throw StateError(
        'Failed to update resource ${resource.name}, there is no resource '
        'at the URI ${resource.uri}, you must add it first using addResource.',
      );
    }
    if (impl != null) _resourceImpls[resource.uri] = impl;

    if (_subscribedResources.contains(resource.uri)) {
      _peer.sendNotification(
        ResourceUpdatedNotification.methodName,
        ResourceUpdatedNotification(uri: resource.uri),
      );
    }
  }

  /// Removes a [Resource] by [uri].
  ///
  /// Does not error if the resource hasn't been added yet.
  void removeResource(String uri) {
    _resources.remove(uri);
    _resourceImpls.remove(uri);
    if (ready) _notifyResourceListChanged();
  }

  /// Lists all the resources currently available.
  ListResourcesResult _listResources(ListResourcesRequest request) {
    return ListResourcesResult(resources: _resources.values.toList());
  }

  /// Reads the resource at `request.uri`.
  ///
  /// Throws an [ArgumentError] if it does not exist (this gets translated into
  /// a generic JSON RPC2 error response).
  FutureOr<ReadResourceResult> _readResource(ReadResourceRequest request) {
    final impl = _resourceImpls[request.uri];
    if (impl == null) {
      throw ArgumentError.value(request.uri, 'uri', 'Resource not found');
    }

    return impl(request);
  }

  /// Subscribes the client to the resource at `request.uri`.
  FutureOr<EmptyResult> _subscribeResource(SubscribeRequest request) async {
    if (!_resources.containsKey(request.uri)) {
      throw ArgumentError.value(request.uri, 'uri', 'Resource not found');
    }

    _subscribedResources.add(request.uri);

    return EmptyResult();
  }

  /// Unsubscribes the client to the resource at `request.uri`.
  FutureOr<EmptyResult> _unsubscribeResource(UnsubscribeRequest request) async {
    _subscribedResources.remove(request.uri);

    return EmptyResult();
  }

  /// Called whenever the list of resources changes, it is the job of the client
  /// to then ask again for the list of tools.
  void _notifyResourceListChanged() {
    _peer.sendNotification(
      ResourceListChangedNotification.methodName,
      ResourceListChangedNotification(),
    );
  }
}
