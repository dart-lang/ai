// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// A request from the client to the server, to ask for completion options.
extension type CompleteRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'completion/complete';

  factory CompleteRequest({
    required PromptReference ref,
    required String argumentName,
    required String argumentValue,
    MetaWithProgressToken? meta,
  }) => CompleteRequest.fromMap({
    'ref': ref,
    'argument': {'name': argumentName, 'value': argumentValue},
    if (meta != null) '_meta': meta,
  });

  PromptReference get ref => _value['ref'] as PromptReference;

  Map<String, Object?> get argument =>
      (_value['argument'] as Map).cast<String, Object?>();
}

/// The server's response to a completion/complete request
extension type CompleteResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory CompleteResult({
    required List<String> values,
    int? total,
    bool? hasMore,
    Meta? meta,
  }) => CompleteResult.fromMap({
    'completion': {
      'values': values,
      if (total != null) 'total': total,
      if (hasMore != null) 'hasMore': hasMore,
    },
    if (meta != null) '_meta': meta,
  });

  Map<String, Object?> get completion =>
      (_value['completion'] as Map).cast<String, Object?>();
}

// /**
//  * The server's response to a completion/complete request
//  */
// export interface CompleteResult extends Result {
//   completion: {
//     /**
//      * An array of completion values. Must not exceed 100 items.
//      */
//     values: string[];
//     /**
//      * The total number of completion options available. This can exceed the
//      * number of values actually sent in the response.
//      */
//     total?: number;
//     /**
//      * Indicates whether there are additional completion options beyond those
//      * provided in the current response, even if the exact total is unknown.
//      */
//     hasMore?: boolean;
//   };
// }

/// Union type for references, see [PromptReference] and [ResourceReference].
extension type Reference._(Map<String, Object?> _value) {
  factory Reference.fromMap(Map<String, Object?> value) {
    assert(value.containsKey('type'));
    return Reference._(value);
  }

  /// Whether or not this is a [PromptReference].
  bool get isPrompt => _value['type'] == PromptReference.expectedType;

  /// Whether or not this is a [ResourceReference].
  bool get isResource => _value['type'] == ResourceReference.expectedType;

  /// The type of reference.
  ///
  /// You can use this in a switch to handle the various types (see the static
  /// `expectedType` getters), or you can use [isPrompt] and [isResource] to
  /// determine the type and then do the cast.
  String get type => _value['type'] as String;
}

/// A reference to a resource or resource template definition.
extension type ResourceReference.fromMap(Map<String, Object?> _value)
    implements Reference {
  static const expectedType = 'ref/resource';

  factory ResourceReference({required String uri}) =>
      ResourceReference.fromMap({'uri': uri, 'type': expectedType});

  /// This should always be [expectedType].
  ///
  /// This has a [type] because it exists as a part of a union type, so this
  /// distinguishes it from other types.
  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The URI or URI template of the resource.
  String get uri => _value['uri'] as String;
}

/// Identifies a prompt.
extension type PromptReference.fromMap(Map<String, Object?> _value)
    implements Reference {
  static const expectedType = 'ref/prompt';

  factory PromptReference({required String name}) =>
      PromptReference.fromMap({'name': name, 'type': expectedType});

  /// This should always be [expectedType].
  ///
  /// This has a [type] because it exists as a part of a union type, so this
  /// distinguishes it from other types.
  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The name of the prompt or prompt template
  String get name => _value['name'] as String;
}
