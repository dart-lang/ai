import 'dart:convert';

import 'package:skills/src/core/package_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Given a project with a valid package_config.json', () {
    late String projectPath;

    setUp(() async {
      await d.dir('project', [
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'dep_a',
                  'rootUri': '../../dep_a',
                  'packageUri': 'lib/',
                },
                {
                  'name': 'dep_b',
                  'rootUri': 'file://${d.path('dep_b')}/',
                  'packageUri': 'lib/',
                },
              ],
            }),
          ),
        ]),
      ]).create();

      await d.dir('dep_a', [
        d.dir('lib', [d.file('dep_a.dart', '')]),
      ]).create();

      await d.dir('dep_b', [
        d.dir('lib', [d.file('dep_b.dart', '')]),
      ]).create();

      projectPath = d.path('project');
    });

    test('when resolving all packages then returns both', () async {
      final resolver = PackageResolver(projectPath);
      final packages = await resolver.resolve();

      expect(packages.map((p) => p.name).toSet(), contains('dep_b'));
    });

    test(
      'when resolving a specific package then returns only that one',
      () async {
        final resolver = PackageResolver(projectPath);
        final packages = await resolver.resolve(packageName: 'dep_b');

        expect(packages, hasLength(1));
        expect(packages.first.name, equals('dep_b'));
      },
    );

    test(
      'when resolving a non-existent package then returns empty list',
      () async {
        final resolver = PackageResolver(projectPath);
        final packages = await resolver.resolve(packageName: 'no_such_pkg');

        expect(packages, isEmpty);
      },
    );
  });

  group('Given a project without package_config.json', () {
    test('when checking hasPackageConfig then returns false', () async {
      await d.dir('empty_project').create();

      final resolver = PackageResolver(d.path('empty_project'));
      expect(resolver.hasPackageConfig, isFalse);
    });

    test('when resolving then throws StateError', () async {
      await d.dir('no_config_project').create();

      final resolver = PackageResolver(d.path('no_config_project'));
      expect(() => resolver.resolve(), throwsA(isA<StateError>()));
    });
  });
}
