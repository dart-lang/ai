import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a single-package project', () {
    test(
      'when resolving then returns one package pointing at project root',
      () async {
        await d.dir('my_project', [
          d.file('pubspec.yaml', '''
name: my_project
environment:
  sdk: ^3.11.0
'''),
        ]).create();

        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('my_project'));

        expect(layout.rootPath, equals(d.path('my_project')));
        expect(layout.isWorkspace, isFalse);
        expect(layout.packages, hasLength(1));
        expect(layout.packages.first.name, equals('my_project'));
        expect(layout.packages.first.path, equals(d.path('my_project')));
      },
    );
  });

  group('Given a single package within a pub workspace', () {
    setUp(() async {
      await d.dir('workspace_root', [
        d.file('pubspec.yaml', '''
name: _
environment:
  sdk: ^3.11.0
workspace:
  - my_pkg
'''),
        d.dir('my_pkg', [
          d.file('pubspec.yaml', '''
name: my_pkg
environment:
  sdk: ^3.11.0
resolution: workspace
'''),
        ]),
      ]).create();
    });

    test(
      'when resolving the single package then uses the workspace '
      'package_config.json path',
      () async {
        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(
          d.path(p.join('workspace_root', 'my_pkg')),
        );

        expect(
          layout.rootPath,
          equals(d.path(p.join('workspace_root', 'my_pkg'))),
        );
        expect(layout.isWorkspace, isFalse);
        expect(layout.packages, hasLength(1));

        final expectedConfig = d.path(
          p.join('workspace_root', '.dart_tool', 'package_config.json'),
        );
        expect(layout.packages.first.packageConfigPath, equals(expectedConfig));
      },
    );

    test('when workspace root is not found then throws StateError', () async {
      await d.dir('isolated_pkg', [
        d.file('pubspec.yaml', '''
name: isolated_pkg
environment:
  sdk: ^3.11.0
resolution: workspace
'''),
      ]).create();

      const resolver = WorkspaceResolver();
      expect(
        () => resolver.resolve(d.path('isolated_pkg')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Given a Dart pub workspace', () {
    setUp(() async {
      await d.dir('workspace', [
        d.file('pubspec.yaml', '''
name: _
publish_to: none
environment:
  sdk: ^3.11.0
workspace:
  - packages/app
  - packages/shared
'''),
        d.dir('packages', [
          d.dir('app', [
            d.file('pubspec.yaml', '''
name: app
environment:
  sdk: ^3.11.0
resolution: workspace
'''),
          ]),
          d.dir('shared', [
            d.file('pubspec.yaml', '''
name: shared
environment:
  sdk: ^3.11.0
resolution: workspace
'''),
          ]),
        ]),
      ]).create();
    });

    test(
      'when resolving then returns workspace layout with member packages',
      () async {
        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('workspace'));

        expect(layout.rootPath, equals(d.path('workspace')));
        expect(layout.isWorkspace, isTrue);
        expect(layout.packages, hasLength(2));

        final names = layout.packages.map((p) => p.name).toSet();
        expect(names, containsAll(['app', 'shared']));
      },
    );

    test(
      'when resolving then all members share the root package_config.json path',
      () async {
        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('workspace'));

        final expectedConfig = p.join(
          d.path('workspace'),
          '.dart_tool',
          'package_config.json',
        );
        for (final pkg in layout.packages) {
          expect(pkg.packageConfigPath, equals(expectedConfig));
        }
      },
    );

    test(
      'when root has a meaningful name then it is not included as a member package',
      () async {
        // Root name is '_' which is the placeholder convention
        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('workspace'));

        expect(layout.packages.map((p) => p.name), isNot(contains('_')));
      },
    );
  });

  group('Given a Dart pub workspace with a non-placeholder root name', () {
    test('when resolving then root package is included', () async {
      await d.dir('named_workspace', [
        d.file('pubspec.yaml', '''
name: my_monorepo
publish_to: none
environment:
  sdk: ^3.11.0
workspace:
  - packages/lib_a
'''),
        d.dir('packages', [
          d.dir('lib_a', [
            d.file('pubspec.yaml', '''
name: lib_a
environment:
  sdk: ^3.11.0
resolution: workspace
'''),
          ]),
        ]),
      ]).create();

      const resolver = WorkspaceResolver();
      final layout = await resolver.resolve(d.path('named_workspace'));

      expect(
        layout.packages.map((p) => p.name),
        containsAll(['my_monorepo', 'lib_a']),
      );
    });
  });

  group('Given a melos project with melos.yaml', () {
    setUp(() async {
      await d.dir('melos_project', [
        d.file('pubspec.yaml', '''
name: melos_root
environment:
  sdk: ^3.11.0
'''),
        d.file('melos.yaml', '''
name: melos_root
packages:
  - packages/*
'''),
        d.dir('packages', [
          d.dir('client', [
            d.file('pubspec.yaml', '''
name: client
environment:
  sdk: ^3.11.0
'''),
          ]),
          d.dir('server', [
            d.file('pubspec.yaml', '''
name: server
environment:
  sdk: ^3.11.0
'''),
          ]),
        ]),
      ]).create();
    });

    test('when resolving then detects melos workspace with members', () async {
      const resolver = WorkspaceResolver();
      final layout = await resolver.resolve(d.path('melos_project'));

      expect(layout.rootPath, equals(d.path('melos_project')));
      expect(layout.isWorkspace, isTrue);
      expect(layout.packages, hasLength(2));

      final names = layout.packages.map((p) => p.name).toSet();
      expect(names, containsAll(['client', 'server']));
    });

    test(
      'when resolving then each member has its own package_config.json path',
      () async {
        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('melos_project'));

        for (final pkg in layout.packages) {
          expect(
            pkg.packageConfigPath,
            equals(p.join(pkg.path, '.dart_tool', 'package_config.json')),
          );
        }
      },
    );
  });

  group('Given a melos project with config in pubspec.yaml', () {
    test(
      'when pubspec has melos section then detects member packages',
      () async {
        await d.dir('melos_in_pubspec', [
          d.file('pubspec.yaml', '''
name: my_root
environment:
  sdk: ^3.11.0
melos:
  packages:
    - packages/*
'''),
          d.dir('packages', [
            d.dir('pkg_a', [
              d.file('pubspec.yaml', '''
name: pkg_a
environment:
  sdk: ^3.11.0
'''),
            ]),
            d.dir('pkg_b', [
              d.file('pubspec.yaml', '''
name: pkg_b
environment:
  sdk: ^3.11.0
'''),
            ]),
          ]),
        ]).create();

        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('melos_in_pubspec'));

        expect(layout.isWorkspace, isTrue);
        final names = layout.packages.map((p) => p.name).toSet();
        expect(names, containsAll(['pkg_a', 'pkg_b']));
      },
    );
  });

  group('Given a melos project with ignore patterns', () {
    test('when resolving then ignored packages are excluded', () async {
      await d.dir('melos_ignore', [
        d.file('pubspec.yaml', '''
name: root
environment:
  sdk: ^3.11.0
'''),
        d.file('melos.yaml', '''
name: root
packages:
  - packages/*
ignore:
  - packages/internal
'''),
        d.dir('packages', [
          d.dir('public', [
            d.file('pubspec.yaml', '''
name: public
environment:
  sdk: ^3.11.0
'''),
          ]),
          d.dir('internal', [
            d.file('pubspec.yaml', '''
name: internal
environment:
  sdk: ^3.11.0
'''),
          ]),
        ]),
      ]).create();

      const resolver = WorkspaceResolver();
      final layout = await resolver.resolve(d.path('melos_ignore'));

      expect(layout.packages, hasLength(1));
      expect(layout.packages.first.name, equals('public'));
    });
  });

  group('Given a directory without any pubspec.yaml in tree', () {
    test('when resolving then throws StateError', () async {
      await d.dir('empty_dir').create();

      const resolver = WorkspaceResolver();

      expect(
        () => resolver.resolve(d.path('empty_dir')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group(
    'Given a directory without pubspec.yaml but with Dart subdirectories',
    () {
      test(
        'when resolving then discovers packages in immediate subdirectories',
        () async {
          await d.dir('implicit_mono', [
            d.dir('server', [
              d.file('pubspec.yaml', '''
name: my_server
environment:
  sdk: ^3.11.0
'''),
            ]),
            d.dir('client', [
              d.file('pubspec.yaml', '''
name: my_client
environment:
  sdk: ^3.11.0
'''),
            ]),
            d.dir('docs', [d.file('index.html', '<html></html>')]),
          ]).create();

          const resolver = WorkspaceResolver();
          final layout = await resolver.resolve(d.path('implicit_mono'));

          expect(
            layout.rootPath,
            equals(p.canonicalize(d.path('implicit_mono'))),
          );
          expect(layout.packages, hasLength(2));

          final names = layout.packages.map((pkg) => pkg.name).toSet();
          expect(names, equals({'my_client', 'my_server'}));

          for (final pkg in layout.packages) {
            expect(
              pkg.packageConfigPath,
              equals(p.join(pkg.path, '.dart_tool', 'package_config.json')),
            );
          }
        },
      );
    },
  );

  group(
    'Given a pub workspace where a member directory lacks pubspec.yaml',
    () {
      test('when resolving then that member is skipped', () async {
        await d.dir('partial_workspace', [
          d.file('pubspec.yaml', '''
name: _
publish_to: none
environment:
  sdk: ^3.11.0
workspace:
  - packages/valid
  - packages/no_pubspec
'''),
          d.dir('packages', [
            d.dir('valid', [
              d.file('pubspec.yaml', '''
name: valid_pkg
environment:
  sdk: ^3.11.0
'''),
            ]),
            d.dir('no_pubspec', [d.file('README.md', 'not a package')]),
          ]),
        ]).create();

        const resolver = WorkspaceResolver();
        final layout = await resolver.resolve(d.path('partial_workspace'));

        expect(layout.packages, hasLength(1));
        expect(layout.packages.first.name, equals('valid_pkg'));
      });
    },
  );
}
