// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// The mode of an elicitation request.
enum ElicitationMode { form, url }

/// The parameters for an `elicitation/create` request.
extension type ElicitRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'elicitation/create';

  /// Creates a form-mode elicitation request.
  static const form = ElicitRequest.new;

  @Deprecated('Use `ElicitRequest.form` instead.')
  factory ElicitRequest({
    required String message,
    required ObjectSchema requestedSchema,
  }) {
    assert(
      validateRequestedSchema(requestedSchema),
      'Invalid requestedSchema. Must be a flat object of primitive values.',
    );
    return ElicitRequest._fromMap({
      Keys.mode: ElicitationMode.form.name,
      Keys.message: message,
      Keys.requestedSchema: requestedSchema,
    });
  }

  /// Creates a URL-mode elicitation request.
  factory ElicitRequest.url({
    required String message,
    required String url,
    required String elicitationId,
  }) {
    return ElicitRequest._fromMap({
      Keys.mode: ElicitationMode.url.name,
      Keys.message: message,
      Keys.url: url,
      Keys.elicitationId: elicitationId,
    });
  }

  /// The mode of this elicitation.
  ElicitationMode get mode {
    final mode = _value[Keys.mode] as String?;
    // Default to form for backward compatibility unless specified.
    if (mode == null) return ElicitationMode.form;
    return ElicitationMode.values.firstWhere((value) => value.name == mode);
  }

  /// A message to display to the user when collecting the response.
  String get message {
    final message = _value[Keys.message] as String?;
    if (message == null) {
      throw ArgumentError('Missing required message field in $ElicitRequest');
    }
    return message;
  }

  /// A unique identifier for the elicitation.
  ///
  /// Required for [ElicitationMode.url].
  String? get elicitationId => _value[Keys.elicitationId] as String?;

  /// The URL that the user should navigate to.
  ///
  /// Required for [ElicitationMode.url].
  String? get url => _value[Keys.url] as String?;

  /// A JSON schema that describes the expected response.
  ///
  /// Required for [ElicitationMode.form].
  ObjectSchema? get requestedSchema =>
      _value[Keys.requestedSchema] as ObjectSchema?;

  /// Validates the [schema] to make sure that it conforms to the
  /// limitations of the spec.
  ///
  /// See also: [requestedSchema] for a description of the spec limitations.
  static bool validateRequestedSchema(ObjectSchema schema) {
    if (schema.type != JsonType.object) {
      return false;
    }

    final properties = schema.properties;
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
        case JsonType
            .enumeration: // ignore: deprecated_member_use_from_same_package
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
  }) => ElicitResult.fromMap({Keys.action: action.name, Keys.content: content});

  /// The action taken by the user in response to an elicitation request.
  ///
  /// - [ElicitationAction.accept]: The user accepted the request and provided
  ///   the requested information.
  /// - [ElicitationAction.decline]: The user explicitly declined the action.
  /// - [ElicitationAction.cancel]: The user dismissed without making an
  ///   explicit choice.
  ElicitationAction get action {
    var action = _value[Keys.action] as String?;
    if (action == null) {
      throw ArgumentError('Missing required action field in $ElicitResult');
    }
    // There was a bug in the initial schema, where the `decline` action was
    // named `reject` instead. Handle using that as an alias for `decline` in
    // case some clients use the old name.
    if (action == 'reject') action = Keys.decline;

    return ElicitationAction.values.firstWhere((value) => value.name == action);
  }

  /// The content of the response, if the user accepted the request.
  ///
  /// Must be `null` if the user didn't accept the request, or if it was a
  /// URL-mode elicitation.
  ///
  /// The content must conform to the [ElicitRequest]'s `requestedSchema` in
  /// form mode.
  Map<String, Object?>? get content =>
      _value[Keys.content] as Map<String, Object?>?;
}

/// The action taken by the user in response to an elicitation request.
enum ElicitationAction {
  /// The user accepted the request and provided the requested information.
  accept,

  /// The user explicitly declined the action.
  decline,

  /// The user dismissed without making an explicit choice.
  cancel;

  @Deprecated('Use `ElicitationAction.decline` instead.')
  static const reject = decline;
}

/// A notification from the server to the client that a URL elicitation has
/// completed.
extension type ElicitationCompleteNotification.fromMap(
  Map<String, Object?> _value
)
    implements Notification {
  static const methodName = 'notifications/elicitation/complete';

  factory ElicitationCompleteNotification({
    required String elicitationId,
    Meta? meta,
  }) => ElicitationCompleteNotification.fromMap({
    Keys.elicitationId: elicitationId,
    if (meta != null) Keys.meta: meta,
  });

  /// The identifier of the completed elicitation.
  String get elicitationId {
    final id = _value[Keys.elicitationId] as String?;
    if (id == null) {
      throw ArgumentError(
        'Missing elicitationId in $ElicitationCompleteNotification',
      );
    }
    return id;
  }
}
