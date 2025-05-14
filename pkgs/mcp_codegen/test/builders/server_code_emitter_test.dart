// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:mcp_codegen/src/builders/server_builder.dart';
import 'package:mcp_codegen/src/emitter/code_emitter.dart';
import 'package:mcp_codegen/src/scanners/annotation_scanner.dart';
import 'package:mcp_codegen/src/scanners/tool_scanner.dart';

void main() {
  group('ServerBuilder & CodeEmitter', () {
    late LibraryElement library;
    late Map<ExecutableElement, DartObject> tools;
    late MapEntry<Element, DartObject> serverEntry;

    setUpAll(() async {
      const src = '''
        library test_lib;
        import 'package:mcp_annotations/mcp_annotations.dart';

        @MCPServerApp()
        void myServer() {}

        @MCPTool()
        int add(int a, int b) => a + b;
      ''';

      await resolveSources({'test_pkg|lib/test_lib.dart': src}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
        library = await resolver.libraryFor(libId);
        serverEntry = AnnotationScanner().findFirst(library)!;
        tools = ToolScanner().scan(library, library);
      });
    });

    test('server scaffold contains tool registration', () {
      final serverCode = ServerBuilder().build(
        serverElement: serverEntry.key,
        annotation: serverEntry.value,
        tools: tools.keys.toList(),
      );
      expect(serverCode, contains('final class _GeneratedServer'));
      expect(serverCode, contains('registerTool(_tool_add'));
    });

    test('CodeEmitter integrates everything', () {
      final emitted = CodeEmitter().emit(
        serverElement: serverEntry.key,
        annotation: serverEntry.value,
        tools: tools,
      );
      expect(emitted, contains('_GeneratedServer'));
      expect(emitted, contains('_handler_add'));
    });
  });
}
