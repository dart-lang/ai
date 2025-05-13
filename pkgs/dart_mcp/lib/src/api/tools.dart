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
    Cursor? nextCursor,
    Meta? meta,
  }) => ListToolsResult.fromMap({
    'tools': tools,
    if (nextCursor != null) 'nextCursor': nextCursor,
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
    // Only supported since version `ProtocolVersion.v2025_03_26`.
    ToolAnnotations? annotations,
  }) => Tool.fromMap({
    'name': name,
    if (description != null) 'description': description,
    'inputSchema': inputSchema,
    if (annotations != null) 'annotations': annotations,
  });

  /// Optional additional tool information.
  ///
  /// Only supported since version [ProtocolVersion.v2025_03_26].
  ToolAnnotations? get toolAnnotations =>
      (_value['annotations'] as Map?)?.cast<String, Object?>()
          as ToolAnnotations?;

  /// The name of the tool.
  String get name => _value['name'] as String;

  /// A human-readable description of the tool.
  String? get description => _value['description'] as String?;

  /// A JSON [ObjectSchema] object defining the expected parameters for the
  /// tool.
  ObjectSchema get inputSchema => _value['inputSchema'] as ObjectSchema;
}

/// Additional properties describing a Tool to clients.
///
/// NOTE: all properties in ToolAnnotations are **hints**. They are not
/// guaranteed to provide a faithful description of tool behavior (including
/// descriptive properties like `title`).
///
/// Clients should never make tool use decisions based on ToolAnnotations
/// received from untrusted servers.
extension type ToolAnnotations.fromMap(Map<String, Object?> _value) {
  factory ToolAnnotations({
    bool? destructiveHint,
    bool? idempotentHint,
    bool? openWorldHint,
    bool? readOnlyHint,
    String? title,
  }) => ToolAnnotations.fromMap({
    if (destructiveHint != null) 'destructiveHint': destructiveHint,
    if (idempotentHint != null) 'idempotentHint': idempotentHint,
    if (openWorldHint != null) 'openWorldHint': openWorldHint,
    if (readOnlyHint != null) 'readOnlyHint': readOnlyHint,
    if (title != null) 'title': title,
  });

  /// If true, the tool may perform destructive updates to its environment.
  ///
  /// If false, the tool performs only additive updates.
  ///
  /// (This property is meaningful only when `readOnlyHint == false`)
  bool? get destructiveHint => _value['destructiveHint'] as bool?;

  /// If true, calling the tool repeatedly with the same arguments will have no
  /// additional effect on the its environment.
  ///
  /// (This property is meaningful only when `readOnlyHint == false`)
  bool? get idempotentHint => _value['idempotentHint'] as bool?;

  /// If true, this tool may interact with an "open world" of external entities.
  ///
  /// If false, the tool's domain of interaction is closed. For example, the
  /// world of a web search tool is open, whereas that of a memory tool is not.
  bool? get openWorldHint => _value['openWorldHint'] as bool?;

  /// If true, the tool does not modify its environment.
  bool? get readOnlyHint => _value['readOnlyHint'] as bool?;

  /// A human-readable title for the tool.
  String? get title => _value['title'] as String?;
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

/// Enum representing the types of validation failures when checking data
/// against a schema.
enum ValidationErrorType {
  // General
  typeMismatch,

  // Schema combinators
  allOfNotMet,
  anyOfNotMet,
  oneOfNotMet,
  notConditionViolated,

  // Object specific
  requiredPropertyMissing,
  additionalPropertyNotAllowed,
  minPropertiesNotMet,
  maxPropertiesExceeded,
  propertyNamesInvalid,
  propertyValueInvalid,
  patternPropertyValueInvalid,
  unevaluatedPropertyNotAllowed,

  // Array/List specific
  minItemsNotMet,
  maxItemsExceeded,
  uniqueItemsViolated,
  itemInvalid,
  prefixItemInvalid,
  unevaluatedItemNotAllowed,

