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
  String get name {
    final name = _value['name'] as String?;
    if (name == null) {
      throw ArgumentError('Missing name field in $CallToolRequest');
    }
    return name;
  }

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
    String? details,
  }) => ValidationError.fromMap({
    'error': error.name,
    if (path != null) 'path': path.toList(),
    if (details != null) 'details': details,
  });

  /// The type of validation error that occurred.
  ValidationErrorType? get error => ValidationErrorType.values.firstWhereOrNull(
    (t) => t.name == _value['error'],
  );

  /// The path to the object that had the error.
  List<String>? get path => (_value['path'] as List?)?.cast<String>();

  /// Additional details about the error (optional).
  String? get details => _value['details'] as String?;

  String toErrorString() {
    return '${error!.name} in object at '
        '${path!.map((p) => '[$p]').join('')}'
        '${details != null ? ' - $details' : ''}';
  }
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
}

extension SchemaValidation on Schema {
  /// Validates the given [data] against this schema.
  ///
  /// Returns a list of [ValidationError] if validation fails,
  /// or an empty list if validation succeeds.
  List<ValidationError> validate(Object? data) {
    final failures = _createHashSet();
    _validateSchema(data, [], failures);

    return failures.toList();
  }

  /// Performs validation based on the direct, non-combinator keywords of this
  /// schema.
  ///
  /// Adds failures to [accumulatedFailures] and returns `false` if any occur.
  bool _performDirectValidation(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    var isValid = true;
    if (type case final schemaType?) {
      switch (schemaType) {
        case JsonType.object:
          isValid = (this as ObjectSchema)._validateObject(
            data,
            currentPath,
            accumulatedFailures,
          );
        case JsonType.list:
          isValid = (this as ListSchema)._validateList(
            data,
            currentPath,
            accumulatedFailures,
          );
        case JsonType.string:
          isValid = (this as StringSchema)._validateString(
            data,
            currentPath,
            accumulatedFailures,
          );
        case JsonType.num:
          isValid = (this as NumberSchema)._validateNumber(
            data,
            currentPath,
            accumulatedFailures,
          );
        case JsonType.int:
          isValid = (this as IntegerSchema)._validateInteger(
            data,
            currentPath,
            accumulatedFailures,
          );
        case JsonType.bool:
          if (data is! bool) {
            isValid = false;
            accumulatedFailures.add(
              ValidationError(
                ValidationErrorType.typeMismatch,
                path: currentPath,
              ),
            );
          }
        case JsonType.nil:
          if (data != null) {
            isValid = false;
            accumulatedFailures.add(
              ValidationError(
                ValidationErrorType.typeMismatch,
                path: currentPath,
              ),
            );
          }
      }
    }
    return isValid;
  }

