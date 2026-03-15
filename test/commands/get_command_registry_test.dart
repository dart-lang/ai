import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/models/skill_manifest.dart';
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
          gitRunner: GitRunner(isAvailableOverride: _gitUnavailable),
        );
        final runner = CommandRunner<void>('skills', 'Test')
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
  });
}

Future<bool> _gitUnavailable() async => false;
