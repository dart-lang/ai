// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:mcp_annotations/mcp_annotations.dart';
import 'package:source_gen/source_gen.dart';

import '../utils/annotation_utils.dart';

/// Scans for `@MCPTool` annotations within the context of the discovered
/// server element.
class ToolScanner {
  final TypeChecker _toolChecker = TypeChecker.fromRuntime(MCPTool);

  /// Returns a map whose keys are the annotated executable elements (methods
  /// or top-level functions) and whose values are their corresponding
  /// annotation values.
  Map<ExecutableElement, DartObject> scan(
    LibraryElement lib,
    Element serverElement,
  ) {
    // When the server is a class, look only at its methods.
    if (serverElement is ClassElement) {
      return {
        for (var method in serverElement.methods)
          if (method.isAnnotated(_toolChecker))
            method: method.firstAnnotation(_toolChecker)!,
      };
    }

    // Otherwise, scan all top-level functions in the compilation units.
    return {
      for (var unit in lib.units)
        for (var fn in unit.functions)
          if (fn.isAnnotated(_toolChecker))
            fn: fn.firstAnnotation(_toolChecker)!,
    };
  }
}
