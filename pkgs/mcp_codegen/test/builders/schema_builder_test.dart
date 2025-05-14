// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';

import 'package:mcp_codegen/src/builders/schema_builder.dart';

void main() {
  group('SchemaBuilder', () {
    const source = '''
      library test_lib;
      import 'package:mcp_annotations/mcp_annotations.dart';

      @MCPTool()
      int add(int a, int b) => a + b;
    ''';

    late FunctionElement addFunc;

    setUpAll(() async {
      await resolveSources({'test_pkg|lib/test_lib.dart': source}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
        final library = await resolver.libraryFor(libId);
        addFunc =
            library.topLevelElements.firstWhere((e) => e.name == 'add')
                as FunctionElement;
      });
    });

    test('generates schema for int params', () {
      final schema = SchemaBuilder().build(addFunc.parameters, null);
      expect(schema, contains("'a'"));
      expect(schema, contains('IntegerSchema'));
    });

    test('supports multiple Dart core types', () async {
      const typedSrc = '''
        library t2;
        import 'package:mcp_annotations/mcp_annotations.dart';

        @MCPTool()
        void fn(int a, double b, num c, String d, bool e, Map<String,String> f) {}
      ''';

      await resolveSources({'test_pkg|lib/t2.dart': typedSrc}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/t2.dart');
        final lib = await resolver.libraryFor(libId);
        final fnElem =
            lib.topLevelElements.firstWhere((e) => e.name == 'fn')
                as FunctionElement;
        final schema = SchemaBuilder().build(fnElem.parameters, null);
        expect(schema, contains('IntegerSchema'));
        expect(schema, contains('NumberSchema'));
        expect(schema, contains('StringSchema'));
        expect(schema, contains('BooleanSchema'));
        expect(schema, contains('ObjectSchema'));
      });
    });
  });
}
