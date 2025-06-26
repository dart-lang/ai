// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// This request is sent from the client to the server when it first connects,
/// asking it to begin initialization.
extension type InitializeRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'initialize';

  factory InitializeRequest({
    required ProtocolVersion protocolVersion,
    required ClientCapabilities capabilities,
    required Implementation clientInfo,
    MetaWithProgressToken? meta,
  }) => InitializeRequest._fromMap({
    'protocolVersion': protocolVersion.versionString,
    'capabilities': capabilities,
    'clientInfo': clientInfo,
    if (meta != null) '_meta': meta,
  });

  /// The latest version of the Model Context Protocol that the client supports.
  ///
  /// The client MAY decide to support older versions as well.
  ///
  /// May be `null` if the version is not recognized.
  ProtocolVersion? get protocolVersion =>
      ProtocolVersion.tryParse(_value['protocolVersion'] as String);

  ClientCapabilities get capabilities {
    final capabilities = _value['capabilities'] as ClientCapabilities?;
    if (capabilities == null) {
      throw ArgumentError('Missing capabilities field in $InitializeRequest.');
    }
    return capabilities;
  }

  Implementation get clientInfo {
    final clientInfo = _value['clientInfo'] as Implementation?;
    if (clientInfo == null) {
      throw ArgumentError('Missing clientInfo field in $InitializeRequest.');
    }
    return clientInfo;
  }
}

/// After receiving an initialize request from the client, the server sends
/// this response.
extension type InitializeResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory InitializeResult({
    required ProtocolVersion protocolVersion,
    required ServerCapabilities serverCapabilities,
    required Implementation serverInfo,
    String? instructions,
  }) => InitializeResult.fromMap({
    'protocolVersion': protocolVersion.versionString,
    'capabilities': serverCapabilities,
    'serverInfo': serverInfo,
    'instructions': instructions,
  });

  /// The version of the Model Context Protocol that the server wants to use.
  ///
  /// This may not match the version that the client requested. If the client
  /// cannot support this version, it MUST disconnect.
  ///
  /// May be `null` if the version is not recognized.
  ProtocolVersion? get protocolVersion =>
      ProtocolVersion.tryParse(_value['protocolVersion'] as String);

  /// Sets the protocol version, by default this is set for you, but you can
  /// override it to a specific version if desired.
  ///
  /// While this API is typed as nullable, `null` is not an allowed value.
  set protocolVersion(ProtocolVersion? value) {
    assert(value != null);
    _value['protocolVersion'] = value!.versionString;
  }

  ServerCapabilities get capabilities =>
      _value['capabilities'] as ServerCapabilities;

  Implementation get serverInfo => _value['serverInfo'] as Implementation;

  /// Instructions describing how to use the server and its features.
  ///
  /// This can be used by clients to improve the LLM's understanding of
  /// available tools, resources, etc. It can be thought of like a "hint" to the
  /// model. For example, this information MAY be added to the system prompt.
  String? get instructions => _value['instructions'] as String?;
}

/// This notification is sent from the client to the server after initialization
/// has finished.
extension type InitializedNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/initialized';

  factory InitializedNotification({Meta? meta}) =>
      InitializedNotification.fromMap({if (meta != null) '_meta': meta});
}

/// Capabilities a client may support.
///
/// Known capabilities are defined here, in this schema, but this is not a
/// closed set: any client can define its own, additional capabilities.
extension type ClientCapabilities.fromMap(Map<String, Object?> _value) {
  factory ClientCapabilities({
    Map<String, Object?>? experimental,
    RootsCapabilities? roots,
    Map<String, Object?>? sampling,
    ElicitationCapability? elicitation,
  }) => ClientCapabilities.fromMap({
    if (experimental != null) 'experimental': experimental,
    if (roots != null) 'roots': roots,
    if (sampling != null) 'sampling': sampling,
    if (elicitation != null) 'elicitation': elicitation,
  });

