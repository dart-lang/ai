import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import '../fake_dialog_support.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('GetCommand with registry', () {
    test(
      'when git is unavailable then only Dart skills are installed and warning is printed',
      () async {
        // Use a test-owned temp dir (pass to create()) so we do not use test_descriptor's
        // global sandbox; then run the command with --directory so we never change process cwd.
        final testRootPath = p.join(
          Directory.systemTemp.path,
          'skills_get_test_${DateTime.now().millisecondsSinceEpoch}',
        );
        Directory(testRootPath).createSync();
        addTearDown(() async {
          await Directory(testRootPath).delete(recursive: true);
        });

        // dep_with_skills is sibling of project, so from project/.dart_tool we need ../../dep_with_skills
        final depRelative = p.join('..', '..', 'dep_with_skills');

        await d.dir('dep_with_skills', [
          d.dir('lib', [d.file('dep.dart', '')]),
          d.dir('skills', [
            d.dir('dep_with_skills-code-gen', [
              d.file('SKILL.md', '---\nname: dep_with_skills-code-gen\n---\n'),
            ]),
          ]),
        ]).create(testRootPath);

        await d.dir('project', [
          d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
                  {
                    'name': 'dep_with_skills',
                    'rootUri': depRelative,
                    'packageUri': 'lib/',
                  },
                ],
              }),
            ),
          ]),
          d.dir('.cursor', [d.dir('skills')]),
        ]).create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');

        final getCommand = GetCommand(
          dialogSupport: FakeDialogSupport(),
          gitRunner: GitRunner(isAvailableOverride: _gitUnavailable),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner
            .run(['get', '--directory', projectPath, '--ide', 'cursor']);

        final skillDir = Directory(
          p.join(projectPath, '.cursor', 'skills', 'dep_with_skills-code-gen'),
        );
        expect(await skillDir.exists(), isTrue);
        final manifestFile = File(SkillManifest.pathIn(projectPath));
        expect(await manifestFile.exists(), isTrue);
      },
    );

    test(
        'when installing from global registry then adds back-link to global '
        'config', () async {
      final mockRegistry = d.dir('mock_registry', [
        d.dir('skills', [
          d.dir('pkg-skill', [
            d.file('SKILL.md', '---\nname: pkg-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry.create();
      final registryPath = mockRegistry.io.path;

      // Initialize git repo
      await Process.run('git', ['init'], workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.name', 'Test'],
          workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: registryPath);
      await Process.run('git', ['add', '.'], workingDirectory: registryPath);
      await Process.run('git', ['commit', '-m', 'initial'],
          workingDirectory: registryPath);

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
                {'name': 'pkg', 'rootUri': '../../pkg', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final globalConfigPath = d.file('global_config.json').io.path;
      GlobalConfig.globalPathOverride = globalConfigPath;
      addTearDown(() => GlobalConfig.globalPathOverride = null);

      final fileUrl = '../mock_registry';
      var globalConfig = const GlobalConfig();
      globalConfig = globalConfig.withRegistry(RegistryRepo(cloneUrl: fileUrl));
      await globalConfig.save(File(globalConfigPath));

      final getCommand = GetCommand(
        dialogSupport: FakeDialogSupport(),
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run(['--directory', projectPath, 'get', '--ide', 'cursor']);

      expect(
          Directory(p.join(projectPath, '.cursor', 'skills', 'pkg-skill'))
              .existsSync(),
          isTrue);

      final updatedGlobalConfig =
          await GlobalConfig.loadOrEmpty(File(globalConfigPath));
      final repo = updatedGlobalConfig.registries
          .firstWhere((r) => r.cloneUrl == fileUrl);
      expect(repo.installs, isNotEmpty);
      expect(repo.installs.first, contains('pkg-skill'));
    });
  });
}

Future<bool> _gitUnavailable() async => false;
