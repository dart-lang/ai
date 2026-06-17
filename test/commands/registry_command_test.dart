import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/registry_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  group('RegistryCommand', () {
    late String projectPath;
    late String globalConfigPath;
    late FakeDialogSupport fakeDialogSupport;
    late SkillsCommandRunner runner;

    setUp(() async {
      await d.dir('project', [
        pubspec('test_app'),
        d.dir('.dart_skills', []),
      ]).create();
      projectPath = d.path('project');

      await d.dir('global_config_dir', []).create();
      globalConfigPath = p.join(
        d.path('global_config_dir'),
        'global_config.json',
      );
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport();

      runner = SkillsCommandRunner(
        'skills',
        'Test',
        dialogSupport: fakeDialogSupport,
      )..addCommand(RegistryCommand(dialogSupport: fakeDialogSupport));
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    group('skills registry add', () {
      group('Given no flags', () {
        test(
          'when adding a registry and selecting Global then adds to global config',
          () async {
            fakeDialogSupport.singleSelectResults.add(0); // Select 'Global'

            await runner.run([
              '-C',
              projectPath,
              'registry',
              'add',
              'flutter/skills',
            ]);

            final globalConfig = await GlobalConfig.loadOrEmpty(
              File(globalConfigPath),
            );
            expect(globalConfig.registries, hasLength(1));
            expect(
              globalConfig.registries.first.cloneUrl,
              equals('https://github.com/flutter/skills.git'),
            );
          },
        );

        test(
          'when adding a registry and selecting Local then adds to local config',
          () async {
            fakeDialogSupport.singleSelectResults.add(1); // Select 'Local'

            await runner.run([
              '-C',
              projectPath,
              'registry',
              'add',
              'serverpod/skills-registry',
            ]);

            final manifest = await SkillManifest.loadOrEmpty(
              File(SkillManifest.pathIn(projectPath)),
            );
            expect(manifest.registries, hasLength(1));
            expect(
              manifest.registries.first.cloneUrl,
              equals('https://github.com/serverpod/skills-registry.git'),
            );
          },
        );
      });

      group('Given --global flag', () {
        test(
          'when adding a registry then adds to global config without prompting',
          () async {
            await runner.run([
              '-C',
              projectPath,
              'registry',
              'add',
              '--global',
              'flutter/skills',
            ]);

            final globalConfig = await GlobalConfig.loadOrEmpty(
              File(globalConfigPath),
            );
            expect(globalConfig.registries, hasLength(1));
          },
        );
      });

      group('Given --no-global flag', () {
        test(
          'when adding a registry then adds to local config without prompting',
          () async {
            await runner.run([
              '-C',
              projectPath,
              'registry',
              'add',
              '--no-global',
              'serverpod/skills-registry',
            ]);

            final manifest = await SkillManifest.loadOrEmpty(
              File(SkillManifest.pathIn(projectPath)),
            );
            expect(manifest.registries, hasLength(1));
          },
        );
      });

      group('Given a Git URI', () {
        test(
          'when adding a registry then parses and adds it correctly',
          () async {
            await runner.run([
              '-C',
              projectPath,
              'registry',
              'add',
              '--global',
              'https://github.com/dart-lang/skills.git',
            ]);

            final globalConfig = await GlobalConfig.loadOrEmpty(
              File(globalConfigPath),
            );
            expect(globalConfig.registries, hasLength(1));
            expect(
              globalConfig.registries.first.cloneUrl,
              equals('https://github.com/dart-lang/skills.git'),
            );
          },
        );
      });
    });

    group('skills registry list', () {
      group('Given global and local registries configured', () {
        test('when listing registries then both are printed', () async {
          var globalConfig = const GlobalConfig();
          globalConfig = globalConfig.withRegistry(
            const RegistryRepo(
              cloneUrl: 'https://github.com/g_owner/g_repo.git',
            ),
          );
          await globalConfig.save(File(globalConfigPath));

          var manifest = const SkillManifest();
          manifest = manifest.withRegistry(
            const RegistryRepo(
              cloneUrl: 'https://github.com/l_owner/l_repo.git',
            ),
          );
          await manifest.save(File(SkillManifest.pathIn(projectPath)));

          final logs = <String>[];
          final subscription = Logger.root.onRecord.listen((log) {
            logs.add(log.message);
          });

          await runner.run(['-C', projectPath, 'registry', 'list']);

          await subscription.cancel();

          expect(
            logs,
            contains(contains('https://github.com/g_owner/g_repo.git')),
          );
          expect(
            logs,
            contains(contains('https://github.com/l_owner/l_repo.git')),
          );
        });
      });
    });

    group('skills registry remove', () {
      group('Given a registry only in local config', () {
        test('when removing it then it is removed without prompting', () async {
          var manifest = const SkillManifest();
          const repo = RegistryRepo(
            cloneUrl: 'https://github.com/l_owner/l_repo.git',
          );
          manifest = manifest.withRegistry(repo);
          await manifest.save(File(SkillManifest.pathIn(projectPath)));

          await runner.run([
            '-C',
            projectPath,
            'registry',
            'remove',
            'https://github.com/l_owner/l_repo.git',
          ]);

          final updatedManifest = await SkillManifest.loadOrEmpty(
            File(SkillManifest.pathIn(projectPath)),
          );
          expect(updatedManifest.registries, isEmpty);
        });
      });

      group('Given a registry only in global config', () {
        test('when removing it then it is removed without prompting', () async {
          var globalConfig = const GlobalConfig();
          const repo = RegistryRepo(
            cloneUrl: 'https://github.com/g_owner/g_repo.git',
          );
          globalConfig = globalConfig.withRegistry(repo);
          await globalConfig.save(File(globalConfigPath));

          await runner.run([
            '-C',
            projectPath,
            'registry',
            'remove',
            'https://github.com/g_owner/g_repo.git',
          ]);

          final updatedGlobalConfig = await GlobalConfig.loadOrEmpty(
            File(globalConfigPath),
          );
          expect(updatedGlobalConfig.registries, isEmpty);
        });
      });

      group('Given a registry in both configs', () {
        test(
          'when removing it then prompts and removes from selected location',
          () async {
            const repo = RegistryRepo(
              cloneUrl: 'https://github.com/both_owner/both_repo.git',
            );

            var globalConfig = const GlobalConfig();
            globalConfig = globalConfig.withRegistry(repo);
            await globalConfig.save(File(globalConfigPath));

            var manifest = const SkillManifest();
            manifest = manifest.withRegistry(repo);
            await manifest.save(File(SkillManifest.pathIn(projectPath)));

            fakeDialogSupport.singleSelectResults.add(0); // Select 'Global'

            await runner.run([
              '-C',
              projectPath,
              'registry',
              'remove',
              'https://github.com/both_owner/both_repo.git',
            ]);

            final updatedGlobalConfig = await GlobalConfig.loadOrEmpty(
              File(globalConfigPath),
            );
            expect(updatedGlobalConfig.registries, isEmpty);

            final updatedManifest = await SkillManifest.loadOrEmpty(
              File(SkillManifest.pathIn(projectPath)),
            );
            expect(updatedManifest.registries, hasLength(1)); // Still in local
          },
        );
      });

      group('Given no arguments', () {
        test(
          'when running remove then shows multi-select and removes selected',
          () async {
            const repo1 = RegistryRepo(
              cloneUrl: 'https://github.com/owner1/repo1.git',
            );
            const repo2 = RegistryRepo(
              cloneUrl: 'https://github.com/owner2/repo2.git',
            );

            var globalConfig = const GlobalConfig();
            globalConfig = globalConfig.withRegistry(repo1);
            await globalConfig.save(File(globalConfigPath));

            var manifest = const SkillManifest();
            manifest = manifest.withRegistry(repo2);
            await manifest.save(File(SkillManifest.pathIn(projectPath)));

            fakeDialogSupport.multiSelectResults.add({
              0,
            }); // Select first option

            await runner.run(['-C', projectPath, 'registry', 'remove']);

            final updatedGlobalConfig = await GlobalConfig.loadOrEmpty(
              File(globalConfigPath),
            );
            expect(updatedGlobalConfig.registries, isEmpty);

            final updatedManifest = await SkillManifest.loadOrEmpty(
              File(SkillManifest.pathIn(projectPath)),
            );
            expect(updatedManifest.registries, hasLength(1)); // Still in local
          },
        );
      });

      group('Given a global registry with back-linked skills', () {
        test(
          'when removing it then deletes the back-linked skills from disk',
          () async {
            final skillPath = p.join(
              projectPath,
              '.cursor',
              'skills',
              'skill_a',
            );
            final repo = RegistryRepo(
              cloneUrl: 'https://github.com/g_owner/g_repo.git',
              installs: [skillPath],
            );

            var globalConfig = const GlobalConfig();
            globalConfig = globalConfig.withRegistry(repo);

            await d.dir('project', [
              pubspec('test_app'),
              d.dir('.dart_skills', []),
              d.dir('.cursor', [
                d.dir('skills', [
                  d.dir('skill_a', [d.file('SKILL.md', '')]),
                ]),
              ]),
            ]).create();

            await globalConfig.save(File(globalConfigPath));

            await runner.run([
              '-C',
              projectPath,
              'registry',
              'remove',
              'https://github.com/g_owner/g_repo.git',
            ]);

            final updatedGlobalConfig = await GlobalConfig.loadOrEmpty(
              File(globalConfigPath),
            );
            expect(updatedGlobalConfig.registries, isEmpty);

            expect(Directory(skillPath).existsSync(), isFalse);
          },
        );
      });
    });
  });
}
