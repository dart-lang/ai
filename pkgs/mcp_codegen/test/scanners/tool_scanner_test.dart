// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:mcp_codegen/src/scanners/tool_scanner.dart';

void main() {
  group('ToolScanner', () {
    test('finds annotated methods and functions', () async {
      const src = '''
        library test_lib;
        import 'package:mcp_annotations/mcp_annotations.dart';

        @MCPServerApp()
        class MyServer {
          @MCPTool()
          int add(int a, int b) => a + b;
        }

        @MCPTool()
        String echo(String message) => message;
      ''';

      await resolveSources({'test_pkg|lib/test_lib.dart': src}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
        final library = await resolver.libraryFor(libId);
        final serverElement = library.topLevelElements
            .whereType<ClassElement>()
            .firstWhere((c) => c.name == 'MyServer');

        final scanner = ToolScanner();
        final classTools = scanner.scan(library, serverElement);
        expect(classTools.keys.map((e) => e.name), contains('add'));

        final globalTools = scanner.scan(library, library);
        expect(globalTools.keys.map((e) => e.name), contains('echo'));
      });
    });
  });
}
