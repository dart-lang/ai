// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension McpErrorCodes on Never {
  /// Error code for when a URL elicitation is required.
  ///
  /// Defined by the 2025-11-25 revision only; the 2026-07-28 revision
  /// reserves this code, and implementations of it must not emit it.
  static const int urlElicitationRequired = -32042;

  /// Error code for a Streamable HTTP request whose required headers are
  /// missing, malformed, or do not match the request body.
  ///
  /// From the 2026-07-28 revision, which reserves `-32020` to `-32099` for
  /// the specification.
  static const int headerMismatch = -32020;

  /// Error code for a request missing a required client capability.
  ///
  /// From the 2026-07-28 revision.
  static const int missingRequiredClientCapability = -32021;

  /// Error code for a request on a protocol version the server does not
  /// support.
  ///
  /// From the 2026-07-28 revision.
  static const int unsupportedProtocolVersion = -32022;
}
