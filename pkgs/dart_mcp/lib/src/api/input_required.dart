// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// A request an [InputRequiredResult] carries, written the way the schema
/// writes it: the method name next to the request it applies to.
///
/// The schema names [ElicitRequest], [CreateMessageRequest] and
/// [ListRootsRequest] here and nothing else, so there is a constructor for
/// each. Reading one back, dispatch on [method] and then read [params] as the
/// matching type.
///
/// From the 2026-07-28 revision.
extension type InputRequest._(Map<String, Object?> _value) {
  factory InputRequest.fromMap(Map<String, Object?> value) {
    assert(value.containsKey(Keys.method));
    return InputRequest._(value);
  }

  factory InputRequest.elicit(ElicitRequest request) => InputRequest._({
    Keys.method: ElicitRequest.methodName,
    Keys.params: request,
  });

  factory InputRequest.sample(CreateMessageRequest request) => InputRequest._({
    Keys.method: CreateMessageRequest.methodName,
    Keys.params: request,
  });

  factory InputRequest.listRoots(ListRootsRequest request) => InputRequest._({
    Keys.method: ListRootsRequest.methodName,
    Keys.params: request,
  });

  /// The method this request is made under.
  ///
  /// The schema requires this on every kind it allows here.
  String get method => _value[Keys.method] as String;

  /// The request itself, which [method] says how to read.
  ///
  /// The schema requires this next to `elicitation/create` and
  /// `sampling/createMessage`. For `roots/list` it only requires the method.
  ///
  /// Throws an [ArgumentError] when a server sent something other than an
  /// object here.
  Request? get params {
    final params = _value[Keys.params];
    if (params == null) return null;
    if (params is! Map) {
      throw ArgumentError(
        'The input request params for "$method" were ${params.runtimeType}, '
        'expected an object.',
      );
    }
    return params.cast<String, Object?>() as Request;
  }

  /// Whether this carries an [ElicitRequest].
  bool get isElicit => _value[Keys.method] == ElicitRequest.methodName;

  /// Whether this carries a [CreateMessageRequest].
  bool get isSample => _value[Keys.method] == CreateMessageRequest.methodName;

  /// Whether this carries a [ListRootsRequest].
  bool get isListRoots => _value[Keys.method] == ListRootsRequest.methodName;
}

/// Sent by a server in place of the result a request asked for, when it needs
/// something from the client first.
///
/// The schema answers with one on `tools/call`, `prompts/get` and
/// `resources/read`, and [Result.resultType] reads `input_required` on it. The
/// client answers the [inputRequests] and then sends the original request
/// again, with the answers and the [requestState] attached. That retry is a
/// new request, so this result ends the exchange it belongs to.
///
/// The schema requires at least one of [inputRequests] and [requestState],
/// since a result carrying neither asks for nothing and hands back nothing to
/// retry with. The unnamed constructor asserts it, and goes one step further
/// by treating an empty [inputRequests] the same way. An empty map is valid on
/// the wire and a server may mean something by it, and `fromMap` keeps
/// whatever a server sent.
///
/// From the 2026-07-28 revision.
extension type InputRequiredResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory InputRequiredResult({
    Map<String, InputRequest>? inputRequests,
    String? requestState,
    Meta? meta,
  }) {
    assert(
      (inputRequests != null && inputRequests.isNotEmpty) ||
          requestState != null,
      'The schema requires at least one of `inputRequests` and `requestState`. '
      'An empty `inputRequests` is valid on the wire, and this constructor '
      'still takes it as asking for nothing.',
    );
    return InputRequiredResult.fromMap({
      Keys.resultType: ResultTypes.inputRequired,
      if (inputRequests != null) Keys.inputRequests: inputRequests,
      if (requestState != null) Keys.requestState: requestState,
      if (meta != null) Keys.meta: meta,
    });
  }

  /// The requests the server issued, keyed by the name the client answers each
  /// one under.
  ///
  /// The keys are the server's own identifiers, and the answers go back under
  /// the same ones.
  Map<String, InputRequest>? get inputRequests =>
      (_value[Keys.inputRequests] as Map?)?.cast<String, InputRequest>();

  /// State the server wants back when the client retries the request.
  ///
  /// This is opaque to the client, which sends it on unread.
  String? get requestState => _value[Keys.requestState] as String?;
}

/// A "mixin"-like extension type for any request that contains input responses
/// at the keys "inputResponses" and "requestState".
///
/// These are the other half of an [InputRequiredResult], what a client puts on
/// the retry. The requests which can answer with one take them.
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
///
/// From the 2026-07-28 revision.
extension type WithInputResponses._fromMap(Map<String, Object?> _value)
    implements Request {
  /// What the client got for each request in
  /// [InputRequiredResult.inputRequests], under the keys the server gave them.
  ///
  /// These carry no method field the way an [InputRequest] does, so a server
  /// reads each back as the type it asked for under that key. A key it did not
  /// ask for is one to ignore.
  Map<String, Result>? get inputResponses =>
      (_value[Keys.inputResponses] as Map?)?.cast<String, Result>();

  /// The [InputRequiredResult.requestState] the server sent, echoed back
  /// unread.
  ///
  /// The value arrives from the client, and the spec has the server treat it
  /// as attacker-controlled input. Nothing here signs or verifies it. A server
  /// whose state carries anything it would not accept straight off the wire
  /// has to protect and check it itself.
  String? get requestState => _value[Keys.requestState] as String?;
}