  /// Validates data against the schema.
  ///
  /// Adds failures to [accumulatedFailures] and returns `false` if any occur.
  bool _validateSchema(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    var isValid = true;

    // Validate data against the non-combinator keywords of the current schema
    // ('this').
    if (!_performDirectValidation(data, currentPath, accumulatedFailures)) {
      isValid = false;
    }

    // Handle combinator keywords. Create the "base schema" from 'this' schema,
    // excluding combinator keywords. This base schema's constraints are
    // effectively ANDed with each sub-schema in combinators.
    final baseSchemaMapForCombinators = Map<String, Object?>.from(_value);
    baseSchemaMapForCombinators.remove('allOf');
    baseSchemaMapForCombinators.remove('anyOf');
    baseSchemaMapForCombinators.remove('oneOf');
    baseSchemaMapForCombinators.remove('not');
    final baseSchemaForCombinators = Schema.fromMap(
      baseSchemaMapForCombinators,
    );

    // Helper to merge a sub-schema with the baseSchemaForCombinators.
    Schema mergeWithBase(Schema subSchema) {
      final mergedMap = Map<String, Object?>.from(
        baseSchemaForCombinators._value,
      );
      // Sub-schema's values override base's if keys conflict. This is generally
      // correct; if sub-schema specifies a conflicting 'type', the merged
      // schema will use sub-schema's type, and validation will proceed. If this
      // makes the schema unsatisfiable with base constraints, validation will
      // fail.
      mergedMap.addAll(subSchema._value);
      return Schema.fromMap(mergedMap);
    }

    if (allOf case final allOfList?) {
      var allSubSchemasAreValid = true;
      final allOfDetailedSubFailures = <ValidationError>[];

      for (final subSchemaMember in allOfList) {
        final effectiveSubSchema = mergeWithBase(subSchemaMember);
        final currentSubSchemaFailures = _createHashSet();
        if (!effectiveSubSchema._validateSchema(
          data,
          currentPath,
          currentSubSchemaFailures,
        )) {
          allSubSchemasAreValid = false;
          allOfDetailedSubFailures.addAll(currentSubSchemaFailures);
        }
      }
      // `allOf` fails if any effective sub-schema (Base AND SubMember) failed.
      if (!allSubSchemasAreValid) {
        isValid = false;
        accumulatedFailures.add(
          ValidationError(ValidationErrorType.allOfNotMet, path: currentPath),
        );
        accumulatedFailures.addAll(allOfDetailedSubFailures);
      }
    }
    if (anyOf case final anyOfList?) {
      var oneSubSchemaPassed = false;
      anyOfList.any((element) {
        final effectiveSubSchema = mergeWithBase(element);
        if (effectiveSubSchema._validateSchema(
          data,
          currentPath,
          _createHashSet(),
        )) {
          oneSubSchemaPassed = true;
          return true;
        }
        return false;
      });
      if (!oneSubSchemaPassed) {
        isValid = false;
        accumulatedFailures.add(
          ValidationError(ValidationErrorType.anyOfNotMet, path: currentPath),
        );
      }
    }
    if (oneOf case final oneOfList?) {
      var matchingSubSchemaCount = 0;
      for (final subSchemaMember in oneOfList) {
        final effectiveSubSchema = mergeWithBase(subSchemaMember);
        if (effectiveSubSchema._validateSchema(
          data,
          currentPath,
          _createHashSet(),
        )) {
          matchingSubSchemaCount++;
        }
      }
      if (matchingSubSchemaCount != 1) {
        isValid = false;
        accumulatedFailures.add(
          ValidationError(ValidationErrorType.oneOfNotMet, path: currentPath),
        );
      }
    }
    if (not case final notList?) {
      final notConditionViolatedBySubSchema = notList.any((subSchemaInNot) {
        final effectiveSubSchemaForNot = mergeWithBase(subSchemaInNot);
        // 'not' is violated if data *validates* against the (Base AND
        // NotSubSchema).
        return effectiveSubSchemaForNot._validateSchema(
          data,
          currentPath,
          _createHashSet(),
        );
      });

      if (notConditionViolatedBySubSchema) {
        isValid = false;
        accumulatedFailures.add(
          ValidationError(
            ValidationErrorType.notConditionViolated,
            path: currentPath,
          ),
        );
      }
    }

    return isValid;
  }
}

