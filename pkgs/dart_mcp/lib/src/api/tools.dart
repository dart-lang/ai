// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// Sent from the client to request a list of tools the server has.
extension type ListToolsRequest.fromMap(Map<String, Object?> _value)
    implements PaginatedRequest {
  static const methodName = 'tools/list';

  factory ListToolsRequest({Cursor? cursor, MetaWithProgressToken? meta}) =>
      ListToolsRequest.fromMap({
        if (cursor != null) 'cursor': cursor,
        if (meta != null) '_meta': meta,
      });
}

/// The server's response to a tools/list request from the client.
extension type ListToolsResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListToolsResult({
    required List<Tool> tools,
    Cursor? cursor,
    Meta? meta,
  }) => ListToolsResult.fromMap({
    'tools': tools,
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });

  List<Tool> get tools => (_value['tools'] as List).cast<Tool>();
}

/// The server's response to a tool call.
///
/// Any errors that originate from the tool SHOULD be reported inside the result
/// object, with `isError` set to true, _not_ as an MCP protocol-level error
/// response. Otherwise, the LLM would not be able to see that an error occurred
/// and self-correct.
///
/// However, any errors in _finding_ the tool, an error indicating that the
/// server does not support tool calls, or any other exceptional conditions,
/// should be reported as an MCP error response.
extension type CallToolResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory CallToolResult({
    Meta? meta,
    required List<Content> content,
    bool? isError,
  }) => CallToolResult.fromMap({
    'content': content,
    if (isError != null) 'isError': isError,
    if (meta != null) '_meta': meta,
  });

  /// The type of content, either [TextContent], [ImageContent],
  /// or [EmbeddedResource],
  List<Content> get content => (_value['content'] as List).cast<Content>();

  /// Whether the tool call ended in an error.
  ///
  /// If not set, this is assumed to be false (the call was successful).
  bool? get isError => _value['isError'] as bool?;
}

/// Used by the client to invoke a tool provided by the server.
extension type CallToolRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'tools/call';

  factory CallToolRequest({
    required String name,
    Map<String, Object?>? arguments,
    MetaWithProgressToken? meta,
  }) => CallToolRequest._fromMap({
    'name': name,
    if (arguments != null) 'arguments': arguments,
    if (meta != null) '_meta': meta,
  });

  /// The name of the method to invoke.
  String get name => _value['name'] as String;

  /// The arguments to pass to the method.
  Map<String, Object?>? get arguments =>
      (_value['arguments'] as Map?)?.cast<String, Object?>();
}

/// An optional notification from the server to the client, informing it that
/// the list of tools it offers has changed.
///
/// This may be issued by servers without any previous subscription from the
/// client.
extension type ToolListChangedNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/tools/list_changed';

  factory ToolListChangedNotification({Meta? meta}) =>
      ToolListChangedNotification.fromMap({if (meta != null) '_meta': meta});
}

/// Definition for a tool the client can call.
extension type Tool.fromMap(Map<String, Object?> _value) {
  factory Tool({
    required String name,
    String? description,
    required ObjectSchema inputSchema,
  }) => Tool.fromMap({
    'name': name,
    if (description != null) 'description': description,
    'inputSchema': inputSchema,
  });

  /// The name of the tool.
  String get name => _value['name'] as String;

  /// A human-readable description of the tool.
  String? get description => _value['description'] as String?;

  /// A JSON [ObjectSchema] object defining the expected parameters for the
  /// tool.
  ObjectSchema get inputSchema => _value['inputSchema'] as ObjectSchema;
}

/// The valid types for properties in a JSON-RCP2 schema.
enum JsonType {
  object('object'),
  list('array'),
  string('string'),
  num('number'),
  int('integer'),
  bool('boolean'),
  nil('null');

  const JsonType(this.typeName);

  final String typeName;
}

/// A JSON Schema object defining the any kind of property.
///
/// See the subtypes [ObjectSchema], [ListSchema], [StringSchema],
/// [NumberSchema], [IntegerSchema], [BooleanSchema], [NullSchema].
///
/// To get an instance of a subtype, you should inspect the [type] as well as
/// check for any schema combinators ([allOf], [anyOf], [oneOf], [not]), as both
/// may be present.
///
/// If a [type] is provided, it applies to all sub-schemas, and you can cast all
/// the sub-schemas directly to the specified type from the parent schema.
///
/// See https://json-schema.org/understanding-json-schema/reference for the full
/// specification.
///
/// **Note:** Only a subset of the json schema spec is supported by these types,
/// if you need something more complex you can create your own
/// `Map<String, Object?>` and cast it to [Schema] (or [ObjectSchema]) directly.
extension type Schema.fromMap(Map<String, Object?> _value) {
  /// A combined schema, see
  /// https://json-schema.org/understanding-json-schema/reference/combining#schema-composition
  factory Schema.combined({
    JsonType? type,
    String? title,
    String? description,
    List<Schema>? allOf,
    List<Schema>? anyOf,
    List<Schema>? oneOf,
    List<Schema>? not,
  }) => Schema.fromMap({
    if (type != null) 'type': type.typeName,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (allOf != null) 'allOf': allOf,
    if (anyOf != null) 'anyOf': anyOf,
    if (oneOf != null) 'oneOf': oneOf,
    if (not != null) 'not': not,
  });

