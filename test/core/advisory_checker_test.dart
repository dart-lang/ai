import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:skills/src/core/advisory_checker.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  final logger = Logger('advisory_checker_test');
  test(
      'Given a dependency with vulterabilities, when '
      'AdvisoryChecker.checkAdvisories is called then those vulnerabilites '
      'are returned', () async {
    await d.dir('pkg1', [
      d.file('pubspec.yaml', 'name: pkg1\nversion: 1.0.0\n'),
    ]).create();
    await d.file('pubspec.lock', '''
packages:
  pkg1:
    source: hosted
    version: "1.0.0"
''').create();

    final packages = [
      ResolvedPackage(name: 'pkg1', rootPath: d.path('pkg1')),
    ];

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

    final result = await checker.checkAdvisories(packages, d.sandbox, logger);

    expect(result, contains('package:pkg1'));
    expect(result['package:pkg1'],
        contains('https://osv.dev/vulnerability/GHSA-1'));
  });

  test(
      'Given a project with no vulnerabilities, when '
      'AdvisoryChecker.checkAdvisories is called then an empty result is '
      'returned', () async {
    await d.dir('pkg1', [
      d.file('pubspec.yaml', 'name: pkg1\nversion: 1.0.0\n'),
    ]).create();

    final packages = [
      ResolvedPackage(name: 'pkg1', rootPath: d.path('pkg1')),
    ];

    final checker = AdvisoryChecker(
      httpClient: MockClient((_) async => http.Response(
          jsonEncode({
            'results': [
              {'vulns': []}
            ]
          }),
          HttpStatus.ok)),
    );

    final result = await checker.checkAdvisories(packages, d.sandbox, logger);

    expect(result, isEmpty);
  });

  test(
      'Given a network error when quering AdvisoryChecker.checkAdvisories, '
      'then it returns an empty list', () async {
    await d.dir('pkg1', [
      d.file('pubspec.yaml', 'name: pkg1\nversion: 1.0.0\n'),
    ]).create();

    final packages = [
      ResolvedPackage(name: 'pkg1', rootPath: d.path('pkg1')),
    ];

    final checker = AdvisoryChecker(
      httpClient: MockClient((request) async {
        return http.Response('', HttpStatus.forbidden);
      }),
    );

    final result = await checker.checkAdvisories(packages, d.sandbox, logger);

    expect(result, isEmpty);
  });

  test(
      'Given some git dependencies when AdvisoryChecker.checkAdvisories is'
      'called then it queries by commit found in the pubspec.lock', () async {
    await d.dir('pkg1', [
      d.file('pubspec.yaml', 'name: pkg1\nversion: 1.0.0\n'),
    ]).create();

    final packages = [
      ResolvedPackage(name: 'pkg1', rootPath: d.path('pkg1')),
    ];

    final lockFileContent = '''
packages:
  pkg1:
    dependency: direct main
    description:
      name: pkg1
      url: "https://github.com/foo/bar.git"
      resolved-ref: "commit123"
    source: git
    version: "1.0.0"
''';

    await d.file('pubspec.lock', lockFileContent).create();

    final checker = AdvisoryChecker(
      httpClient: MockClient((request) async {
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
