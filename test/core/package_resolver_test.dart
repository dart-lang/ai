import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Given a project with a valid package_config.json', () {
    late String projectPath;

    setUp(() async {
      await d.dir('dep_a', [pubspec('dep_a')]).create();
      await d.dir('dep_b', [pubspec('dep_b')]).create();

      await d.dir('project', [
        pubspec('project', dependencies: [.new('dep_a'), .new('dep_b')]),
      ]).create();

      projectPath = d.path('project');
      await Process.run('dart', ['pub', 'get'], workingDirectory: projectPath);
    });

    test('when resolving all packages then returns both', () async {
      final resolver = PackageResolver(projectPath);
      final packages = await resolver.resolve();

      expect(
        packages.map((p) => p.name).toSet(),
        containsAll(['dep_a', 'dep_b']),
      );
      for (final package in packages) {
        expect(
          package.originalPackageConfigPath,
          equals(
            d.path(p.join('project', '.dart_tool', 'package_config.json')),
          ),
        );
      }
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

  group('Given a workspace layout', () {
    test('when resolveWorkspace is called it merges dependencies and ignores '
        'members', () async {
      await d.dir('dep_x', [pubspec('dep_x')]).create();
      await d.dir('dep_y', [pubspec('dep_y')]).create();

      await d.dir('workspace', [
        pubspec('pkg_a', dependencies: [.new('dep_x')]),
        d.dir('pkg_b', [
          pubspec(
            'pkg_b',
            dependencies: [
              .new('dep_x', path: '../../dep_x'),
              .new('dep_y', path: '../../dep_y'),
            ],
          ),
        ]),
      ]).create();

      final workspacePath = d.path('workspace');
      final pkgBPath = d.path(p.join('workspace', 'pkg_b'));

      await Process.run('dart', [
        'pub',
        'get',
      ], workingDirectory: workspacePath);
      await Process.run('dart', ['pub', 'get'], workingDirectory: pkgBPath);

      final layout = WorkspaceLayout(
        rootPath: workspacePath,
        packages: [
          WorkspacePackage(
            name: 'pkg_a',
            path: workspacePath,
            packageConfigPath: d.path(
              p.join('workspace', '.dart_tool', 'package_config.json'),
            ),
          ),
          WorkspacePackage(
            name: 'pkg_b',
            path: pkgBPath,
            packageConfigPath: d.path(
              p.join('workspace', 'pkg_b', '.dart_tool', 'package_config.json'),
            ),
          ),
        ],
      );

      final packages = await PackageResolver.resolveWorkspace(layout);

      final names = packages.map((p) => p.name).toSet();
      expect(names, equals({'dep_x', 'dep_y'}));

      final depX = packages.firstWhere((pkg) => pkg.name == 'dep_x');
      expect([
        d.path(p.join('workspace', '.dart_tool', 'package_config.json')),
        d.path(
          p.join('workspace', 'pkg_b', '.dart_tool', 'package_config.json'),
        ),
      ], contains(depX.originalPackageConfigPath));

      final depY = packages.firstWhere((pkg) => pkg.name == 'dep_y');
      expect(
        depY.originalPackageConfigPath,
        equals(
          d.path(
            p.join('workspace', 'pkg_b', '.dart_tool', 'package_config.json'),
          ),
        ),
      );
    });

    test('when resolving a specific package from workspace then returns only '
        'that one', () async {
      await d.dir('dep_z', [pubspec('dep_z')]).create();

      await d.dir('workspace2', [
        pubspec('pkg_a', dependencies: [.new('dep_z')]),
      ]).create();

      final workspacePath = d.path('workspace2');
      await Process.run('dart', [
        'pub',
        'get',
      ], workingDirectory: workspacePath);

      final layout = WorkspaceLayout(
        rootPath: workspacePath,
        packages: [
          WorkspacePackage(
            name: 'pkg_a',
            path: workspacePath,
            packageConfigPath: d.path(
              p.join('workspace2', '.dart_tool', 'package_config.json'),
            ),
          ),
        ],
      );

      final packages = await PackageResolver.resolveWorkspace(
        layout,
        packageNames: {'dep_z'},
      );
      expect(packages, hasLength(1));
      expect(packages.first.name, equals('dep_z'));

      final packages2 = await PackageResolver.resolveWorkspace(
        layout,
        packageNames: {'no_such_pkg'},
      );
      expect(packages2, isEmpty);
    });

    test(
      'when multiple versions of the same package exist then preserves both based on path',
      () async {
        final depMV1 = d.dir('dep_m_v1', [pubspec('dep_m')]);
        await depMV1.create();

        final depMV2 = d.dir('dep_m_v2', [pubspec('dep_m')]);
        await depMV2.create();

        await d.dir('workspace3', [
          pubspec('pkg_a', dependencies: [.new('dep_m', path: '../dep_m_v1')]),
          d.dir('pkg_b', [
            pubspec(
              'pkg_b',
              dependencies: [.new('dep_m', path: '../../dep_m_v2')],
            ),
          ]),
        ]).create();

        final workspacePath = d.path('workspace3');
        final pkgBPath = d.path(p.join('workspace3', 'pkg_b'));

        await Process.run('dart', [
          'pub',
          'get',
        ], workingDirectory: workspacePath);
        await Process.run('dart', ['pub', 'get'], workingDirectory: pkgBPath);

        final layout = WorkspaceLayout(
          rootPath: workspacePath,
          packages: [
            WorkspacePackage(
              name: 'pkg_a',
              path: workspacePath,
              packageConfigPath: d.path(
                p.join('workspace3', '.dart_tool', 'package_config.json'),
              ),
            ),
            WorkspacePackage(
              name: 'pkg_b',
              path: pkgBPath,
              packageConfigPath: d.path(
                p.join(
                  'workspace3',
                  'pkg_b',
                  '.dart_tool',
                  'package_config.json',
                ),
              ),
            ),
          ],
        );

        final packages = await PackageResolver.resolveWorkspace(layout);

        final mPackages = packages.where((pkg) => pkg.name == 'dep_m').toList();
        expect(mPackages, hasLength(2));

        final paths = mPackages.map((pkg) => p.normalize(pkg.rootPath)).toSet();
        expect(paths, containsAll([depMV1.io.path, depMV2.io.path]));
      },
    );

    test(
      'when a package is a transitive dependency then it is skipped',
      () async {
        await d.dir('dep_transitive', [pubspec('dep_transitive')]).create();
        await d.dir('pkg_c', [
          pubspec('pkg_c', dependencies: [.new('dep_transitive')]),
        ]).create();

        await d.dir('workspace4', [
          pubspec('pkg_a', dependencies: [.new('pkg_c')]),
        ]).create();

        final workspacePath = d.path('workspace4');
        await Process.run('dart', [
          'pub',
          'get',
        ], workingDirectory: workspacePath);

        final layout = WorkspaceLayout(
          rootPath: workspacePath,
          packages: [
            WorkspacePackage(
              name: 'pkg_a',
              path: workspacePath,
              packageConfigPath: d.path(
                p.join('workspace4', '.dart_tool', 'package_config.json'),
              ),
            ),
          ],
        );

        final packages = await PackageResolver.resolveWorkspace(layout);
        final names = packages.map((pkg) => pkg.name).toSet();

        expect(names, isNot(contains('dep_transitive')));
        expect(
          names,
          equals({'pkg_c'}),
        ); // pkg_c is a direct dependency, dep_transitive is transitive
      },
    );
  });

  group('Given a project without package_config.json', () {
    test('when resolving then throws StateError', () async {
      await d.dir('no_config_project').create();

      final resolver = PackageResolver(d.path('no_config_project'));
      expect(() => resolver.resolve(), throwsA(isA<StateError>()));
    });
  });
}
