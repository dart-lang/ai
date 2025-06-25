part of 'api.dart';

/// The parameters for an `elicitation/create` request.

extension type ElicitationRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'elicitation/create';

  factory ElicitationRequest({
    required String message,
    required Schema requestedSchema,
  }) {
    assert(
      validateRequestedSchema(requestedSchema),
      'Invalid requestedSchema. Must be a flat object of primitive values.',
    );
    return ElicitationRequest._fromMap({
      'message': message,
      'requestedSchema': requestedSchema,
    });
  }

  /// A message to display to the user when collecting the response.
  String get message => _value['message'] as String;

  /// A JSON schema that describes the expected response.
  ///
  /// The content may only consist of a flat `Map` (no nested maps or lists)
  /// with primitive values (`String`, `num`, `bool`, `enum`).
  ///
  /// You can use [validateRequestedSchema] to validate that the schema conforms
  /// to these limitations.
  ///
  /// In Dart, the enum values will be represented as a `String`.
  Schema get requestedSchema => _value['requestedSchema'] as Schema;

  /// Validates the [schema] to make sure that it conforms to the
  /// limitations of the spec.
  ///
  /// See also: [requestedSchema] for a description of the spec limitations.
  static bool validateRequestedSchema(Schema schema) {
    if (schema.type != JsonType.object) {
      return false;
    }

    final objectSchema = schema as ObjectSchema;
    final properties = objectSchema.properties;

    if (properties == null) {
      return true; // No properties to validate.
    }

    for (final propertySchema in properties.values) {
      // Combinators would mean it's not a simple primitive type.
      if (propertySchema.allOf != null ||
          propertySchema.anyOf != null ||
          propertySchema.oneOf != null ||
          propertySchema.not != null) {
        return false;
      }

      switch (propertySchema.type) {
        case JsonType.string:
        case JsonType.num:
        case JsonType.int:
        case JsonType.bool:
        case JsonType.enumeration:
          // These are the allowed primitive types.
          break;
        case JsonType.object:
        case JsonType.list:
        case JsonType.nil:
        case null:
          // Disallowed, or no type specified.
          return false;
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() => _value;
}

/// The response to an `elicitation/create` request.
extension type ElicitationResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory ElicitationResult({
    required ElicitationAction action,
    Map<String, Object?>? content,
  }) => ElicitationResult.fromMap({'action': action, 'content': content});

  /// The action taken by the user.
  ElicitationAction get action => _value['action'] as ElicitationAction;

  /// The content of the response, if the user accepted the request.
  ///
  /// Must be `null` if the user didn't accept the request.
  ///
  /// The content must conform to the [ElicitationRequest]'s `requestedSchema`.
  Map<String, Object?>? get content =>
      _value['content'] as Map<String, Object?>?;

  Map<String, dynamic> toJson() => _value;
}

/// The action taken by the user in response to an elicitation request.
enum ElicitationAction {
  /// The user accepted the request and provided the requested information.
  accept,

  /// The user rejected the request.
  reject,

  /// The user cancelled the request.
  cancel;

  factory ElicitationAction.fromJson(String json) {
    return ElicitationAction.values.firstWhere((e) => e.name == json);
  }

  String toJson() => name;
}
