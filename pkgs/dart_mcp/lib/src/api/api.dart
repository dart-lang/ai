// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Interfaces are based on https://github.com/modelcontextprotocol/specification/blob/main/schema/2024-11-05/schema.json
//
// TODO: Finish porting the commented out typescript types to dart extension
//       types.
// TODO: Autogenerate this from schema files
library;

import 'package:json_rpc_2/json_rpc_2.dart';

part 'initialization.dart';
part 'logging.dart';
part 'prompts.dart';
part 'resources.dart';
part 'roots.dart';
part 'sampling.dart';
part 'tools.dart';

/// The current protocol version
const protocolVersion = '2024-11-05';

/// A progress token, used to associate progress notifications with the original
/// request.
extension type ProgressToken( /*String|int*/ Object _) {}

/// An opaque token used to represent a cursor for pagination.
extension type Cursor(String _) {}

/// Generic metadata passed with most requests, can be anything.
extension type Meta.fromMap(Map<String, Object?> _value) {}

/// A "mixin"-like extension type for any extension type that might contain a
/// [ProgressToken] at the key "progressToken".
///
/// Should be "mixed in" by implementing this type from other extension types.
extension type WithProgressToken.fromMap(Map<String, Object?> _value) {
  ProgressToken? get progressToken => _value['progressToken'] as ProgressToken?;
}

/// A [Meta] object with a known progress token key.
///
/// Has arbitrary other keys.
extension type MetaWithProgressToken.fromMap(Map<String, Object?> _value)
    implements Meta, WithProgressToken {
  factory MetaWithProgressToken({ProgressToken? progressToken}) =>
      MetaWithProgressToken.fromMap({'progressToken': progressToken});
}

/// Base interface for all request types.
///
/// Should not be constructed directly, and has no public constructor.
extension type Request._fromMap(Map<String, Object?> _value) {
  /// If specified, the caller is requesting out-of-band progress notifications
  /// for this request (as represented by notifications/progress).
  ///
  /// The value of this parameter is an opaque token that will be attached to
  /// any subsequent notifications. The receiver is not obligated to provide
  /// these notifications.
  MetaWithProgressToken? get meta => _value['_meta'] as MetaWithProgressToken?;
}

/// Base interface for all notifications.
extension type Notification(Map<String, Object?> _value) {
  /// This parameter name is reserved by MCP to allow clients and servers to
  /// attach additional metadata to their notifications.
  Meta? get meta => _value['_meta'] as Meta?;
}

/// Base interface for all responses to requests.
extension type Result._(Map<String, Object?> _value) {
  Meta? get meta => _value['_meta'] as Meta?;
}

/// A response that indicates success but carries no data.
extension type EmptyResult.fromMap(Map<String, Object?> _) implements Result {
  factory EmptyResult() => EmptyResult.fromMap(const {});
}

/// This notification can be sent by either side to indicate that it is
/// cancelling a previously-issued request.
///
/// The request SHOULD still be in-flight, but due to communication latency, it
/// is always possible that this notification MAY arrive after the request has
/// already finished.
///
/// This notification indicates that the result will be unused, so any
/// associated processing SHOULD cease.
///
/// A client MUST NOT attempt to cancel its `initialize` request.
extension type CancelledNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/cancelled';

  factory CancelledNotification({
    required RequestId requestId,
    String? reason,
    Meta? meta,
  }) {
    return CancelledNotification.fromMap({
      'requestId': requestId,
      if (reason != null) 'reason': reason,
      if (meta != null) '_meta': meta,
    });
  }

  /// The ID of the request to cancel.
  ///
  /// This MUST correspond to the ID of a request previously issued in the same
  /// direction.
  RequestId? get requestId => _value['requestId'] as RequestId?;

  /// An optional string describing the reason for the cancellation. This MAY be
  /// logged or presented to the user.
  String? get reason => _value['reason'] as String?;
}

/// An opaque request ID.
extension type RequestId( /*String|int*/ Parameter _) {}

/// A ping, issued by either the server or the client, to check that the other
/// party is still alive.
///
/// The receiver must promptly respond, or else may be disconnected.
extension type PingRequest.fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'ping';

  factory PingRequest({MetaWithProgressToken? meta}) =>
      PingRequest.fromMap({if (meta != null) '_meta': meta});
}

/// An out-of-band notification used to inform the receiver of a progress
/// update for a long-running request.
extension type ProgressNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/progress';

  factory ProgressNotification({
    required ProgressToken progressToken,
    required int progress,
    int? total,
    Meta? meta,
  }) => ProgressNotification.fromMap({
    'progressToken': progressToken,
    'progress': progress,
    if (total != null) 'total': total,
    if (meta != null) '_meta': meta,
  });

  /// The progress token which was given in the initial request, used to
  /// associate this notification with the request that is proceeding.
  ProgressToken get progressToken => _value['progressToken'] as ProgressToken;

  /// The progress thus far.
  ///
  /// This should increase every time progress is made, even if the total is
  /// unknown.
  int get progress => _value['progress'] as int;

  /// Total number of items to process (or total progress required), if
  /// known.
  int? get total => _value['total'] as int?;
}

/// A "mixin"-like extension type for any request that contains a [Cursor] at
/// the key "cursor".
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
extension type PaginatedRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  /// An opaque token representing the current pagination position.
  ///
  /// If provided, the server should return results starting after this cursor.
  Cursor? get cursor => _value['cursor'] as Cursor?;
}

/// A "mixin"-like extension type for any result type that contains a [Cursor]
/// at the key "cursor".
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
extension type PaginatedResult._fromMap(Map<String, Object?> _value)
    implements Result {
  Cursor? get cursor => _value['cursor'] as Cursor?;
}
