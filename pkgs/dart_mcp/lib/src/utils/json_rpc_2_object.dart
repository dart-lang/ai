// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'constants.dart';

/// The kind of a decoded JSON-RPC 2.0 message.
enum JsonRpc2Kind { request, notification, response }

/// A decoded JSON-RPC 2.0 message.
extension type JsonRpc2Object.fromMap(Map<String, Object?> _value) {
  /// The kind of this message.
  ///
  /// A message with a `result` or `error` member is a response, any other
  /// message with an `id` member is a request, and the rest are
  /// notifications.
  JsonRpc2Kind get kind =>
      _value.containsKey(Keys.result) || _value.containsKey(Keys.error)
          ? JsonRpc2Kind.response
          : _value.containsKey(Keys.id)
          ? JsonRpc2Kind.request
          : JsonRpc2Kind.notification;

  /// The method of this message, if it is a request or notification.
  String? get method => _value[Keys.method] as String?;

  /// The id of this message, if it is a request or response.
  ///
  /// A JSON-RPC id is a `String` or an `int`.
  Object? get id => _value[Keys.id];
}

/// A decoded JSON-RPC 2.0 request.
extension type JsonRpc2Request.fromMap(Map<String, Object?> _value)
    implements JsonRpc2Object {}

/// A decoded JSON-RPC 2.0 response.
extension type JsonRpc2Response.fromMap(Map<String, Object?> _value)
    implements JsonRpc2Object {
  /// The result of this response, if it is a success response.
  Object? get result => _value[Keys.result];
}