  // String specific
  minLengthNotMet,
  maxLengthExceeded,
  patternMismatch,

  // Number/Integer specific
  minimumNotMet,
  maximumExceeded,
  exclusiveMinimumNotMet,
  exclusiveMaximumExceeded,
  multipleOfInvalid,
}

/// A validation error with detailed information about the location of the
/// error.
extension type ValidationError.fromMap(Map<String, Object?> _value) {
  factory ValidationError(
    ValidationErrorType error, {
    List<String>? path,
    Object? object,
    String? details,
  }) => ValidationError.fromMap({
    'error': error,
    if (path != null) 'path': path,
    if (object != null) 'object': object,
    if (details != null) 'details': details,
  });

  /// The type of validation error that occurred.
  ValidationErrorType? get error => _value['error'] as ValidationErrorType?;

  /// The path to the object that had the error.
  List<String>? get path => _value['path'] as List<String>?;

  /// The object that failed validation located at [path].
  Object? get object => _value['object'];

  /// Additional details about the error (optional).
  String? get details => _value['details'] as String?;
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
    (t) => (_value['type'] as String? ?? '') == t.typeName,
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

  /// Validates the given [data] against this schema.
  ///
  /// Returns a list of [ValidationError] if validation fails,
  /// or an empty list if validation succeeds.
  List<ValidationError> validate(Object? data) {
    return _validateSchema(this, data);
  }
}

// These have to be external to the Schema extension because of clashes with
// type-named members like bool, int, and num.
List<ValidationError> _validateSchema(Schema schema, Object? data) {
  final failures = <ValidationError>[];

  // 1. Handle schema combinators
  if (schema.allOf != null) {
    var currentAllOfValid = true;
    final allOfDetailedFailures = <ValidationError>[];
    for (final subSchema in schema.allOf!) {
      final subFailures = _validateSchema(subSchema, data);
      if (subFailures.isNotEmpty) {
        currentAllOfValid = false;
        allOfDetailedFailures.addAll(subFailures);
      }
    }
    if (!currentAllOfValid) {
      failures.add(ValidationError(ValidationErrorType.allOfNotMet));
      failures.addAll(allOfDetailedFailures);
    }
  }
  if (schema.anyOf != null) {
    var oneValid = false;
    for (final subSchema in schema.anyOf!) {
      if (_validateSchema(subSchema, data).isEmpty) {
        oneValid = true;
        break;
      }
    }
    if (!oneValid) {
      failures.add(ValidationError(ValidationErrorType.anyOfNotMet));
    }
  }
  if (schema.oneOf != null) {
    var validCount = 0;
    for (final subSchema in schema.oneOf!) {
      if (_validateSchema(subSchema, data).isEmpty) {
        validCount++;
      }
    }
    if (validCount != 1) {
      failures.add(ValidationError(ValidationErrorType.oneOfNotMet));
    }
  }
  if (schema.not != null) {
    var validCount = 0;
    for (final subSchema in schema.not!) {
      if (_validateSchema(subSchema, data).isEmpty) {
        validCount++;
      }
    }
    if (validCount == 1) {
      failures.add(ValidationError(ValidationErrorType.notConditionViolated));
    }
  }

  // 2. Handle explicit type validation if schema.type is present
  final schemaType = schema.type;
  if (schemaType != null) {
    switch (schemaType) {
      case JsonType.object:
        if (data is Map<String, Object?>) {
          failures.addAll(_validateObject(schema as ObjectSchema, data));
        } else if (data != null) {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
      case JsonType.list:
        if (data is List) {
          failures.addAll(_validateList(schema as ListSchema, data));
        } else {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
      case JsonType.string:
        if (data is String) {
          failures.addAll(_validateString(schema as StringSchema, data));
        } else {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
      case JsonType.num:
        if (data is num) {
          failures.addAll(_validateNumber(schema as NumberSchema, data));
        } else {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
      case JsonType.int:
        if (data is int) {
          failures.addAll(_validateInteger(schema as IntegerSchema, data));
        } else if (data is num && data == data.toInt()) {
          failures.addAll(
            _validateInteger(schema as IntegerSchema, data.toInt()),
          );
        } else {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
      case JsonType.bool:
        if (data is! bool) {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
      case JsonType.nil:
        if (data != null) {
          failures.add(ValidationError(ValidationErrorType.typeMismatch));
        }
    }
  }

  return failures.toSet().toList(); // Remove duplicates
}

List<ValidationError> _validateObject(
  ObjectSchema schema,
  Map<String, Object?> data,
) {
  final failures = <ValidationError>[];

  if (schema.minProperties != null &&
      data.keys.length < schema.minProperties!) {
    failures.add(ValidationError(ValidationErrorType.minPropertiesNotMet));
  }
  if (schema.maxProperties != null &&
      data.keys.length > schema.maxProperties!) {
    failures.add(ValidationError(ValidationErrorType.maxPropertiesExceeded));
  }

  for (final reqProp in schema.required ?? const []) {
    if (!data.containsKey(reqProp)) {
      failures.add(
        ValidationError(ValidationErrorType.requiredPropertyMissing),
      );
    }
  }

  final evaluatedKeys = <String>{};
  if (schema.properties != null) {
    for (final entry in schema.properties!.entries) {
      if (data.containsKey(entry.key)) {
        evaluatedKeys.add(entry.key);
        failures.addAll(
          _validateSchema(entry.value, data[entry.key]).map(
            (e) => ValidationError(
              ValidationErrorType.propertyValueInvalid,
              details: e.details,
            ),
          ),
        );
      }
    }
  }
  if (schema.patternProperties != null) {
    for (final entry in schema.patternProperties!.entries) {
      final pattern = RegExp(entry.key);
      for (final dataKey in data.keys) {
        if (pattern.hasMatch(dataKey)) {
          evaluatedKeys.add(dataKey);
          failures.addAll(
            _validateSchema(entry.value, data[dataKey]).map(
              (e) => ValidationError(
                ValidationErrorType.patternPropertyValueInvalid,
                details: e.details,
              ),
            ),
          );
        }
      }
    }
  }
  if (schema.propertyNames != null) {
    for (final key in data.keys) {
      final keyFailures = _validateSchema(schema.propertyNames!, key);
      if (keyFailures.isNotEmpty) {
        failures.addAll(keyFailures);
        failures.add(ValidationError(ValidationErrorType.propertyNamesInvalid));
      }
    }
  }

  for (final dataKey in data.keys) {
    if (evaluatedKeys.contains(dataKey)) continue;

    var allowed = true;
    if (schema.additionalProperties != null) {
      final ap = schema.additionalProperties;
      if (ap is bool && !ap) {
        allowed = false;
      } else if (ap is Schema &&
          _validateSchema(ap, data[dataKey]).isNotEmpty) {
        allowed = false;
      }
      if (!allowed) {
        failures.add(
          ValidationError(ValidationErrorType.additionalPropertyNotAllowed),
        );
      }
    } else if (schema.unevaluatedProperties == false) {
      // Only applies if additionalProperties is not defined
      failures.add(
        ValidationError(ValidationErrorType.unevaluatedPropertyNotAllowed),
      );
    }
  }
  return failures;
}

List<ValidationError> _validateList(ListSchema schema, List<dynamic> data) {
  final failures = <ValidationError>[];

  if (schema.minItems != null && data.length < schema.minItems!) {
    failures.add(ValidationError(ValidationErrorType.minItemsNotMet));
  }

  if (schema.maxItems != null && data.length > schema.maxItems!) {
    failures.add(ValidationError(ValidationErrorType.maxItemsExceeded));
  }

  if (schema.uniqueItems == true && data.toSet().length != data.length) {
    failures.add(ValidationError(ValidationErrorType.uniqueItemsViolated));
  }

  final evaluatedItems = List<bool>.filled(data.length, false);
  if (schema.prefixItems != null) {
    for (var i = 0; i < schema.prefixItems!.length && i < data.length; i++) {
      evaluatedItems[i] = true;
      if (_validateSchema(schema.prefixItems![i], data[i]).isNotEmpty) {
        failures.add(ValidationError(ValidationErrorType.prefixItemInvalid));
      }
    }
  }
  if (schema.items != null) {
    final startIndex = schema.prefixItems?.length ?? 0;
    for (var i = startIndex; i < data.length; i++) {
      evaluatedItems[i] = true;
      if (_validateSchema(schema.items!, data[i]).isNotEmpty) {
        failures.add(ValidationError(ValidationErrorType.itemInvalid));
      }
    }
  }
  if (schema.unevaluatedItems == false) {
    for (var i = 0; i < data.length; i++) {
      if (!evaluatedItems[i]) {
        failures.add(
          ValidationError(ValidationErrorType.unevaluatedItemNotAllowed),
        );
        // Only report the first unevaluated item to avoid excessive errors.
        return failures;
      }
    }
  }
  return failures;
}

List<ValidationError> _validateString(StringSchema schema, String data) {
  final failures = <ValidationError>[];
  if (schema.minLength != null && data.length < schema.minLength!) {
    failures.add(ValidationError(ValidationErrorType.minLengthNotMet));
  }
  if (schema.maxLength != null && data.length > schema.maxLength!) {
    failures.add(ValidationError(ValidationErrorType.maxLengthExceeded));
  }
  if (schema.pattern != null && !RegExp(schema.pattern!).hasMatch(data)) {
    failures.add(ValidationError(ValidationErrorType.patternMismatch));
  }
  return failures;
}

List<ValidationError> _validateNumber(NumberSchema schema, num data) {
  final failures = <ValidationError>[];
  if (schema.minimum != null && data < schema.minimum!) {
    failures.add(ValidationError(ValidationErrorType.minimumNotMet));
  }
  if (schema.maximum != null && data > schema.maximum!) {
    failures.add(ValidationError(ValidationErrorType.maximumExceeded));
  }
  if (schema.exclusiveMinimum != null && data <= schema.exclusiveMinimum!) {
    failures.add(ValidationError(ValidationErrorType.exclusiveMinimumNotMet));
  }
  if (schema.exclusiveMaximum != null && data >= schema.exclusiveMaximum!) {
    failures.add(ValidationError(ValidationErrorType.exclusiveMaximumExceeded));
  }
  if (schema.multipleOf != null && schema.multipleOf! != 0) {
    final remainder = data / schema.multipleOf!;
    if ((remainder - remainder.round()).abs() > 1e-9) {
      failures.add(ValidationError(ValidationErrorType.multipleOfInvalid));
    }
  }
  return failures;
}

List<ValidationError> _validateInteger(IntegerSchema schema, int data) {
  final failures = <ValidationError>[];
  if (schema.minimum != null && data < schema.minimum!) {
    failures.add(ValidationError(ValidationErrorType.minimumNotMet));
  }
  if (schema.maximum != null && data > schema.maximum!) {
    failures.add(ValidationError(ValidationErrorType.maximumExceeded));
  }
  if (schema.exclusiveMinimum != null && data <= schema.exclusiveMinimum!) {
    failures.add(ValidationError(ValidationErrorType.exclusiveMinimumNotMet));
  }
  if (schema.exclusiveMaximum != null && data >= schema.exclusiveMaximum!) {
    failures.add(ValidationError(ValidationErrorType.exclusiveMaximumExceeded));
  }
  if (schema.multipleOf != null && (data % schema.multipleOf! != 0)) {
    failures.add(ValidationError(ValidationErrorType.multipleOfInvalid));
  }
  return failures;
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
