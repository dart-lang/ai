import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a single-package project', () {
    test(
      'when resolving then returns one package pointing at project root',
      () async {
        await d.dir('my_project', [pubspec('my_project')]).create();

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
        pubspec('_', workspace: ['my_pkg']),
        d.dir('my_pkg', [pubspec('my_pkg', resolution: 'workspace')]),
      ]).create();
    });

    test('when resolving the single package then uses the workspace '
        'package_config.json path', () async {
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
    });

    test('when workspace root is not found then throws StateError', () async {
      await d.dir('isolated_pkg', [
        pubspec('isolated_pkg', resolution: 'workspace'),
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
        pubspec(
          '_',
          publishTo: 'none',
          workspace: ['packages/app', 'packages/shared'],
        ),
        d.dir('packages', [
          d.dir('app', [pubspec('app', resolution: 'workspace')]),
          d.dir('shared', [pubspec('shared', resolution: 'workspace')]),
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
        pubspec(
          'my_monorepo',
          publishTo: 'none',
          workspace: ['packages/lib_a'],
        ),
        d.dir('packages', [
          d.dir('lib_a', [pubspec('lib_a', resolution: 'workspace')]),
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
        pubspec('melos_root'),
        d.file('melos.yaml', '''
name: melos_root
packages:
  - packages/*
'''),
        d.dir('packages', [
          d.dir('client', [pubspec('client')]),
          d.dir('server', [pubspec('server')]),
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
          pubspec(
            'my_root',
            extra: '''
melos:
  packages:
    - packages/*
''',
          ),
          d.dir('packages', [
            d.dir('pkg_a', [pubspec('pkg_a')]),
            d.dir('pkg_b', [pubspec('pkg_b')]),
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
        pubspec('root'),
        d.file('melos.yaml', '''
name: root
packages:
  - packages/*
ignore:
  - packages/internal
'''),
        d.dir('packages', [
          d.dir('public', [pubspec('public')]),
          d.dir('internal', [pubspec('internal')]),
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
            d.dir('server', [pubspec('my_server')]),
            d.dir('client', [pubspec('my_client')]),
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
          pubspec(
            '_',
            publishTo: 'none',
            workspace: ['packages/valid', 'packages/no_pubspec'],
          ),
          d.dir('packages', [
            d.dir('valid', [pubspec('valid_pkg')]),
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
