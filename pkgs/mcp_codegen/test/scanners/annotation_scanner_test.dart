// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:mcp_codegen/src/scanners/annotation_scanner.dart';

void main() {
  group('AnnotationScanner', () {
    test('finds top-level server function', () async {
      const src = '''
        library test_lib;
        import 'package:mcp_annotations/mcp_annotations.dart';

        @MCPServerApp()
        class MyServer {
          const MyServer();
          @MCPTool()
          int add(int a, int b) => a + b;
        }
      ''';

      await resolveSources({'test_pkg|lib/test_lib.dart': src}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
        final library = await resolver.libraryFor(libId);
        final scanner = AnnotationScanner();
        final result = scanner.findFirst(library);
        expect(result, isNotNull);
        expect(result!.key.name, 'MyServer');
      });
    });
  });
}
