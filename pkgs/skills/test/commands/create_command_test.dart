import 'package:args/command_runner.dart';

import 'package:skills/src/commands/create_command.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils.dart';

void main() {
  late CommandRunner<void> runner;
  late CreateCommand createCommand;

  setUp(() async {
    createCommand = CreateCommand();
    runner = CommandRunner<void>('skills', 'test')
      ..addCommand(createCommand)
      ..argParser.addOption('directory', abbr: 'C');
  });

  group('CreateCommand', () {
    test('creates a skill with valid name and description from args', () async {
      await d.dir('project', [pubspec('my_package')]).create();

      await runner.run([
        'create',
        '--name',
        'my-skill',
        '--description',
        'my description',
        '-C',
        d.path('project'),
      ]);

      await d.dir('project', [
        d.dir('skills', [
          d.dir('my_package-my-skill', [
            d.file('SKILL.md', '''---
name: my_package-my-skill
description: my description
---

Add your skill instructions here.
'''),
          ]),
        ]),
      ]).validate();
    });

    test(
      'throws UsageException when a name passed as an option has invalid characters',
      () async {
        await d.dir('project', [pubspec('my_package')]).create();

        expect(
          () => runner.run([
            'create',
            '--name',
            'super@awesome skill!',
            '--description',
            'description',
            '-C',
            d.path('project'),
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );

    test(
      'throws UsageException when a name passed as an option has spaces',
      () async {
        await d.dir('project', [pubspec('my_package')]).create();

        expect(
          () => runner.run([
            'create',
            '--name',
            'my skill',
            '--description',
            'description',
            '-C',
            d.path('project'),
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );

    test(
      'throws UsageException if the skill directory already exists',
      () async {
        await d.dir('project', [
          pubspec('my_package'),
          d.dir('skills', [
            d.dir('my_package-existing-skill', [
              d.file('SKILL.md', 'existing content'),
            ]),
          ]),
        ]).create();

        expect(
          () => runner.run([
            'create',
            '--name',
            'existing-skill',
            '--description',
            'new description',
            '-C',
            d.path('project'),
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );
  });
}
