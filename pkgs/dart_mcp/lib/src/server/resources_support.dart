// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'server.dart';

typedef ReadResourceHandler =
    FutureOr<ReadResourceResult?> Function(ReadResourceRequest);

/// A mixin for MCP servers which support the `resources` capability.
///
/// Servers should add [Resource]s using the [addResource] method, typically
/// inside the [initialize] method or constructor, but they may also be added
/// after initialization if needed.
///
/// Resources can later be removed using [removeResource], or the client can be
/// notified of updates using [updateResource].
///
/// Implements the `subscribe` and `listChanges` capabilities for clients, so
/// they can be notified of changes to resources.
///
/// Any [ResourceTemplate]s, should typically be added in [initialize] method or
/// the constructor using [addResourceTemplate]. There is no notification
/// protocol for templates which are added after a client requests them once, so
/// they should be added eagerly.
///
/// See https://modelcontextprotocol.io/docs/concepts/resources.
base mixin ResourcesSupport on MCPServer {
  /// The current resources by URI.
  final Map<String, Resource> _resources = {};

  /// The current resource implementations by URI.
  final Map<String, ReadResourceHandler> _resourceImpls = {};

  /// All the resource templates supported by this server, see
  /// [addResourceTemplate].
  final List<({ResourceTemplate template, ReadResourceHandler handler})>
  _resourceTemplates = [];

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
    registerRequestHandler(ListResourcesRequest.methodName, _listResources);
    registerRequestHandler(
      ListResourceTemplatesRequest.methodName,
      _listResourceTemplates,
    );

    registerRequestHandler(ReadResourceRequest.methodName, _readResource);

    registerRequestHandler(SubscribeRequest.methodName, _subscribeResource);
    registerRequestHandler(UnsubscribeRequest.methodName, _unsubscribeResource);

    final result = await super.initialize(request);
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
  /// Throws a [StateError] if there is already a [Resource] registered with the
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

  /// Adds the [ResourceTemplate] [template] with [handler].
  ///
  /// When reading resources, first regular resources added by [addResource]
  /// are prioritized. Then, we call the [handler] for each [template], in the
  /// order they were added (using this method), and the first one to return a
  /// non-null response wins. This package does not automatically handle
  /// matching of templates and handlers must accept URIs in any form.
  ///
  /// Throws a [StateError] if there is already a template registered with the
  /// same uri template.
  void addResourceTemplate(
    ResourceTemplate template,
    ReadResourceHandler handler,
  ) {
    if (_resourceTemplates.any(
      (t) => t.template.uriTemplate == template.uriTemplate,
    )) {
      throw StateError(
        'Failed to add resource template ${template.name}, there is '
        'already a resource template with the same uri pattern '
        '${template.uriTemplate}.',
      );
    }
    _resourceTemplates.add((template: template, handler: handler));
  }

  /// Lists all the [ResourceTemplate]s currently available.
  ListResourceTemplatesResult _listResourceTemplates(
    ListResourceTemplatesRequest request,
  ) {
    return ListResourceTemplatesResult(
      resourceTemplates: [
        for (var descriptor in _resourceTemplates) descriptor.template,
      ],
    );
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
      sendNotification(
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
  FutureOr<ReadResourceResult> _readResource(
    ReadResourceRequest request,
  ) async {
    final impl = _resourceImpls[request.uri];
    if (impl == null) {
      // Check if it matches any resource template.
      for (var descriptor in _resourceTemplates) {
        final response = await descriptor.handler(request);
        if (response != null) return response;
      }
    }

    final response = await impl?.call(request);
    if (response == null) {
      throw ArgumentError.value(request.uri, 'uri', 'Resource not found');
    }
    return response;
  }

  /// Subscribes the client to the resource at `request.uri`.
  FutureOr<EmptyResult> _subscribeResource(SubscribeRequest request) {
    if (!_resources.containsKey(request.uri)) {
      throw ArgumentError.value(request.uri, 'uri', 'Resource not found');
    }

    _subscribedResources.add(request.uri);

    return EmptyResult();
  }

  /// Unsubscribes the client to the resource at `request.uri`.
  FutureOr<EmptyResult> _unsubscribeResource(UnsubscribeRequest request) {
    _subscribedResources.remove(request.uri);

    return EmptyResult();
  }

  /// Called whenever the list of resources changes, it is the job of the client
  /// to then ask again for the list of tools.
  void _notifyResourceListChanged() => sendNotification(
    ResourceListChangedNotification.methodName,
    ResourceListChangedNotification(),
  );
}
