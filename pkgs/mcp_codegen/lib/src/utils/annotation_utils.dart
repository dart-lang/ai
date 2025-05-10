// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';

/// Utility extension methods for working with annotations via `source_gen`'s
/// `TypeChecker` API.
extension AnnotationHelpers on Element {
  /// Returns `true` when [checker] matches at least one annotation on `this`.
  bool isAnnotated(TypeChecker checker) => checker.hasAnnotationOfExact(this);

  /// Returns the first annotation on `this` that matches [checker] using an
  /// *exact* type check, or `null` when none is found.
  DartObject? firstAnnotation(TypeChecker checker) =>
      checker.firstAnnotationOfExact(this);
}
