// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// The parameters for an `elicitation/create` request.
extension type ElicitRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'elicitation/create';

  factory ElicitRequest({
    required String message,
    required Schema requestedSchema,
  }) {
    assert(
      validateRequestedSchema(requestedSchema),
      'Invalid requestedSchema. Must be a flat object of primitive values.',
    );
    return ElicitRequest._fromMap({
      'message': message,
      'requestedSchema': requestedSchema,
    });
  }

  /// A message to display to the user when collecting the response.
  String get message {
    final message = _value['message'] as String?;
    if (message == null) {
      throw ArgumentError('Missing required message field in $ElicitRequest');
    }
    return message;
  }

  /// A JSON schema that describes the expected response.
  ///
  /// The content may only consist of a flat object (no nested maps or lists)
  /// with primitive values (`String`, `num`, `bool`, `enum`).
  ///
  /// You can use [validateRequestedSchema] to validate that a schema conforms
  /// to these limitations.
  Schema get requestedSchema {
    final requestedSchema = _value['requestedSchema'] as Schema?;
    if (requestedSchema == null) {
      throw ArgumentError(
        'Missing required requestedSchema field in $ElicitRequest',
      );
    }
    return requestedSchema;
  }

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
}

/// The client's response to an `elicitation/create` request.
extension type ElicitResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory ElicitResult({
    required ElicitationAction action,
    Map<String, Object?>? content,
  }) => ElicitResult.fromMap({'action': action.name, 'content': content});

  /// The action taken by the user in response to an elicitation request.
  ///
  /// - [ElicitationAction.accept]: The user accepted the request and provided
  ///   the requested information.
  /// - [ElicitationAction.reject]: The user explicitly declined the action.
  /// - [ElicitationAction.cancel]: The user dismissed without making an
  ///   explicit choice.
  ElicitationAction get action {
    final action = _value['action'] as String?;
    if (action == null) {
      throw ArgumentError('Missing required action field in $ElicitResult');
    }
    return ElicitationAction.values.byName(action);
  }

  /// The content of the response, if the user accepted the request.
  ///
  /// Must be `null` if the user didn't accept the request.
  ///
  /// The content must conform to the [ElicitRequest]'s `requestedSchema`.
  Map<String, Object?>? get content =>
      _value['content'] as Map<String, Object?>?;
}

/// The action taken by the user in response to an elicitation request.
enum ElicitationAction {
  /// The user accepted the request and provided the requested information.
  accept,

  /// The user explicitly declined the action.
  reject,

  /// The user dismissed without making an explicit choice.
  cancel,
}