  /// Experimental, non-standard capabilities that the client supports.
  Map<String, Object?>? get experimental =>
      _value['experimental'] as Map<String, Object?>?;

  /// Sets [experimental] asserting it is non-null first.
  set experimental(Map<String, Object?>? value) {
    assert(experimental == null);
    _value['experimental'] = value;
  }

  /// Present if the client supports any capabilities regarding roots.
  RootsCapabilities? get roots => _value['roots'] as RootsCapabilities?;

  /// Sets [roots] asserting it is non-null first.
  set roots(RootsCapabilities? value) {
    assert(roots == null);
    _value['roots'] = value;
  }

  /// Present if the client supports sampling from an LLM.
  Map<String, Object?>? get sampling =>
      (_value['sampling'] as Map?)?.cast<String, Object?>();

  /// Sets [sampling] asserting it is non-null first.
  set sampling(Map<String, Object?>? value) {
    assert(sampling == null);
    _value['sampling'] = value;
  }

  /// Present if the client supports elicitation.
  ElicitationCapability? get elicitation =>
      _value['elicitation'] as ElicitationCapability?;

  /// Sets [elicitation], asserting it is null first.
  set elicitation(ElicitationCapability? value) {
    assert(elicitation == null);
    _value['elicitation'] = value;
  }
}

/// Whether the client supports notifications for changes to the roots list.
extension type RootsCapabilities.fromMap(Map<String, Object?> _value) {
  factory RootsCapabilities({bool? listChanged}) => RootsCapabilities.fromMap({
    if (listChanged != null) 'listChanged': listChanged,
  });

  /// Present if the client supports listing roots.
  bool? get listChanged => _value['listChanged'] as bool?;

  /// Sets whether [listChanged] is supported.
  set listChanged(bool? value) {
    assert(listChanged == null);
    _value['listChanged'] = value;
  }
}

/// Whether the client supports elicitation.
extension type ElicitationCapability.fromMap(Map<String, Object?> _value) {
  factory ElicitationCapability() => ElicitationCapability.fromMap({});
}

/// Capabilities that a server may support.
///
/// Known capabilities are defined here, in this schema, but this is not a
/// closed set: any server can define its own, additional capabilities.
extension type ServerCapabilities.fromMap(Map<String, Object?> _value) {
  factory ServerCapabilities({
    Map<String, Object?>? experimental,
    Completions? completions,
    Logging? logging,
    Prompts? prompts,
    Resources? resources,
    Tools? tools,
    Elicitation? elicitation,
  }) => ServerCapabilities.fromMap({
    if (experimental != null) 'experimental': experimental,
    if (logging != null) 'logging': logging,
    if (prompts != null) 'prompts': prompts,
    if (resources != null) 'resources': resources,
    if (tools != null) 'tools': tools,
    if (elicitation != null) 'elicitation': elicitation,
  });

  /// Experimental, non-standard capabilities that the server supports.
  Map<String, Object?>? get experimental =>
      (_value['experimental'] as Map?)?.cast<String, Object?>();

  /// Sets [experimental] if it is null, otherwise throws.
  set experimental(Map<String, Object?>? value) {
    assert(experimental == null);
    _value['experimental'] = value;
  }

  /// Present if the server supports sending completion requests to the client.
  Completions? get completions => _value['completions'] as Completions?;

  /// Sets [completions] if it is null, otherwise throws.
  set completions(Completions? value) {
    assert(completions == null);
    _value['completions'] = value;
  }

  /// Present if the server supports sending log messages to the client.
  Logging? get logging =>
      (_value['logging'] as Map?)?.cast<String, Object?>() as Logging?;

  /// Sets [logging] if it is null, otherwise throws.
  set logging(Logging? value) {
    assert(logging == null);
    _value['logging'] = value;
  }

  /// Present if the server offers any prompt templates.
  Prompts? get prompts => _value['prompts'] as Prompts?;

