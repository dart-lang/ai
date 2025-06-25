part of 'api.dart';

/// The parameters for an `elicitation/create` request.

extension type ElicitationRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'elicitation/create';

  factory ElicitationRequest({
    required String message,
    required Schema requestedSchema,
  }) {
    return ElicitationRequest._fromMap({
      'message': message,
      'requestedSchema': requestedSchema,
    });
  }

  /// A message to display to the user when collecting the response.
  String get message => _value['message'] as String;

  /// A JSON schema that describes the expected response.
  ///
  /// The content will only consist of a flat `Map` (no nested maps or lists)
  /// with primitive values (`String`, `num`, `bool`, `enum`).
  ///
  /// Here are the allowed schemas for the primitive values that could be
  /// received:
  ///
  /// 1. **String Schema**
  ///
  ///    ```json
  ///    {
  ///      "type": "string",
  ///      "title": "Display Name",
  ///      "description": "Description text",
  ///      "minLength": 3,
  ///      "maxLength": 50,
  ///      "pattern": "^[A-Za-z]+$",
  ///      "format": "email"
  ///    }
  ///    ```
  ///
  ///    Supported formats: `email`, `uri`, `date`, `date-time`
  ///
  /// 2. **Number Schema**
  ///
  ///    ```json
  ///    {
  ///      "type": "number", // or "integer"
  ///      "title": "Display Name",
  ///      "description": "Description text",
  ///      "minimum": 0,
  ///      "maximum": 100
  ///    }
  ///    ```
  ///
  /// 3. **Boolean Schema**
  ///
  ///    ```json
  ///    {
  ///      "type": "boolean",
  ///      "title": "Display Name",
  ///      "description": "Description text",
  ///      "default": false
  ///    }
  ///    ```
  ///
  /// 4. **Enum Schema**
  ///    ```json
  ///    {
  ///      "type": "string",
  ///      "title": "Display Name",
  ///      "description": "Description text",
  ///      "enum": ["option1", "option2", "option3"],
  ///      "enumNames": ["Option 1", "Option 2", "Option 3"]
  ///    }
  ///    ```
  ///
  /// In Dart, the enum values will be represented as a `String`.
  Schema get requestedSchema => _value['requestedSchema'] as Schema;

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