/// A JSON Schema definition for an object with properties.
///
/// `ObjectSchema` is used to define the expected structure, data types, and
/// constraints for MCP argument objects. It allows you to specify:
///
/// - Which properties an object can or must have ([properties], [required]).
/// - The schema for each of those properties (e.g., string, number, nested
///   object).
/// - Whether additional properties not explicitly defined are allowed
///   ([additionalProperties], [unevaluatedProperties]).
/// - Constraints on the number of properties ([minProperties],
///   [maxProperties]).
/// - Constraints on property names ([propertyNames]).
///
/// See https://json-schema.org/understanding-json-schema/reference/object.html
/// for more details on object schemas.
///
/// Example:
///
/// To define a schema for a product object that requires `productId` and
/// `productName`, has an optional `price` (non-negative number) and optional
/// `tags` (list of unique strings), and optional `dimensions` (an object with
/// required numeric length, width, and height):
///
/// ```dart
/// final productSchema = ObjectSchema(
///   title: 'Product',
///   description: 'Schema for a product object',
///   required: ['productId', 'productName'],
///   properties: {
///     'productId': Schema.string(
///       description: 'Unique identifier for the product',
///     ),
///     'productName': Schema.string(description: 'Name of the product'),
///     'price': Schema.num(
///       description: 'Price of the product',
///       minimum: 0,
///     ),
///     'tags': Schema.list(
///       description: 'Optional list of tags for the product',
///       items: Schema.string(),
///       uniqueItems: true,
///     ),
///     'dimensions': ObjectSchema(
///       description: 'Optional product dimensions',
///       properties: {
///         'length': Schema.num(),
///         'width': Schema.num(),
///         'height': Schema.num(),
///       },
///       required: ['length', 'width', 'height'],
///     ),
///   },
///   additionalProperties: false, // No other properties allowed beyond those defined
/// );
/// ```
///
/// This schema can then be used with the `validate` method to check if a given
/// JSON-like map conforms to the defined structure.
///
/// For example, valid data might look like:
///
/// ```json
/// {
///   "productId": "ABC12345",
///   "productName": "Super Widget",
///   "price": 19.99,
///   "tags": ["electronics", "gadget"],
///   "dimensions": {"length": 10, "width": 5, "height": 2.5}
/// }
/// ```
///
/// And invalid data (e.g., missing productName, or an extra undefined
/// property):
/// ```json
/// {
///   "productId": "XYZ67890",
///   "price": 9.99
/// }
/// ```
///
/// ```json
/// {
///   "productId": "DEF4567",
///   "productName": "Another Gadget",
///   "color": "blue" // Invalid if additionalProperties is false
/// }
/// ```
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
  ///
  /// For example, to define a schema where any property name starting with
  /// "x-" should have a string value:
  ///
  /// ```dart
  /// final schema = ObjectSchema(patternProperties: {r'^x-': Schema.string()});
  /// ```
  ///
  Map<String, Schema>? get patternProperties =>
      (_value['patternProperties'] as Map?)?.cast<String, Schema>();

  /// A list of the required properties by name.
  ///
  /// For example, to define a schema for an object that requires a `name`
  /// property:
  ///
  /// ```dart
  /// final schema = ObjectSchema(
  ///   required: ['name'],
  ///   properties: {'name': Schema.string()},
  /// );
  /// ```
  ///
  /// In this schema, an object like `{'name': 'John'}` would be valid, but
  /// `{}` or `{'age': 30}` would be invalid because they do not contain the
  /// required `name` property. Note that the type of the `name` property is
  /// also defined using the `properties` field; `required` only enforces the
  /// presence of the property, not its type or value, which are handled by
  /// the corresponding schema in the `properties` map (if provided, otherwise
  /// any value is accepted).
  ///
  /// Properties in this list must be set in the object.
  List<String>? get required => (_value['required'] as List?)?.cast<String>();

  /// Rules for additional properties that don't match the
  /// [properties] or [patternProperties] schemas.
  ///
  /// Can be either a [bool] or a [Schema], if it is a [Schema] then additional
  /// properties should match that [Schema].
  ///
  /// For example, to define a schema where any property not explicitly defined
  /// in `properties` should have an integer value:
  ///
  /// ```dart
  /// final schema = ObjectSchema(
  ///   properties: {'name': Schema.string()},
  ///   additionalProperties: Schema.int(),
  /// );
  /// ```
  ///
  /// In this schema, an object like `{'name': 'John', 'age': 30}` would be
  /// valid, but `{'name': 'John', 'age': 'thirty'}` would be invalid because
  /// `age` is not a defined property and its value is not an integer as
  /// required by `additionalProperties`.
  Object? get additionalProperties => _value['additionalProperties'];

  /// Similar to [additionalProperties] but more flexible, see
  /// https://json-schema.org/understanding-json-schema/reference/object#unevaluatedproperties
  /// for more details.
  ///
  /// For example, to define a schema where any property not explicitly defined
  /// in `properties` or matched by `patternProperties` is disallowed:
  ///
  /// ```dart
  /// final schema = ObjectSchema(
  ///   properties: {'name': Schema.string()},
  ///   patternProperties: {r'^x-': Schema.string()},
  ///   unevaluatedProperties: false,
  /// );
  /// ```
  ///
  /// In this schema, an object like `{'name': 'John', 'x-id': '123'}` would be
  /// valid, but `{'name': 'John', 'age': 30}` would be invalid because `age` is
  /// neither a defined property nor matches the pattern, and
  /// `unevaluatedProperties` is set to `false`.
  bool? get unevaluatedProperties => _value['unevaluatedProperties'] as bool?;

  /// A list of valid patterns for all property names.
  ///
  /// For example, to define a schema where all property names must start with
  /// a lowercase letter:
  ///
  /// ```dart
  /// final schema = ObjectSchema(
  ///   propertyNames: Schema.string(pattern: r'^[a-z].*$'),
  /// );
  /// ```
  ///
  /// In this schema, an object like `{'name': 'John', 'age': 30}` would be
  /// valid, but `{'Name': 'John', 'Age': 30}` would be invalid because the
  /// property names do not start with a lowercase letter.
  StringSchema? get propertyNames =>
      (_value['propertyNames'] as Map?)?.cast<String, Object?>()
          as StringSchema?;

  /// The minimum number of properties in this object.
  ///
  /// If the object has less than this many properties, it will be invalid.
  int? get minProperties => _value['minProperties'] as int?;

  /// The maximum number of properties in this object.
  ///
  /// If the object has more than this many properties, it will be invalid.
  int? get maxProperties => _value['maxProperties'] as int?;

  bool _validateObject(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    if (data is! Map<String, Object?>) {
      accumulatedFailures.add(
        ValidationError(ValidationErrorType.typeMismatch, path: currentPath),
      );
      return false;
    }

    var isValid = true;

    if (minProperties case final min? when data.keys.length < min) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.minPropertiesNotMet,
          path: currentPath,
          details:
              'There should be at least $minProperties '
              'properties. Only ${data.keys.length} were found.',
        ),
      );
    }

    if (maxProperties case final max? when data.keys.length > max) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.maxPropertiesExceeded,
          path: currentPath,
          details:
              'Exceeded maxProperties limit of $maxProperties '
              '(${data.keys.length}).',
        ),
      );
    }

    for (final reqProp in required ?? const []) {
      if (!data.containsKey(reqProp)) {
        isValid = false;
        accumulatedFailures.add(
          ValidationError(
            ValidationErrorType.requiredPropertyMissing,
            path: currentPath,
            details: 'Required property "$reqProp" is missing.',
          ),
        );
      }
    }

    // Check for property values that match any defined properties in the
    // `properties` map. If a property name exists in the `properties` map, the
    // value of that property is validated against the schema associated with
    // that property.
    final evaluatedKeys = <String>{};
    if (properties case final props?) {
      for (final entry in props.entries) {
        if (data.containsKey(entry.key)) {
          currentPath.add(entry.key);
          evaluatedKeys.add(entry.key);
          final propertySpecificFailures = _createHashSet();
          if (!entry.value._validateSchema(
            data[entry.key],
            currentPath,
            propertySpecificFailures,
          )) {
            isValid = false;
            accumulatedFailures.add(
              ValidationError(
                ValidationErrorType.propertyValueInvalid,
                path: currentPath,
              ),
            );
            accumulatedFailures.addAll(propertySpecificFailures);
          }
          currentPath.removeLast();
        }
      }
    }

    // Check for property values that match any defined pattern properties.
    // If a property name matches a pattern in `patternProperties`, the value
    // of that property is validated against the schema associated with that
    // pattern.
    if (patternProperties case final patternProps?) {
      for (final entry in patternProps.entries) {
        final pattern = RegExp(entry.key);
        for (final dataKey in data.keys) {
          if (pattern.hasMatch(dataKey)) {
            currentPath.add(dataKey);
            evaluatedKeys.add(dataKey);
            final patternPropertySpecificFailures = _createHashSet();
            if (!entry.value._validateSchema(
              data[dataKey],
              currentPath,
              patternPropertySpecificFailures,
            )) {
              isValid = false;
              accumulatedFailures.add(
                ValidationError(
                  ValidationErrorType.patternPropertyValueInvalid,
                  path: currentPath,
                ),
              );
              accumulatedFailures.addAll(patternPropertySpecificFailures);
            }
            currentPath.removeLast();
          }
        }
      }
    }

    // If a `propertyNames` schema is defined, iterate over each key (property
    // name) in the input `data` object and validate it against that schema.
    // If any property name is invalid, mark the overall validation as failed
    // and record the specific errors.
    if (propertyNames case final propNamesSchema?) {
      for (final key in data.keys) {
        currentPath.add(key);
        final propertyNameSpecificFailures = _createHashSet();
        if (!propNamesSchema._validateSchema(
          key,
          currentPath,
          propertyNameSpecificFailures,
        )) {
          isValid = false;
          accumulatedFailures.addAll(propertyNameSpecificFailures);
          accumulatedFailures.add(
            ValidationError(
              ValidationErrorType.propertyNamesInvalid,
              path: currentPath,
            ),
          );
        }
        currentPath.removeLast();
      }
    }

    // If additionalProperties is defined, check if unevaluated properties
    // (properties not in `properties` or `patternProperties`) are allowed. If
    // additionalProperties is not defined, check if unevaluated properties are
    // allowed based on the value of unevaluatedProperties.
    for (final dataKey in data.keys) {
      if (evaluatedKeys.contains(dataKey)) continue;

      var isAdditionalPropertyAllowed = true;
      if (additionalProperties != null) {
        final ap = additionalProperties;
        currentPath.add(dataKey);
        if (ap is bool && !ap) {
          isAdditionalPropertyAllowed = false;
        } else if (ap is Schema) {
          final additionalPropSchemaFailures = _createHashSet();
          if (!ap._validateSchema(
            data[dataKey],
            currentPath,
            additionalPropSchemaFailures,
          )) {
            isAdditionalPropertyAllowed = false;
            // Add details why it failed
            accumulatedFailures.addAll(additionalPropSchemaFailures);
          }
        }
        if (!isAdditionalPropertyAllowed) {
          isValid = false;
          accumulatedFailures.add(
            ValidationError(
              ValidationErrorType.additionalPropertyNotAllowed,
              path: currentPath,
            ),
          );
        }
        currentPath.removeLast();
      } else if (unevaluatedProperties == false) {
        isValid = false;
        // Only applies if additionalProperties is not defined
        currentPath.add(dataKey);
        accumulatedFailures.add(
          ValidationError(
            ValidationErrorType.unevaluatedPropertyNotAllowed,
            path: currentPath,
          ),
        );
        currentPath.removeLast();
      }
    }
    return isValid;
  }
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

  bool _validateString(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    if (data is! String) {
      accumulatedFailures.add(
        ValidationError(ValidationErrorType.typeMismatch, path: currentPath),
      );
      return false;
    }
    var isValid = true;
    if (minLength case final minLen? when data.length < minLen) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.minLengthNotMet,
          path: currentPath,
          details: 'String "$data" is not at least $minLen characters long.',
        ),
      );
    }
    if (maxLength case final maxLen? when data.length > maxLen) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.maxLengthExceeded,
          path: currentPath,
          details: 'String "$data" is more than $maxLen characters long.',
        ),
      );
    }
    if (pattern case final dataPattern?
        when !RegExp(dataPattern).hasMatch(data)) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.patternMismatch,
          path: currentPath,
          details: 'String "$data" doesn\'t match the pattern "$dataPattern".',
        ),
      );
    }
    return isValid;
  }
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

  bool _validateNumber(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    if (data is! num) {
      accumulatedFailures.add(
        ValidationError(ValidationErrorType.typeMismatch, path: currentPath),
      );
      return false;
    }

    var isValid = true;
    if (minimum case final min? when data < min) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.minimumNotMet,
          path: currentPath,
          details: 'Value $data is not at least $min.',
        ),
      );
    }
    if (maximum case final max? when data > max) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.maximumExceeded,
          path: currentPath,
          details: 'Value $data is larger than $max.',
        ),
      );
    }
    if (exclusiveMinimum case final exclusiveMin? when data <= exclusiveMin) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.exclusiveMinimumNotMet,
          path: currentPath,

          details: 'Value $data is not greater than $exclusiveMin.',
        ),
      );
    }
    if (exclusiveMaximum case final exclusiveMax? when data >= exclusiveMax) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.exclusiveMaximumExceeded,
          path: currentPath,
          details: 'Value $data is not less than $exclusiveMax.',
        ),
      );
    }
    if (multipleOf case final multOf? when multOf != 0) {
      final remainder = data / multOf;
      if ((remainder - remainder.round()).abs() > 1e-9) {
        isValid = false;
        accumulatedFailures.add(
          ValidationError(
            ValidationErrorType.multipleOfInvalid,
            path: currentPath,
            details: 'Value $data is not a multiple of $multipleOf.',
          ),
        );
      }
    }
    return isValid;
  }
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

  bool _validateInteger(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    if (data == null || (data is! int && data is! num)) {
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.typeMismatch,
          path: currentPath,
          details:
              'Value $data has the type ${data.runtimeType}, which is not '
              'an integer.',
        ),
      );
      return false;
    }
    if (data is num) {
      final intData = data.toInt();
      if (data != intData) {
        accumulatedFailures.add(
          ValidationError(
            ValidationErrorType.typeMismatch,
            path: currentPath,
            details: 'Value $data is a number, but is not an integer.',
          ),
        );
        return false;
      }
      data = intData;
    } else {
      data = data as int;
    }
    var isValid = true;
    if (minimum case final min? when data < min) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.minimumNotMet,
          path: currentPath,
          details: 'Value $data is less than the minimum of $min.',
        ),
      );
    }
    if (maximum case final max? when data > max) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.maximumExceeded,
          path: currentPath,
          details: 'Value $data is more than the maximum of $max.',
        ),
      );
    }
    if (exclusiveMinimum case final exclusiveMin? when data <= exclusiveMin) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.exclusiveMinimumNotMet,
          path: currentPath,
          details: 'Value $data is not greater than $exclusiveMin.',
        ),
      );
    }
    if (exclusiveMaximum case final exclusiveMax? when data >= exclusiveMax) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.exclusiveMaximumExceeded,
          path: currentPath,
          details: 'Value $data is not less than $exclusiveMax.',
        ),
      );
    }
    if (multipleOf case final multOf?
        when multOf != 0 && (data % multOf != 0)) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.multipleOfInvalid,
          path: currentPath,
          details: 'Value $data is not a multiple of $multOf.',
        ),
      );
    }
    return isValid;
  }
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
  ///
  /// For example, to define a schema for a list where all items must be
  /// strings:
  ///
  /// ```dart
  /// final schema = ListSchema(items: Schema.string());
  /// ```
  ///
  /// In this schema, a list like `['apple', 'banana', 'cherry']` would be
  /// valid, but `['apple', 42, 'cherry']` would be invalid because it
  /// contains a non-string item.
  ///
  /// Note that if you want to define a schema for a list where the initial
  /// items have specific types and the remaining items follow a different
  /// schema, you can use the `prefixItems` property in conjunction with
  /// `items`. For example, to allow a string followed by an integer, and
  /// then any number of booleans:
  ///
  /// ```dart
  /// final schema = ListSchema(
  ///   prefixItems: [Schema.string(), Schema.int()],
  ///   items: Schema.bool(),
  /// );
  /// ```
  Schema? get items => _value['items'] as Schema?;

  /// The schema for the initial items in this list, if specified.
  ///
  /// For example, to define a schema for a list where the first item must be
  /// a string and the second item must be an integer:
  ///
  /// ```dart
  /// final schema = ListSchema(
  ///   prefixItems: [Schema.string(), Schema.int()],
  /// );
  /// ```
  ///
  /// In this schema, a list like `['hello', 42]` would be valid, but
  /// `[42, 'hello']` or `['hello']` would be invalid because they do not
  /// conform to the specified order and types of the prefix items.
  ///
  /// Note that if you want to allow additional items in the list that do not
  /// match the prefix items, you can use the `items` property to define a
  /// schema for those additional items. For example, to allow any number of
  /// additional strings after the initial string and integer:
  ///
  /// ```dart
  /// final schema = ListSchema(
  ///   prefixItems: [Schema.string(), Schema.int()],
  ///   items: Schema.string()
  /// );
  /// ```
  List<Schema>? get prefixItems =>
      (_value['prefixItems'] as List?)?.cast<Schema>();

  /// Whether or not  additional items in the list are allowed that don't
  /// match the [items] or [prefixItems] schemas.
  ///
  /// For example, to define a schema for a list where only items matching
  /// `prefixItems` or `items` are allowed:
  ///
  /// ```dart
  /// final schema = ListSchema(
  ///   prefixItems: [Schema.string(), Schema.int()],
  ///   items: Schema.bool(),
  ///   unevaluatedItems: false,
  /// );
  /// ```
  ///
  /// In this schema, a list like `['hello', 42, true]` would be valid, but
  /// `['hello', 42, true, 123]` would be invalid because the last item does
  /// not match the schema defined by `items` (which applies to items
  /// beyond those covered by `prefixItems`), and `unevaluatedItems` is set
  /// to `false`, disallowing any items not explicitly matched by the
  /// schema.
  bool? get unevaluatedItems => _value['unevaluatedItems'] as bool?;

  /// The minimum number of items in this list.
  int? get minItems => _value['minItems'] as int?;

  /// The maximum number of items in this list.
  int? get maxItems => _value['maxItems'] as int?;

  /// Whether or not all the items in this list must be unique.
  ///
  /// For example, to define a schema for a list where all items must be
  /// unique:
  ///
  /// ```dart
  /// final schema = ListSchema(
  ///   items: Schema.string(),
  ///   uniqueItems: true,
  /// );
  /// ```
  ///
  /// In this schema, a list like `['apple', 'banana', 'cherry']` would be
  /// valid, but `['apple', 'banana', 'apple']` would be invalid because it
  /// contains duplicate items. Note that the type of the items is also
  /// defined using the `items` property; `uniqueItems` only enforces the
  /// uniqueness of the items, not their type or value, which are handled by
  /// the corresponding schema in the `items` property.
  bool? get uniqueItems => _value['uniqueItems'] as bool?;

  bool _validateList(
    Object? data,
    List<String> currentPath,
    HashSet<ValidationError> accumulatedFailures,
  ) {
    if (data is! List<dynamic>) {
      accumulatedFailures.add(
        ValidationError(ValidationErrorType.typeMismatch, path: currentPath),
      );
      return false;
    }

    var isValid = true;

    if (minItems case final min? when data.length < min) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.minItemsNotMet,
          path: currentPath,
          details:
              'List has ${data.length} items, but must have at least '
              '$min.',
        ),
      );
    }

    if (maxItems case final max? when data.length > max) {
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.maxItemsExceeded,
          path: currentPath,
          details:
              'List has ${data.length} items, but must have less than '
              '$max.',
        ),
      );
    }

    if (uniqueItems == true && data.toSet().length != data.length) {
      final seenItems = <Object?>{};
      final duplicates = <Object?>{};
      for (final item in data) {
        if (seenItems.contains(item)) {
          duplicates.add(item);
        } else {
          seenItems.add(item);
        }
      }
      isValid = false;
      accumulatedFailures.add(
        ValidationError(
          ValidationErrorType.uniqueItemsViolated,
          path: currentPath,
          details: 'List contains duplicate items: ${duplicates.join(', ')}.',
        ),
      );
    }

    final evaluatedItems = List<bool>.filled(data.length, false);
    if (prefixItems case final pItems?) {
      for (var i = 0; i < pItems.length && i < data.length; i++) {
        evaluatedItems[i] = true;
        currentPath.add(i.toString());
        final prefixItemSpecificFailures = _createHashSet();
        if (!pItems[i]._validateSchema(
          data[i],
          currentPath,
          prefixItemSpecificFailures,
        )) {
          isValid = false;
          accumulatedFailures.add(
            ValidationError(
              ValidationErrorType.prefixItemInvalid,
              path: currentPath,
            ),
          );
          accumulatedFailures.addAll(prefixItemSpecificFailures);
        }
        currentPath.removeLast();
      }
    }
    if (items case final itemSchema?) {
      final startIndex = prefixItems?.length ?? 0;
      for (var i = startIndex; i < data.length; i++) {
        evaluatedItems[i] = true;
        currentPath.add(i.toString());
        final itemSpecificFailures = _createHashSet();
        if (!itemSchema._validateSchema(
          data[i],
          currentPath,
          itemSpecificFailures,
        )) {
          isValid = false;
          accumulatedFailures.add(
            ValidationError(ValidationErrorType.itemInvalid, path: currentPath),
          );
          accumulatedFailures.addAll(itemSpecificFailures);
        }
        currentPath.removeLast();
      }
    }
    if (unevaluatedItems == false) {
      for (var i = 0; i < data.length; i++) {
        if (!evaluatedItems[i]) {
          currentPath.add(i.toString());

          isValid = false;
          accumulatedFailures.add(
            ValidationError(
              ValidationErrorType.unevaluatedItemNotAllowed,
              path: currentPath,
              details: 'Unevaluated item in list at index $i',
            ),
          );
          currentPath.removeLast();
          // Only report the first unevaluated item to avoid excessive errors.
          // If we want all, remove the break. For now, keeping existing
          // behavior of early exit.
          break;
        }
      }
    }
    return isValid;
  }
}

HashSet<ValidationError> _createHashSet() {
  return HashSet<ValidationError>(
    equals: (ValidationError a, ValidationError b) {
      return const ListEquality<String>().equals(a.path, b.path) &&
          a.details == b.details &&
          a.error == b.error;
    },
    hashCode: (ValidationError error) {
      return Object.hashAll([
        ...error.path ?? const [],
        error.details,
        error.error,
      ]);
    },
  );
}