  /// Sets [prompts] if it is null, otherwise throws.
  set prompts(Prompts? value) {
    assert(prompts == null);
    _value['prompts'] = value;
  }

  /// Whether this server supports subscribing to resource updates.
  Resources? get resources => _value['resources'] as Resources?;

  /// Sets [resources] if it is null, otherwise throws.
  set resources(Resources? value) {
    assert(resources == null);
    _value['resources'] = value;
  }

  /// Present if the server offers any tools to call.
  Tools? get tools => _value['tools'] as Tools?;

  /// Sets [tools] if it is null, otherwise throws.
  set tools(Tools? value) {
    assert(tools == null);
    _value['tools'] = value;
  }

  /// Present if the server supports elicitation.
  Elicitation? get elicitation => _value['elicitation'] as Elicitation?;

  /// Sets [elicitation] if it is null, otherwise asserts.
  set elicitation(Elicitation? value) {
    assert(elicitation == null);
    _value['elicitation'] = value;
  }
}

/// Completions parameter for [ServerCapabilities].
extension type Completions.fromMap(Map<String, Object?> _value) {
  factory Completions() => Completions.fromMap({});
}

/// Prompts parameter for [ServerCapabilities].
extension type Prompts.fromMap(Map<String, Object?> _value) {
  factory Prompts({bool? listChanged}) =>
      Prompts.fromMap({if (listChanged != null) 'listChanged': listChanged});

  /// Whether this server supports notifications for changes to the prompt list.
  bool? get listChanged => _value['listChanged'] as bool?;

  /// Sets whether [listChanged] is supported.
  set listChanged(bool? value) {
    assert(listChanged == null);
    _value['listChanged'] = value;
  }
}

/// Resources parameter for [ServerCapabilities].
extension type Resources.fromMap(Map<String, Object?> _value) {
  factory Resources({bool? listChanged, bool? subscribe}) => Resources.fromMap({
    if (listChanged != null) 'listChanged': listChanged,
    if (subscribe != null) 'subscribe': subscribe,
  });

  /// Whether this server supports notifications for changes to the resource
  /// list.
  bool? get listChanged => _value['listChanged'] as bool?;

  /// Sets whether [listChanged] is supported.
  set listChanged(bool? value) {
    assert(listChanged == null);
    _value['listChanged'] = value;
  }

  /// Present if the server offers any resources to read.
  bool? get subscribe => _value['subscribe'] as bool?;

  /// Sets whether [subscribe] is supported.
  set subscribe(bool? value) {
    assert(subscribe == null);
    _value['subscribe'] = value;
  }
}

/// Tools parameter for [ServerCapabilities].
extension type Tools.fromMap(Map<String, Object?> _value) {
  factory Tools({bool? listChanged}) =>
      Tools.fromMap({if (listChanged != null) 'listChanged': listChanged});

  /// Whether this server supports notifications for changes to the tool list.
  bool? get listChanged => _value['listChanged'] as bool?;

  /// Sets whether [listChanged] is supported.
  set listChanged(bool? value) {
    assert(listChanged == null);
    _value['listChanged'] = value;
  }
}

/// Elicitation parameter for [ServerCapabilities].
extension type Elicitation.fromMap(Map<String, Object?> _value) {
  factory Elicitation() => Elicitation.fromMap({});
}

/// Describes the name and version of an MCP implementation.
extension type Implementation.fromMap(Map<String, Object?> _value)
    implements BaseMetadata {
  factory Implementation({
    required String name,
    required String version,
    String? title,
  }) => Implementation.fromMap({
    'name': name,
    'version': version,
    if (title != null) 'title': title,
  });

  String get version {
    final version = _value['version'] as String?;
    if (version == null) {
      throw ArgumentError('Missing version field in $Implementation.');
    }
    return version;
  }
}

@Deprecated('Use Implementation instead.')
typedef ClientImplementation = Implementation;

@Deprecated('Use Implementation instead.')
typedef ServerImplementation = Implementation;
