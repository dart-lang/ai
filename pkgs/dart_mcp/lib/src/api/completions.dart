// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Note that all features here are only supported since version
/// [ProtocolVersion.v2025_03_26].
part of 'api.dart';

/// A request from the client to the server, to ask for completion options.
extension type CompleteRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'completion/complete';

  factory CompleteRequest({
    required Reference ref,
    required CompletionArgument argument,
    CompletionContext? context,
    MetaWithProgressToken? meta,
  }) => CompleteRequest.fromMap({
    Keys.ref: ref,
    Keys.argument: argument,
    if (context != null) Keys.context: context,
    if (meta != null) Keys.meta: meta,
  });

  /// A reference to the thing to complete.
  ///
  /// See the [PromptReference] and [ResourceTemplateReference] types.
  ///
  /// In the case of a [ResourceTemplateReference], it must refer to a
  /// [ResourceTemplate].
  Reference get ref {
    final ref = _value[Keys.ref] as Reference?;
    if (ref == null) {
      throw ArgumentError('Missing ref field in $CompleteRequest.');
    }
    return ref;
  }

  /// The argument's information.
  CompletionArgument get argument {
    final argument = _value[Keys.argument] as CompletionArgument?;
    if (argument == null) {
      throw ArgumentError('Missing argument field in $CompleteRequest.');
    }
    return argument;
  }

  /// Additional, optional context for completions.
  CompletionContext? get context => _value[Keys.context] as CompletionContext?;
}

/// The server's response to a completion/complete request
extension type CompleteResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory CompleteResult({required Completion completion, Meta? meta}) =>
      CompleteResult.fromMap({
        Keys.completion: completion,
        if (meta != null) Keys.meta: meta,
      });

  /// The actual completion.
  Completion get completion =>
      (_value[Keys.completion] as Map).cast<String, Object?>() as Completion;
}

/// An individual completion from a [CompleteResult].
extension type Completion.fromMap(Map<String, Object?> _value) {
  factory Completion({
    required List<String> values,
    int? total,
    bool? hasMore,
    Meta? meta,
  }) {
    assert(
      values.length <= 100,
      'no more than 100 completion values should be given',
    );
    return Completion.fromMap({
      Keys.values: values,
      if (total != null) Keys.total: total,
      if (hasMore != null) Keys.hasMore: hasMore,
    });
  }

  /// A list of completion values.
  ///
  /// Must not exceed 100 items.
  List<String> get values => (_value[Keys.values] as List).cast<String>();

  /// The total number of completion options available.
  ///
  /// This can exceed the number of values actually sent in the response.
  int? get total => _value[Keys.total] as int?;

  /// Indicates whether there are additional completion options beyond those
  /// provided in the current response, even if the exact total is unknown.
  bool? get hasMore => _value[Keys.hasMore] as bool?;
}

/// An argument passed to a [CompleteRequest].
extension type CompletionArgument.fromMap(Map<String, Object?> _value) {
  factory CompletionArgument({required String name, required String value}) =>
      CompletionArgument.fromMap({Keys.name: name, Keys.value: value});

  /// The name of the argument.
  String get name => _value[Keys.name] as String;

  /// The value of the argument to use for completion matching.
  String get value => _value[Keys.value] as String;
}

/// A context passed to a [CompleteRequest].
extension type CompletionContext.fromMap(Map<String, Object?> _value) {
  factory CompletionContext({Map<String, String>? arguments}) =>
      CompletionContext.fromMap({Keys.arguments: arguments});

  /// Previously-resolved variables in a URI template or prompt.
  Map<String, String>? get arguments =>
      (_value[Keys.arguments] as Map?)?.cast<String, String>();
}

/// Union type for references, see [PromptReference] and
/// [ResourceTemplateReference].
extension type Reference._(Map<String, Object?> _value) {
  factory Reference.fromMap(Map<String, Object?> value) {
    assert(value.containsKey(Keys.type));
    return Reference._(value);
  }

  /// Whether or not this is a [PromptReference].
  bool get isPrompt => _value[Keys.type] == PromptReference.expectedType;

  /// Whether or not this is a [ResourceTemplateReference].
  bool get isResource =>
      _value[Keys.type] == ResourceTemplateReference.expectedType;

  /// The type of reference.
  ///
  /// You can use this in a switch to handle the various types (see the static
  /// `expectedType` getters), or you can use [isPrompt] and [isResource] to
  /// determine the type and then do the cast.
  String get type => _value[Keys.type] as String;
}

/// A reference to a resource or resource template definition.
extension type ResourceTemplateReference.fromMap(Map<String, Object?> _value)
    implements Reference {
  static const expectedType = 'ref/resource';

  factory ResourceTemplateReference({required String uri}) =>
      ResourceTemplateReference.fromMap({
        Keys.uri: uri,
        Keys.type: expectedType,
      });

  /// This should always be [expectedType].
  ///
  /// This has a [type] because it exists as a part of a union type, so this
  /// distinguishes it from other types.
  String get type {
    final type = _value[Keys.type] as String;
    assert(type == expectedType);
    return type;
  }

  /// The URI or URI template of the resource.
  String get uri => _value[Keys.uri] as String;
}

@Deprecated('Use ResourceTemplateReference instead')
typedef ResourceReference = ResourceTemplateReference;

/// Identifies a prompt.
extension type PromptReference.fromMap(Map<String, Object?> _value)
    implements Reference, BaseMetadata {
  static const expectedType = 'ref/prompt';

  factory PromptReference({required String name, String? title}) =>
      PromptReference.fromMap({
        Keys.name: name,
        Keys.title: title,
        Keys.type: expectedType,
      });

  /// This should always be [expectedType].
  ///
  /// This has a [type] because it exists as a part of a union type, so this
  /// distinguishes it from other types.
  String get type {
    final type = _value[Keys.type] as String;
    assert(type == expectedType);
    return type;
  }
}
