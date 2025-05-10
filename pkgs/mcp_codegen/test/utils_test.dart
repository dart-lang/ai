// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';
import 'package:source_gen/source_gen.dart';
import 'package:mcp_annotations/mcp_annotations.dart';

import 'package:mcp_codegen/src/utils/annotation_utils.dart';

void main() {
  const src = '''
    library test_lib;
    import 'package:mcp_annotations/mcp_annotations.dart';

    @MCPTool()
    void toolFn() {}

    void nonAnnotated() {}
  ''';

  test('AnnotationHelpers detects annotations correctly', () async {
    await resolveSources({'test_pkg|lib/test_lib.dart': src}, (resolver) async {
      final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
      final library = await resolver.libraryFor(libId);
      final toolElement = library.topLevelElements.firstWhere(
        (e) => e.name == 'toolFn',
      );
      final nonElement = library.topLevelElements.firstWhere(
        (e) => e.name == 'nonAnnotated',
      );

      final checker = TypeChecker.fromRuntime(MCPTool);
      expect(toolElement.isAnnotated(checker), isTrue);
      expect(nonElement.isAnnotated(checker), isFalse);

      expect(toolElement.firstAnnotation(checker), isNotNull);
      expect(nonElement.firstAnnotation(checker), isNull);
    });
  });
}
