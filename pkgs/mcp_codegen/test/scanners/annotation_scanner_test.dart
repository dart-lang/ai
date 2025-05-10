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
        void myServer() {}
      ''';

      await resolveSources({'test_pkg|lib/test_lib.dart': src}, (
        resolver,
      ) async {
        final libId = AssetId.parse('test_pkg|lib/test_lib.dart');
        final library = await resolver.libraryFor(libId);
        final scanner = AnnotationScanner();
        final result = scanner.findFirst(library);
        expect(result, isNotNull);
        expect(result!.key.name, 'myServer');
      });
    });
  });
}
