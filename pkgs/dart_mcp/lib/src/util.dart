// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_rpc_2/json_rpc_2.dart';

import 'api.dart';

/// Wraps [wrapped] with a function that takes a [Parameters] object, extracts
/// out the value of that object as a `Map<String, Object?>`, casts it to type
/// [T], and then calls [wrapped] with that value and returns the result.
R Function(Parameters) convertParameters<T extends Request, R extends Object?>(
  R Function(T) wrapped,
) => (Parameters p) => wrapped((p.value as Map).cast<String, Object?>() as T);