  /// Alias for [StringSchema.new].
  static const string = StringSchema.new;

  /// Alias for [BooleanSchema.new].
  static const bool = BooleanSchema.new;

  /// Alias for [NumberSchema.new].
  static const num = NumberSchema.new;

  /// Alias for [IntegerSchema.new].
  static const int = IntegerSchema.new;

  /// Alias for [ListSchema.new].
  static const list = ListSchema.new;

  /// Alias for [ObjectSchema.new].
  static const object = ObjectSchema.new;

  /// Alias for [NullSchema.new].
  static const nil = NullSchema.new;

  /// The [JsonType] of this schema, if present.
  ///
  /// Use this in switch statements to determine the type of schema and cast to
  /// the appropriate subtype.
  ///
  /// Note that it is good practice to include a default case, to avoid breakage
  /// in the case that a new type is added.
  ///
  /// This is not required, and commonly won't be present if one of the schema
  /// combinators ([allOf], [anyOf], [oneOf], or [not]) are used.
  JsonType? get type => JsonType.values.firstWhereOrNull(
    (t) => _value['type'] as String == t.typeName,
  );

  /// A title for this schema, should be short.
  String? get title => _value['title'] as String?;

  /// A description of this schema.
  String? get description => _value['description'] as String?;

  /// Schema combinator that requires all sub-schemas to match.
  List<Schema>? get allOf => (_value['allOf'] as List?)?.cast<Schema>();

  /// Schema combinator that requires at least one of the sub-schemas to match.
  List<Schema>? get anyOf => (_value['anyOf'] as List?)?.cast<Schema>();

  /// Schema combinator that requires exactly one of the sub-schemas to match.
  List<Schema>? get oneOf => (_value['oneOf'] as List?)?.cast<Schema>();

  /// Schema combinator that requires none of the sub-schemas to match.
  List<Schema>? get not => (_value['not'] as List?)?.cast<Schema>();
}

/// A JSON Schema definition for an object with properties.
extension type ObjectSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory ObjectSchema({
    String? title,
    String? description,
    Map<String, Schema>? properties,
    Map<String, Schema>? patternProperties,
    List<String>? required,

    /// Must be one of bool, Schema, or Null
    Object? additionalProperties,
    bool? unevaluatedProperties,
    StringSchema? propertyNames,
    int? minProperties,
    int? maxProperties,
  }) => ObjectSchema.fromMap({
    'type': JsonType.object.typeName,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (properties != null) 'properties': properties,
    if (patternProperties != null) 'patternProperties': patternProperties,
    if (required != null) 'required': required,
    if (additionalProperties != null)
      'additionalProperties': additionalProperties,
    if (unevaluatedProperties != null)
      'unevaluatedProperties': unevaluatedProperties,
    if (propertyNames != null) 'propertyNames': propertyNames,
    if (minProperties != null) 'minProperties': minProperties,
    if (maxProperties != null) 'maxProperties': maxProperties,
  });

  /// A map of the properties of the object to the nested [Schema]s for those
  /// properties.
  Map<String, Schema>? get properties =>
      (_value['properties'] as Map?)?.cast<String, Schema>();

  /// A map of the property patterns of the object to the nested [Schema]s for
  /// those properties.
  Map<String, Schema>? get patternProperties =>
      (_value['patternProperties'] as Map?)?.cast<String, Schema>();

  /// A list of the required properties by name.
  List<String>? get required => (_value['required'] as List?)?.cast<String>();

  /// Rules for additional properties that don't match the
  /// [properties] or [patternProperties] schemas.
  ///
  /// Can be either a [bool] or a [Schema], if it is a [Schema] then additional
  /// properties should match that [Schema].
  /*bool|Schema|Null*/
  Object? get additionalProperties => _value['additionalProperties'];

  /// Similar to [additionalProperties] but more flexible, see
  /// https://json-schema.org/understanding-json-schema/reference/object#unevaluatedproperties
  bool? get unevaluatedProperties => _value['unevaluatedProperties'] as bool?;

  /// A list of valid patterns for all property names.
  StringSchema? get propertyNames =>
      (_value['propertyNames'] as Map?)?.cast<String, Object?>()
          as StringSchema?;

  /// The minimum number of properties in this object.
  int? get minProperties => _value['minProperties'] as int?;

  /// The maximum number of properties in this object.
  int? get maxProperties => _value['maxProperties'] as int?;
}

