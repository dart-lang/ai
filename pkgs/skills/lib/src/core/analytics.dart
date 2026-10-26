// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:unified_analytics/unified_analytics.dart';

/// Provides access to the [Analytics] instance injected into the current Zone.
/// If no instance is provided, returns a [NoOpAnalytics].
Analytics get analytics =>
    Zone.current[#_analytics] as Analytics? ?? const NoOpAnalytics();

/// Runs [body] within a new zone that provides [analyticsInstance] via the
/// `analytics` getter.
T runWithAnalytics<T>(Analytics? analyticsInstance, T Function() body) {
  return runZoned(body, zoneValues: {#_analytics: analyticsInstance});
}

/// Logs errors, recording just the runtime type of the error.
///
/// These do not all indicate bugs, and could for instance be [ArgumentError]s.
final class ErrorMetrics extends CustomMetrics {
  // Can't be called `runtimeType`.
  final String runtimeTypeName;

  ErrorMetrics(this.runtimeTypeName);

  static const String type = 'error';

  @override
  Map<String, Object> toMap() => {'runtimeType': runtimeTypeName};
}
