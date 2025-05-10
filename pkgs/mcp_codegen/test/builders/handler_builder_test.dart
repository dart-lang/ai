// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:mcp_codegen/src/builders/handler_builder.dart';

void main() {
  group('HandlerBuilder', () {
    late FunctionElement addFunc;
    late DartObject addAnn;

    setUpAll(() async {
      const src = '''
        library test_lib;
        import 'package:mcp_annotations/mcp_annotations.dart';

        @MCPTool(destructiveHint: true, title: 'Adder')
        int add(int a, int b) => a + b;
      ''';
      await resolveSources({'test_pkg|lib/test_lib.dart': src}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
        final library = await resolver.libraryFor(libId);
        addFunc =
            library.topLevelElements.firstWhere((e) => e.name == 'add')
                as FunctionElement;
        addAnn = addFunc.metadata.first.computeConstantValue()!;
      });
    });

    test('produces tool and handler code', () {
      final code = HandlerBuilder().build(addFunc, addAnn, false);
      expect(code, contains('final Tool _tool_add'));
      expect(code, contains('FutureOr<CallToolResult> _handler_add'));
    });

    test('includes annotation flags', () {
      final code = HandlerBuilder().build(addFunc, addAnn, false);
      expect(code, contains('ToolAnnotations('));
      expect(code, contains('destructiveHint: true'));
      expect(code, contains('title: Adder'));
    });
  });
}
