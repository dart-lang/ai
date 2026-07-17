import 'package:args/command_runner.dart';

import 'package:skills/src/commands/create_command.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

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
      await d.dir('project', [
        d.file('pubspec.yaml', 'name: my_package'),
      ]).create();

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
        await d.dir('project2', [
          d.file('pubspec.yaml', 'name: pkg_two'),
        ]).create();

        expect(
          () => runner.run([
            'create',
            '--name',
            'super@awesome skill!',
            '--description',
            'description',
            '-C',
            d.path('project2'),
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );

    test(
      'throws UsageException when a name passed as an option has spaces',
      () async {
        await d.dir('project3', [
          d.file('pubspec.yaml', 'name: pkg_three'),
        ]).create();

        expect(
          () => runner.run([
            'create',
            '--name',
            'my skill',
            '--description',
            'description',
            '-C',
            d.path('project3'),
          ]),
          throwsA(isA<UsageException>()),
        );
      },
    );
  });
}
