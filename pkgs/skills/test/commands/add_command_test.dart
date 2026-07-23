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
        () => runner.run([
          'add',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws if both --all and --skill are provided', () async {
      expect(
        () => runner.run([
          'add',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
          '--all',
          '--skill',
          'my-skill',
          'owner/repo',
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'does not add to manifest or config when git is not available',
      () async {
        await runner.run([
          'add',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
          'owner/repo',
        ]);

        final localFile = File(SkillManifest.pathIn(projectPath));
        final manifest = await SkillManifest.loadOrEmpty(localFile);
        expect(manifest.isEmpty, isTrue);
      },
    );

    group('with valid local git repository', () {
      late String fileUrl;
      late SkillsCommandRunner realGitRunner;

      setUp(() async {
        await d.dir('local_repo', [
          d.dir('skills', [
            d.dir('my-skill', [
              d.file('SKILL.md', '''
---
name: my-skill
description: A test skill.
---
Test skill body.
'''),
            ]),
          ]),
        ]).create();
        final localPath = p.normalize(p.absolute(d.path('local_repo')));
        await Process.run('git', ['init'], workingDirectory: localPath);
        await Process.run('git', [
          'config',
          'user.email',
          'test@test',
        ], workingDirectory: localPath);
        await Process.run('git', [
          'config',
          'user.name',
          'Test',
        ], workingDirectory: localPath);
        await Process.run('git', ['add', '.'], workingDirectory: localPath);
        await Process.run('git', [
          'commit',
          '-m',
          'init',
        ], workingDirectory: localPath);

        if (Platform.isWindows) {
          fileUrl = 'file:///${localPath.replaceAll(r'\', '/')}';
        } else {
          fileUrl = 'file://$localPath';
        }

        final addCommand = AddCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: const GitRunner(),
        );
        realGitRunner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(addCommand);
      });

      test('adds to global config when --global is passed', () async {
        await realGitRunner.run([
          'add',
          '--global',
          '--agent',
          'cursor',
          '--all',
          fileUrl,
        ]);

        final globalConfig = await GlobalConfig.loadOrEmpty(
          File(globalConfigPath),
        );
        expect(globalConfig.gitRepos, hasLength(1));
        expect(globalConfig.gitRepos.first.cloneUrl, fileUrl);
      });

      test('adds to local manifest when --global is not passed', () async {
        await realGitRunner.run([
          'add',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
          '--all',
          fileUrl,
        ]);

        final localFile = File(SkillManifest.pathIn(projectPath));
        final manifest = await SkillManifest.loadOrEmpty(localFile);
        expect(
          manifest.sourceUrisForAgent('cursor').containsKey(fileUrl),
          isTrue,
        );
      });

      test('succeeds when specific skill names are passed', () async {
        await realGitRunner.run([
          'add',
          '--directory',
          projectPath,
          '--agent',
          'cursor',
          '--skill',
          'my-skill',
          fileUrl,
        ]);

        final localFile = File(SkillManifest.pathIn(projectPath));
        final manifest = await SkillManifest.loadOrEmpty(localFile);
        expect(
          manifest.sourceUrisForAgent('cursor').containsKey(fileUrl),
          isTrue,
        );
      });

      test(
        'does not add to manifest or config when repo sync fails and git is available',
        () async {
          await realGitRunner.run([
            'add',
            '--directory',
            projectPath,
            '--agent',
            'cursor',
            'bad/nonexistent_repo_for_test',
          ]);

          final localFile = File(SkillManifest.pathIn(projectPath));
          final manifest = await SkillManifest.loadOrEmpty(localFile);
          expect(
            manifest
                .sourceUrisForAgent('cursor')
                .containsKey(
                  'https://github.com/bad/nonexistent_repo_for_test.git',
                ),
            isFalse,
          );
        },
      );
    });
  });
}