/// A JSON Schema definition for a String.
extension type const StringSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory StringSchema({
    String? title,
    String? description,
    int? minLength,
    int? maxLength,
    String? pattern,
  }) => StringSchema.fromMap({
    'type': JsonType.string.typeName,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (minLength != null) 'minLength': minLength,
    if (maxLength != null) 'maxLength': maxLength,
    if (pattern != null) 'pattern': pattern,
  });

  /// The minimum allowed length of this String.
  int? get minLength => _value['minLength'] as int?;

  /// The maximum allowed length of this String.
  int? get maxLength => _value['maxLength'] as int?;

  /// A regular expression pattern that the String must match.
  String? get pattern => _value['pattern'] as String?;
}

/// A JSON Schema definition for a [num].
extension type NumberSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory NumberSchema({
    String? title,
    String? description,
    num? minimum,
    num? maximum,
    num? exclusiveMinimum,
    num? exclusiveMaximum,
    num? multipleOf,
  }) => NumberSchema.fromMap({
    'type': JsonType.num.typeName,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
    if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
    if (multipleOf != null) 'multipleOf': multipleOf,
  });

  /// The minimum value (inclusive) for this number.
  num? get minimum => _value['minimum'] as num?;

  /// The maximum value (inclusive) for this number.
  num? get maximum => _value['maximum'] as num?;

  /// The minimum value (exclusive) for this number.
  num? get exclusiveMinimum => _value['exclusiveMinimum'] as num?;

  /// The maximum value (exclusive) for this number.
  num? get exclusiveMaximum => _value['exclusiveMaximum'] as num?;

  /// The value must be a multiple of this number.
  num? get multipleOf => _value['multipleOf'] as num?;
}

/// A JSON Schema definition for an [int].
extension type IntegerSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory IntegerSchema({
    String? title,
    String? description,
    int? minimum,
    int? maximum,
    int? exclusiveMinimum,
    int? exclusiveMaximum,
    num? multipleOf,
  }) => IntegerSchema.fromMap({
    'type': JsonType.int.typeName,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
    if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
    if (multipleOf != null) 'multipleOf': multipleOf,
  });

  /// The minimum value (inclusive) for this integer.
  int? get minimum => _value['minimum'] as int?;

  /// The maximum value (inclusive) for this integer.
  int? get maximum => _value['maximum'] as int?;

  /// The minimum value (exclusive) for this integer.
  int? get exclusiveMinimum => _value['exclusiveMinimum'] as int?;

  /// The maximum value (exclusive) for this integer.
  int? get exclusiveMaximum => _value['exclusiveMaximum'] as int?;

  /// The value must be a multiple of this number.
  num? get multipleOf => _value['multipleOf'] as num?;
}

/// A JSON Schema definition for a [bool].
extension type BooleanSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory BooleanSchema({String? title, String? description}) =>
      BooleanSchema.fromMap({
        'type': JsonType.bool.typeName,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      });
}

/// A JSON Schema definition for `null`.
extension type NullSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory NullSchema({String? title, String? description}) =>
      NullSchema.fromMap({
        'type': JsonType.nil.typeName,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      });
}

/// A JSON Schema definition for a [List].
extension type ListSchema.fromMap(Map<String, Object?> _value)
    implements Schema {
  factory ListSchema({
    String? title,
    String? description,
    Schema? items,
    List<Schema>? prefixItems,
    bool? unevaluatedItems,
    int? minItems,
    int? maxItems,
    bool? uniqueItems,
  }) => ListSchema.fromMap({
    'type': JsonType.list.typeName,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (items != null) 'items': items,
    if (prefixItems != null) 'prefixItems': prefixItems,
    if (unevaluatedItems != null) 'unevaluatedItems': unevaluatedItems,
    if (minItems != null) 'minItems': minItems,
    if (maxItems != null) 'maxItems': maxItems,
    if (uniqueItems != null) 'uniqueItems': uniqueItems,
  });

  /// The schema for all the items in this list, or all those after
  /// [prefixItems] (if present).
  Schema? get items => _value['items'] as Schema?;

  /// The schema for the initial items in this list, if specified.
  List<Schema>? get prefixItems =>
      (_value['prefixItems'] as List?)?.cast<Schema>();

  /// Whether or not  additional items in the list are allowed that don't
  /// match the [items] or [prefixItems] schemas.
  bool? get unevaluatedItems => _value['unevaluatedItems'] as bool?;

  /// The minimum number of items in this list.
  int? get minItems => _value['minItems'] as int?;

  /// The maximum number of items in this list.
  int? get maxItems => _value['maxItems'] as int?;

  /// Whether or not all the items in this list must be unique.
  bool? get uniqueItems => _value['uniqueItems'] as bool?;
}
