import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/migration.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:skills/src/core/registry_repos.dart';
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
      globalConfigPath =
          p.join(d.path('global_config_dir'), 'global_config.json');
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport();
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    group('Given a version 1 manifest and existing local repos', () {
      test(
          'when user selects to keep globally then moves to global config '
          'and renames directory', () async {
        const manifest = SkillManifest(version: 1);
        fakeDialogSupport.singleSelectResult =
            0; // Select 'keep this installed globally'

        final updatedManifest = await maybeDoRegistryMigration(
            projectPath, manifest, fakeDialogSupport);

        expect(updatedManifest.version, equals(1));
        final globalConfig =
            await GlobalConfig.loadOrEmpty(File(globalConfigPath));
        expect(globalConfig.registries, hasLength(1));
        expect(globalConfig.registries.first.cloneUrl,
            equals('https://github.com/owner1/repo1.git'));

        final oldRepoDir = Directory(p.join(
            projectPath, SkillManifest.dirName, 'repos', 'owner1', 'repo1'));
        expect(await oldRepoDir.exists(), isFalse);

        final newRepoDir = Directory(p.join(
            projectPath,
            SkillManifest.dirName,
            'repos',
            Uri.encodeComponent('https://github.com/owner1/repo1.git')));
        expect(await newRepoDir.exists(), isTrue);
      });

      test('when user selects to keep locally then moves to local config',
          () async {
        const manifest = SkillManifest(version: 1);
        fakeDialogSupport.singleSelectResult =
            1; // Select 'keep this installed for this project'

        final updatedManifest = await maybeDoRegistryMigration(
            projectPath, manifest, fakeDialogSupport);

        expect(updatedManifest.version, equals(1));
        final globalConfig =
            await GlobalConfig.loadOrEmpty(File(globalConfigPath));
        expect(globalConfig.registries, isEmpty);
        expect(updatedManifest.registries, hasLength(1));
        expect(updatedManifest.registries.first.cloneUrl,
            equals('https://github.com/owner1/repo1.git'));
      });

      test(
          'when user selects to remove then deletes from disk and does not add to config',
          () async {
        const manifest = SkillManifest(version: 1);
        fakeDialogSupport.singleSelectResult =
            2; // Select 'remove this registry'

        final updatedManifest = await maybeDoRegistryMigration(
            projectPath, manifest, fakeDialogSupport);

        expect(updatedManifest.version, equals(1));
        final globalConfig =
            await GlobalConfig.loadOrEmpty(File(globalConfigPath));
        expect(globalConfig.registries, isEmpty);
        expect(updatedManifest.registries, isEmpty);

        final repoDir = Directory(p.join(
            projectPath, SkillManifest.dirName, 'repos', 'owner1', 'repo1'));
        expect(await repoDir.exists(), isFalse);
      });

      test('when no dialog support then keeps repos local', () async {
        const manifest = SkillManifest(version: 1);

        final updatedManifest =
            await maybeDoRegistryMigration(projectPath, manifest, null);

        expect(updatedManifest.version, equals(1));

        final globalConfig =
            await GlobalConfig.loadOrEmpty(File(globalConfigPath));
        expect(globalConfig.registries, isEmpty);

        expect(updatedManifest.registries, hasLength(1));
        expect(updatedManifest.registries.first.cloneUrl,
            equals('https://github.com/owner1/repo1.git'));
      });
    });

    test(
        'Given a version 2 manifest, when running migration then does nothing '
        'and returns same instance', () async {
      const manifest = SkillManifest(version: 2);

      final updatedManifest = await maybeDoRegistryMigration(
          projectPath, manifest, fakeDialogSupport);

      expect(updatedManifest, equals(manifest));
      final globalConfig =
          await GlobalConfig.loadOrEmpty(File(globalConfigPath));
      expect(globalConfig.registries, isEmpty);
    });

    test(
        'Given a version 1 manifest and repos already in global config, when '
        'running migration then skips them and does not prompt', () async {
      const manifest = SkillManifest(version: 1);

      var globalConfig = const GlobalConfig();
      globalConfig = globalConfig.withRegistry(
          const RegistryRepo(cloneUrl: 'https://github.com/owner1/repo1.git'));
      await globalConfig.save(File(globalConfigPath));

      fakeDialogSupport.singleSelectResult = null; // Should not prompt

      final updatedManifest = await maybeDoRegistryMigration(
          projectPath, manifest, fakeDialogSupport);

      expect(updatedManifest.version, equals(1));
      expect(fakeDialogSupport.lastSingleSelectOptions, isNull);
    });

    test(
        'Given a version 1 manifest and global config already exists, when '
        'running migration then it still runs and prompts for new repos',
        () async {
      const manifest = SkillManifest(version: 1);

      await const GlobalConfig().save(File(globalConfigPath));

      fakeDialogSupport.singleSelectResult =
          0; // Select 'keep this installed globally'

      final updatedManifest = await maybeDoRegistryMigration(
          projectPath, manifest, fakeDialogSupport);

      expect(updatedManifest.version, equals(1));
      final globalConfig =
          await GlobalConfig.loadOrEmpty(File(globalConfigPath));
      expect(globalConfig.registries, hasLength(1));
    });
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
      globalConfigPath =
          p.join(d.path('global_config_dir'), 'global_config.json');
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport();
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    test(
        'Given an old .dart_skills dir when running migrations '
        'should first migrate both the manifest and registries', () async {
      fakeDialogSupport.singleSelectResult = 0; // Keep globally

      await runMigrations(projectPath, fakeDialogSupport);

      // Check directory migrated
      final oldDir = Directory(p.join(projectPath, '.dart_skills'));
      expect(await oldDir.exists(), isFalse);

      final newDir = Directory(p.join(projectPath, '.dart_tool', 'skills'));
      expect(await newDir.exists(), isTrue);

      // Check registry migrated to global config
      final globalConfig =
          await GlobalConfig.loadOrEmpty(File(globalConfigPath));
      expect(globalConfig.registries, hasLength(1));
      expect(globalConfig.registries.first.cloneUrl,
          equals('https://github.com/owner1/repo1.git'));

      // Check manifest updated to current version
      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest!.version, equals(SkillManifest.currentVersion));

      // Check the repo has been moved to the new location
      final oldRepoDir = Directory(p.join(
          projectPath, SkillManifest.dirName, 'repos', 'owner1', 'repo1'));
      expect(await oldRepoDir.exists(), isFalse);

      final newRepoDir = Directory(p.join(projectPath, SkillManifest.dirName,
          'repos', Uri.encodeComponent('https://github.com/owner1/repo1.git')));
      expect(await newRepoDir.exists(), isTrue);
    });
  });
}
