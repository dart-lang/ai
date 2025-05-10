// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:mcp_annotations/mcp_annotations.dart';
import 'package:source_gen/source_gen.dart';

/// Scans a library for the first element annotated with [MCPServerApp].
class AnnotationScanner {
  final TypeChecker _serverChecker = TypeChecker.fromRuntime(MCPServerApp);

  /// Returns the first element annotated with `@MCPServerApp`, or `null` if
  /// no such element exists.
  MapEntry<Element, DartObject>? findFirst<T>(LibraryElement lib) {
    for (var unit in lib.units) {
      for (var element in [...unit.functions, ...unit.classes]) {
        final ann = _serverChecker.firstAnnotationOfExact(element);
        if (ann != null) return MapEntry<Element, DartObject>(element, ann);
      }
    }
    return null;
  }
}
