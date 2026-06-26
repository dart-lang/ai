import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/migration.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/core/exceptions.dart';
import '../fake_dialog_support.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('Registry migration', () {
    late String projectPath;
    late String globalConfigPath;
    late FakeDialogSupport fakeDialogSupport;

    setUp(() async {
      await d.dir('project', [
        d.file('pubspec.lock', '''
packages:
  pkg_a:
    dependency: "direct main"
'''),
        d.dir('.dart_tool', [
          d.dir('skills', [
            d.dir('repos', [
              d.dir('owner1', [
                d.dir('repo1', [
                  d.dir('skills', [
                    d.dir('pkg-a', [d.file('SKILL.md', '')]),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]).create();
      projectPath = d.path('project');

      await d.dir('global_config_dir', []).create();
      globalConfigPath = p.join(
        d.path('global_config_dir'),
        'global_config.json',
      );
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport();
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    group('Given a version 1 manifest and existing local repos', () {
      test('when user selects to keep globally then moves to global config '
          'and renames directory', () async {
        var manifest = const SkillManifest(version: 1);
        manifest = manifest.withSourceUri(
          'generic',
          'pkg-a',
          SkillsEntry(
            skills: [
              InstalledSkillEntry(
                name: 'pkg-a',
                installedAt: DateTime.now().toUtc(),
              ),
            ],
          ),
        );

        fakeDialogSupport.singleSelectResults.add(
          0,
        ); // Select 'keep this installed globally'

        manifest = maybeMigratePackageUris(manifest);
        final updatedManifest = await maybeDoRegistryMigration(
          projectPath,
          manifest,
          fakeDialogSupport,
        );

        expect(updatedManifest.version, equals(1));
        final globalConfig = await GlobalConfig.loadOrEmpty(
          File(globalConfigPath),
        );
        expect(globalConfig.gitRepos, hasLength(1));
        expect(
          globalConfig.gitRepos.first.cloneUrl,
          equals('https://github.com/owner1/repo1.git'),
        );

        final oldRepoDir = Directory(
          p.join(projectPath, '.dart_skills', 'repos', 'owner1', 'repo1'),
        );
        expect(await oldRepoDir.exists(), isFalse);

        final newRepoDir = Directory(
          p.join(
            projectPath,
            SkillManifest.cacheDirPath,
            'repos',
            Uri.encodeComponent('https://github.com/owner1/repo1.git'),
          ),
        );
        expect(await newRepoDir.exists(), isTrue);

        expect(
          updatedManifest.sourceUrisForIde('generic').containsKey('pkg-a'),
          isFalse,
        );
        expect(
          updatedManifest
              .sourceUrisForIde('generic')
              .containsKey('https://github.com/owner1/repo1.git'),
          isTrue,
        );
        expect(
          updatedManifest
              .sourceUrisForIde(
                'generic',
              )['https://github.com/owner1/repo1.git']!
              .skills
              .first
              .name,
          equals('pkg-a'),
        );
      });

      test(
        'when user selects to keep locally then moves to local config',
        () async {
          var manifest = SkillManifest(
            version: 1,
            installations: {
              'cursor': {
                'pkg-a': SkillsEntry(
                  skills: [
                    InstalledSkillEntry(
                      name: 'pkg-a',
                      installedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
                    ),
                  ],
                ),
                'pkg-b': SkillsEntry(
                  skills: [
                    InstalledSkillEntry(
                      name: 'pkg-b',
                      installedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
                    ),
                  ],
                ),
              },
            },
          ); // Select 'keep this installed for this project'

          fakeDialogSupport.singleSelectResults.add(1);
          manifest = maybeMigratePackageUris(manifest);
          final updatedManifest = await maybeDoRegistryMigration(
            projectPath,
            manifest,
            fakeDialogSupport,
          );

          expect(updatedManifest.version, equals(1));
          final globalConfig = await GlobalConfig.loadOrEmpty(
            File(globalConfigPath),
          );
          expect(globalConfig.gitRepos, isEmpty);
          expect(updatedManifest.gitRepos, hasLength(1));
          expect(
            updatedManifest.gitRepos.first.cloneUrl,
            equals('https://github.com/owner1/repo1.git'),
          );

          expect(
            updatedManifest.sourceUrisForIde('cursor').containsKey('pkg-a'),
            isFalse,
          );
          expect(
            updatedManifest
                .sourceUrisForIde('cursor')
                .containsKey('https://github.com/owner1/repo1.git'),
            isTrue,
          );
          expect(
            updatedManifest
                .sourceUrisForIde(
                  'cursor',
                )['https://github.com/owner1/repo1.git']!
                .skills
                .first
                .name,
            equals('pkg-a'),
          );
        },
      );

      test(
        'when user selects to remove then deletes from disk and does not add to config',
        () async {
          const manifest = SkillManifest(version: 1);
          fakeDialogSupport.singleSelectResults.add(
            2,
          ); // Select 'remove this registry'

          final updatedManifest = await maybeDoRegistryMigration(
            projectPath,
            manifest,
            fakeDialogSupport,
          );

          expect(updatedManifest.version, equals(1));
          final globalConfig = await GlobalConfig.loadOrEmpty(
            File(globalConfigPath),
          );
          expect(globalConfig.gitRepos, isEmpty);
          expect(updatedManifest.gitRepos, isEmpty);

          final repoDir = Directory(
            p.join(projectPath, '.dart_skills', 'repos', 'owner1', 'repo1'),
          );
          expect(await repoDir.exists(), isFalse);
        },
      );

      test('when user aborts dialog then throws UserAbortException', () async {
        var manifest = const SkillManifest(version: 1);

        fakeDialogSupport.singleSelectResults.add(null); // Abort dialog

        manifest = maybeMigratePackageUris(manifest);
        expect(
          () => maybeDoRegistryMigration(
            projectPath,
            manifest,
            fakeDialogSupport,
          ),
          throwsA(isA<UserAbortException>()),
        );
      });

      test(
        'when user selects to remove and uninstall then deletes from disk and '
        'uninstalls skills',
        () async {
          // Setup a skill in the manifest to uninstall
          var manifest = const SkillManifest(version: 1);
          manifest = manifest.withSourceUri(
            'generic',
            'https://github.com/owner1/repo1.git',
            SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg-a',
                  installedAt: DateTime.now().toUtc(),
                ),
              ],
            ),
          );
          manifest = SkillManifest(
            version: 1,
            installations: manifest.installations,
          );

          // Setup an installed skill on disk
          await d.dir('project', [
            d.dir('.agents', [
              d.dir('skills', [
                d.dir('pkg-a', [d.file('SKILL.md', '')]),
              ]),
            ]),
          ]).create();

          fakeDialogSupport.singleSelectResults.add(
            3,
          ); // Select 'remove this repository and uninstall its skills'

          manifest = maybeMigratePackageUris(manifest);
          final updatedManifest = await maybeDoRegistryMigration(
            projectPath,
            manifest,
            fakeDialogSupport,
          );

          expect(updatedManifest.version, equals(1));
          final globalConfig = await GlobalConfig.loadOrEmpty(
            File(globalConfigPath),
          );
          expect(globalConfig.gitRepos, isEmpty);
          expect(updatedManifest.gitRepos, isEmpty);

          final repoDir = Directory(
            p.join(projectPath, '.dart_skills', 'repos', 'owner1', 'repo1'),
          );
          expect(await repoDir.exists(), isFalse);

          // Check that the installed skill was deleted
          final installedSkillDir = Directory(
            p.join(projectPath, '.agents', 'skills', 'pkg-a'),
          );
          expect(await installedSkillDir.exists(), isFalse);

          // Check that the skill was removed from the manifest
          expect(updatedManifest.installations['generic'], isNull);
        },
      );

      test('when no dialog support then keeps repos local', () async {
        var manifest = SkillManifest(
          version: 1,
          installations: {
            'generic': {
              'pkg-a': SkillsEntry(
                skills: [
                  InstalledSkillEntry(
                    name: 'pkg-a',
                    installedAt: DateTime.now().toUtc(),
                  ),
                ],
              ),
            },
          },
        );

        manifest = maybeMigratePackageUris(manifest);
        final updatedManifest = await maybeDoRegistryMigration(
          projectPath,
          manifest,
          null,
        );

        expect(updatedManifest.version, equals(1));

        final globalConfig = await GlobalConfig.loadOrEmpty(
          File(globalConfigPath),
        );
        expect(globalConfig.gitRepos, isEmpty);

        expect(updatedManifest.gitRepos, hasLength(1));
        expect(
          updatedManifest.gitRepos.first.cloneUrl,
          equals('https://github.com/owner1/repo1.git'),
        );
      });
    });

    test('Given a version 2 manifest, when running migration then does nothing '
        'and returns same instance', () async {
      var manifest = const SkillManifest(version: 2);

      manifest = maybeMigratePackageUris(manifest);
      final updatedManifest = await maybeDoRegistryMigration(
        projectPath,
        manifest,
        fakeDialogSupport,
      );

      expect(updatedManifest, equals(manifest));
      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      expect(globalConfig.gitRepos, isEmpty);
    });

    test('Given a version 1 manifest and repos already in global config, when '
        'running migration then skips them and does not prompt', () async {
      var manifest = const SkillManifest(version: 1);

      var globalConfig = const GlobalConfig();
      globalConfig = globalConfig.withGitRepo(
        const GitRepo(cloneUrl: 'https://github.com/owner1/repo1.git'),
      );
      await globalConfig.save(File(globalConfigPath));

      manifest = maybeMigratePackageUris(manifest);
      final updatedManifest = await maybeDoRegistryMigration(
        projectPath,
        manifest,
        fakeDialogSupport,
      );

      expect(updatedManifest.version, equals(1));
      expect(fakeDialogSupport.singleSelectCallCount, 0);
    });

    test(
      'Given a version 1 manifest and global config already exists, when '
      'running migration then it still runs and prompts for new repos',
      () async {
        var manifest = const SkillManifest(version: 1);

        await const GlobalConfig().save(File(globalConfigPath));

        fakeDialogSupport.singleSelectResults.add(
          0,
        ); // Select 'keep this installed globally'

        manifest = maybeMigratePackageUris(manifest);
        final updatedManifest = await maybeDoRegistryMigration(
          projectPath,
          manifest,
          fakeDialogSupport,
        );

        expect(updatedManifest.version, equals(1));
        final globalConfig = await GlobalConfig.loadOrEmpty(
          File(globalConfigPath),
        );
        expect(globalConfig.gitRepos, hasLength(1));
      },
    );
  });

  group('runMigrations', () {
    late String projectPath;
    late String globalConfigPath;
    late FakeDialogSupport fakeDialogSupport;

    setUp(() async {
      await d.dir('project', [
        d.dir('.dart_skills', [
          d.dir('repos', [
            d.dir('owner1', [
              d.dir('repo1', [
                d.dir('skills', [
                  d.dir('pkg-a', [d.file('SKILL.md', '')]),
                ]),
              ]),
            ]),
          ]),
          d.file('skills_config.json', '{"version": 1}'),
        ]),
      ]).create();
      projectPath = d.path('project');

      await d.dir('global_config_dir', []).create();
      globalConfigPath = p.join(
        d.path('global_config_dir'),
        'global_config.json',
      );
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport();
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    test('Given an old .dart_skills dir when running migrations '
        'should first migrate both the manifest and registries', () async {
      fakeDialogSupport.singleSelectResults.add(0); // Keep globally

      await runMigrations(projectPath, fakeDialogSupport);

      // Check directory migrated
      final oldDir = Directory(p.join(projectPath, '.dart_skills'));
      expect(await oldDir.exists(), isFalse);

      final newDir = Directory(p.join(projectPath, '.dart_tool', 'skills'));
      expect(await newDir.exists(), isTrue);

      // Check registry migrated to global config
      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      expect(globalConfig.gitRepos, hasLength(1));
      expect(
        globalConfig.gitRepos.first.cloneUrl,
        equals('https://github.com/owner1/repo1.git'),
      );

      // Check manifest updated to current version
      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest!.version, equals(SkillManifest.currentVersion));

      // Check the repo has been moved to the new location
      final oldRepoDir = Directory(
        p.join(projectPath, '.dart_skills', 'repos', 'owner1', 'repo1'),
      );
      expect(await oldRepoDir.exists(), isFalse);

      final newRepoDir = Directory(
        p.join(
          projectPath,
          SkillManifest.cacheDirPath,
          'repos',
          Uri.encodeComponent('https://github.com/owner1/repo1.git'),
        ),
      );
      expect(await newRepoDir.exists(), isTrue);
    });
  });
}
