import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

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

      expect(
          packages.map((p) => p.name).toSet(), containsAll(['dep_a', 'dep_b']));
      for (final package in packages) {
        expect(
          package.originalPackageConfigPath,
          equals(
              d.path(p.join('project', '.dart_tool', 'package_config.json'))),
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
    test(
        'when resolveWorkspace is called it merges dependencies and ignores '
        'members', () async {
      await d.dir('workspace', [
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'pkg_a',
                  'rootUri': '../../pkg_a',
                  'packageUri': 'lib/',
                },
                {
                  'name': 'dep_x',
                  'rootUri': 'file://${d.path('dep_x')}/',
                  'packageUri': 'lib/',
                },
              ],
            }),
          ),
        ]),
        d.dir('pkg_b', [
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {
                    'name': 'pkg_b',
                    'rootUri': '../',
                    'packageUri': 'lib/',
                  },
                  {
                    'name': 'dep_x',
                    'rootUri': 'file://${d.path('dep_x')}/',
                    'packageUri': 'lib/',
                  },
                  {
                    'name': 'dep_y',
                    'rootUri': 'file://${d.path('dep_y')}/',
                    'packageUri': 'lib/',
                  },
                ],
              }),
            ),
          ]),
        ]),
      ]).create();

      await d.dir('dep_x', [
        d.dir('lib', [d.file('dep_x.dart', '')]),
      ]).create();

      await d.dir('dep_y', [
        d.dir('lib', [d.file('dep_y.dart', '')]),
      ]).create();

      final layout = WorkspaceLayout(
        rootPath: d.path('workspace'),
        packages: [
          WorkspacePackage(
            name: 'pkg_a',
            path: d.path(p.join('workspace', 'pkg_a')),
            packageConfigPath: d
                .path(p.join('workspace', '.dart_tool', 'package_config.json')),
          ),
          WorkspacePackage(
            name: 'pkg_b',
            path: d.path(p.join('workspace', 'pkg_b')),
            packageConfigPath: d.path(p.join(
                'workspace', 'pkg_b', '.dart_tool', 'package_config.json')),
          ),
        ],
      );

      final packages = await PackageResolver.resolveWorkspace(layout);

      final names = packages.map((p) => p.name).toSet();
      expect(names, equals({'dep_x', 'dep_y'}));

      final depX = packages.firstWhere((pkg) => pkg.name == 'dep_x');
      // Could be resolved from either package_config.json since both contain
      // dep_x
      expect(
        [
          d.path(p.join('workspace', '.dart_tool', 'package_config.json')),
          d.path(
              p.join('workspace', 'pkg_b', '.dart_tool', 'package_config.json'))
        ],
        contains(depX.originalPackageConfigPath),
      );

      final depY = packages.firstWhere((pkg) => pkg.name == 'dep_y');
      expect(
        depY.originalPackageConfigPath,
        equals(d.path(
            p.join('workspace', 'pkg_b', '.dart_tool', 'package_config.json'))),
      );
    });

    test(
        'when resolving a specific package from workspace then returns only '
        'that one', () async {
      await d.dir('workspace2', [
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'pkg_a',
                  'rootUri': '../../pkg_a',
                  'packageUri': 'lib/',
                },
                {
                  'name': 'dep_z',
                  'rootUri': 'file://${d.path('dep_z')}/',
                  'packageUri': 'lib/',
                },
              ],
            }),
          ),
        ]),
      ]).create();

      await d.dir('dep_z', [
        d.dir('lib', [d.file('dep_z.dart', '')]),
      ]).create();

      final layout = WorkspaceLayout(
        rootPath: d.path('workspace2'),
        packages: [
          WorkspacePackage(
            name: 'pkg_a',
            path: d.path(p.join('workspace2', 'pkg_a')),
            packageConfigPath: d.path(
                p.join('workspace2', '.dart_tool', 'package_config.json')),
          ),
        ],
      );

      final packages = await PackageResolver.resolveWorkspace(layout,
          packageNames: {'dep_z'});
      expect(packages, hasLength(1));
      expect(packages.first.name, equals('dep_z'));

      final packages2 = await PackageResolver.resolveWorkspace(layout,
          packageNames: {'no_such_pkg'});
      expect(packages2, isEmpty);
    });

    test(
        'when multiple versions of the same package exist then preserves both based on path',
        () async {
      final depMV1 = d.dir('dep_m_v1', [
        d.dir('lib', [d.file('dep_m.dart', '')]),
      ]);
      await depMV1.create();

      final depMV2 = d.dir('dep_m_v2', [
        d.dir('lib', [d.file('dep_m.dart', '')]),
      ]);
      await depMV2.create();
      await d.dir('workspace3', [
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'pkg_a',
                  'rootUri': '../../pkg_a',
                  'packageUri': 'lib/',
                },
                {
                  'name': 'dep_m',
                  'rootUri': '${depMV1.io.uri}/',
                  'packageUri': 'lib/',
                },
              ],
            }),
          ),
        ]),
        d.dir('pkg_b', [
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {
                    'name': 'pkg_b',
                    'rootUri': '../',
                    'packageUri': 'lib/',
                  },
                  {
                    'name': 'dep_m',
                    'rootUri': '${depMV2.io.uri}/',
                    'packageUri': 'lib/',
                  },
                ],
              }),
            ),
          ]),
        ]),
      ]).create();

      final layout = WorkspaceLayout(
        rootPath: d.path('workspace3'),
        packages: [
          WorkspacePackage(
            name: 'pkg_a',
            path: d.path(p.join('workspace3', 'pkg_a')),
            packageConfigPath: d.path(
                p.join('workspace3', '.dart_tool', 'package_config.json')),
          ),
          WorkspacePackage(
            name: 'pkg_b',
            path: d.path(p.join('workspace3', 'pkg_b')),
            packageConfigPath: d.path(p.join(
                'workspace3', 'pkg_b', '.dart_tool', 'package_config.json')),
          ),
        ],
      );

      final packages = await PackageResolver.resolveWorkspace(layout);

      final mPackages = packages.where((pkg) => pkg.name == 'dep_m').toList();
      expect(mPackages, hasLength(2));

      final paths = mPackages.map((pkg) => p.normalize(pkg.rootPath)).toSet();
      expect(paths, containsAll([depMV1.io.path, depMV2.io.path]));
    });
  });

  group('Given a project without package_config.json', () {
    test('when resolving then throws StateError', () async {
      await d.dir('no_config_project').create();

      final resolver = PackageResolver(d.path('no_config_project'));
      expect(() => resolver.resolve(), throwsA(isA<StateError>()));
    });
  });
}
