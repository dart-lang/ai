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
          d.dir('my-package-my-skill', [
            d.file('SKILL.md', '''---
name: my-package-my-skill
description: "my description"
---

# my-package-my-skill

Brief overview of what this skill does and what it enables the agent to do.

## Instructions

Step-by-step instructions for the agent to follow:

1. Step one...
2. Step two...

## Guidelines

- Use clear, imperative language (e.g., "Run X", "Verify Y").
- Include concrete examples of inputs and expected outputs where helpful.
- Keep `SKILL.md` concise; move detailed reference docs to `references/` and helper scripts to `scripts/`.
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
            d.dir('my-package-existing-skill', [
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
    test(
      'creates a skill with a description containing special characters',
      () async {
        await d.dir('project', [pubspec('my_package')]).create();

        await runner.run([
          'create',
          '--name',
          'my-skill2',
          '--description',
          'description with: a colon, "quotes", \nnewlines\tand backticks `like this`',
          '-C',
          d.path('project'),
        ]);

        await d.dir('project', [
          d.dir('skills', [
            d.dir('my-package-my-skill2', [
              d.file('SKILL.md', r'''---
name: my-package-my-skill2
description: "description with: a colon, \"quotes\", \nnewlines\tand backticks `like this`"
---

# my-package-my-skill2

Brief overview of what this skill does and what it enables the agent to do.

## Instructions

Step-by-step instructions for the agent to follow:

1. Step one...
2. Step two...

## Guidelines

- Use clear, imperative language (e.g., "Run X", "Verify Y").
- Include concrete examples of inputs and expected outputs where helpful.
- Keep `SKILL.md` concise; move detailed reference docs to `references/` and helper scripts to `scripts/`.
'''),
            ]),
          ]),
        ]).validate();
      },
    );
  });
}
