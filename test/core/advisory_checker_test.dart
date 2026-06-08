import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/advisory_checker.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  final logger = Logger('advisory_checker_test');
  late List<ResolvedPackage> packages;

  group('Given a single package', () {
    setUp(() async {
      await d.dir('pkg1', [
        d.file('pubspec.yaml', 'name: pkg1\nversion: 1.0.0\n'),
      ]).create();

      packages = [
        ResolvedPackage(
            name: 'pkg1',
            rootPath: d.path('pkg1'),
            originalPackageConfigPath:
                d.path(p.join('.dart_tool', 'package_config.json'))),
      ];
    });

    group('as a hosted dependency', () {
      setUp(() async {
        await d.file('pubspec.lock', '''
packages:
  pkg1:
    source: hosted
    version: "1.0.0"
''').create();
      });

      test(
          'and some vulnerabilities, when AdvisoryChecker.checkAdvisories '
          'is called then those vulnerabilities are returned', () async {
        final checker = AdvisoryChecker(
          httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'results': [
                  {
                    'vulns': [
                      {'id': 'GHSA-1'},
                    ]
                  }
                ]
              }),
              HttpStatus.ok)),
        );

        final result =
            await checker.checkAdvisories(packages, d.sandbox, logger);

        expect(result, contains('package:pkg1'));
        expect(result['package:pkg1'],
            contains('https://osv.dev/vulnerability/GHSA-1'));
      });

      test(
          'no vulnerabilities, when AdvisoryChecker.checkAdvisories is called '
          'then an empty result is returned', () async {
        final checker = AdvisoryChecker(
          httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'results': [
                  {'vulns': []}
                ]
              }),
              HttpStatus.ok)),
        );

        final result =
            await checker.checkAdvisories(packages, d.sandbox, logger);

        expect(result, isEmpty);
      });

      test(
          'and a network error when querying AdvisoryChecker.checkAdvisories '
          'then it returns an empty list', () async {
        final checker = AdvisoryChecker(
          httpClient: MockClient((request) async {
            return http.Response('', HttpStatus.forbidden);
          }),
        );

        final result =
            await checker.checkAdvisories(packages, d.sandbox, logger);

        expect(result, isEmpty);
      });
    });

    group('as a git dependency', () {
      setUp(() async {
        await d.file('pubspec.lock', '''
packages:
  pkg1:
    dependency: direct main
    description:
      name: pkg1
      url: "https://github.com/foo/bar.git"
      resolved-ref: "commit123"
    source: git
    version: "1.0.0"
''').create();
      });

      test(
          'when AdvisoryChecker.checkAdvisories is called then it queries by '
          'commit found in the pubspec.lock', () async {
        var wasCalled = false;
        final checker = AdvisoryChecker(
          httpClient: MockClient((request) async {
            wasCalled = true;
            expect(request.body, contains('"commit":"commit123"'));
            return http.Response(
                jsonEncode({
                  'results': [
                    {'vulns': []}
                  ]
                }),
                HttpStatus.ok);
          }),
        );

        await checker.checkAdvisories(packages, d.sandbox, logger);
        expect(wasCalled, true);
      });
    });
  });

  group('Given multiple packages from different version solves', () {
    setUp(() async {
      await d.dir('pkg1', [
        d.file('pubspec.yaml', 'name: pkg1\nversion: 1.0.0\n'),
      ]).create();
      await d.dir('pkg2', [
        d.file('pubspec.yaml', 'name: pkg2\nversion: 2.0.0\n'),
      ]).create();
      await d.dir('project1', [
        d.file('pubspec.lock', '''
packages:
  pkg1:
    source: hosted
    version: "1.0.0"
''')
      ]).create();
      await d.dir('project2', [
        d.file('pubspec.lock', '''
packages:
  pkg2:
    source: hosted
    version: "2.0.0"
''')
      ]).create();

      packages = [
        ResolvedPackage(
            name: 'pkg1',
            rootPath: d.path('pkg1'),
            originalPackageConfigPath: d
                .path(p.join('project1', '.dart_tool', 'package_config.json'))),
        ResolvedPackage(
            name: 'pkg2',
            rootPath: d.path('pkg1'),
            originalPackageConfigPath: d
                .path(p.join('project2', '.dart_tool', 'package_config.json'))),
      ];
    });

    test('each package is resolved against the proper pubspec.lock', () async {
      var wasCalled = false;
      final checker = AdvisoryChecker(
        httpClient: MockClient((request) async {
          wasCalled = true;
          final json = jsonDecode(request.body) as Map<String, Object?>;
          final query = json['queries'] as List<Object?>;
          expect(
              query,
              unorderedMatches([
                isA<Map>()
                    .having((request) => request['package']['name'] as String,
                        'name', 'pkg1')
                    .having((request) => request['version'] as String,
                        'version', '1.0.0'),
                isA<Map>()
                    .having((request) => request['package']['name'] as String,
                        'name', 'pkg2')
                    .having((request) => request['version'] as String,
                        'version', '2.0.0')
              ]));
          return http.Response(
              jsonEncode({
                'results': [
                  {'vulns': []}
                ]
              }),
              HttpStatus.ok);
        }),
      );

      await checker.checkAdvisories(packages, d.sandbox, logger);
      expect(wasCalled, isTrue);
    });
  });

  test(
      'Given some git registries when AdvisoryChecker.checkAdvisories is '
      'called then it queries by the current registry commit hash', () async {
    final checker = AdvisoryChecker(httpClient: MockClient((request) async {
      expect(request.body, contains('"commit":"commit456"'));
      return http.Response(
          jsonEncode({
            'results': [
              {'vulns': []}
            ]
          }),
          HttpStatus.ok);
    }));

    await checker.checkAdvisories(
      [],
      d.sandbox,
      logger,
      registryRepoCommits: {'owner/repo': 'commit456'},
    );
  });
}
