// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'dart:async';

import 'package:build/build.dart';
import 'package:mcp_annotations/mcp_annotations.dart';
import 'package:source_gen/source_gen.dart';

import 'scanners/annotation_scanner.dart';
import 'scanners/tool_scanner.dart';
import 'emitter/code_emitter.dart';

/// Orchestrates the scanning and emission process to generate MCP server
/// source code.
class MCPGenerator extends Generator {
  final AnnotationScanner _annotationScanner = AnnotationScanner();
  final ToolScanner _toolScanner = ToolScanner();
  final CodeEmitter _emitter = CodeEmitter();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    // Locate the element annotated with `@MCPServerApp`.
    final serverEntry = _annotationScanner.findFirst<MCPServerApp>(
      library.element,
    );

    if (serverEntry == null) return null;

    final serverElement = serverEntry.key;
    final serverAnn = serverEntry.value;

    // Gather tools defined in the same library (or within the server class).
    final tools = _toolScanner.scan(library.element, serverElement);

    // Delegate code generation.
    return _emitter.emit(
      serverElement: serverElement,
      annotation: serverAnn,
      tools: tools,
    );
  }
}
