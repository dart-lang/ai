import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:skills/src/commands/add_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:path/path.dart' as p;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  group('AddCommand', () {
    late String projectPath;
    late String globalConfigPath;
    late FakeDialogSupport fakeDialogSupport;
    late SkillsCommandRunner runner;

    setUp(() async {
      await d.dir('project', [pubspec('project')]).create();
      projectPath = d.path('project');

      await d.dir('global_config_dir', []).create();
      globalConfigPath = p.join(
        d.path('global_config_dir'),
        'global_config.json',
      );
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport();
      final addCommand = AddCommand(
        dialogSupport: fakeDialogSupport,
        gitRunner: GitRunner(isAvailableOverride: () async => false),
      );
      runner = SkillsCommandRunner('skills', 'Test')..addCommand(addCommand);
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    test('throws if no git repos provided', () async {
      expect(
        () =>
            runner.run(['add', '--directory', projectPath, '--ide', 'cursor']),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws if both --all and --skill are provided', () async {
      expect(
        () => runner.run([
          'add',
          '--directory',
          projectPath,
          '--ide',
          'cursor',
          '--all',
          '--skill',
          'my-skill',
          'owner/repo',
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('adds to global config when --global is passed', () async {
      await runner.run(['add', '--global', '--ide', 'cursor', 'owner/repo']);

      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      expect(globalConfig.gitRepos, hasLength(1));
      expect(
        globalConfig.gitRepos.first.cloneUrl,
        'https://github.com/owner/repo.git',
      );
    });

    test('adds to local manifest when --global is not passed', () async {
      await runner.run([
        'add',
        '--directory',
        projectPath,
        '--ide',
        'cursor',
        'owner/repo',
      ]);

      final localFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(localFile);
      expect(
        manifest
            .sourceUrisForIde('cursor')
            .containsKey('https://github.com/owner/repo.git'),
        isTrue,
      );
    });

    test('succeeds when --all is passed', () async {
      await runner.run([
        'add',
        '--directory',
        projectPath,
        '--ide',
        'cursor',
        '--all',
        'owner/repo',
      ]);

      final localFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(localFile);
      expect(
        manifest
            .sourceUrisForIde('cursor')
            .containsKey('https://github.com/owner/repo.git'),
        isTrue,
      );
    });

    test('succeeds when specific skill names are passed', () async {
      await runner.run([
        'add',
        '--directory',
        projectPath,
        '--ide',
        'cursor',
        '--skill',
        'my-skill',
        'owner/repo',
      ]);

      final localFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(localFile);
      expect(
        manifest
            .sourceUrisForIde('cursor')
            .containsKey('https://github.com/owner/repo.git'),
        isTrue,
      );
    });
  });
}
