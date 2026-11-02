// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/ansi.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/link_command.dart';
import 'package:skills/src/commands/list_command.dart';
import 'package:skills/src/commands/prune_command.dart';
import 'package:skills/src/commands/remove_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  group('LinkCommand', () {
    late String projectPath;
    late String sourcePath;
    late String linkUri;
    late FakeDialogSupport fakeDialogSupport;
    late SkillsCommandRunner runner;
    late List<String> logs;

    d.FileDescriptor skillMd(String name, [String body = 'Body.']) => d.file(
      'SKILL.md',
      '---\nname: $name\ndescription: $name\n---\n$body\n',
    );

    String installedPath(String skillName) =>
        p.join(projectPath, '.cursor', 'skills', skillName);

    Future<SkillManifest> loadManifest() =>
        SkillManifest.loadOrEmptyFromRoot(projectPath);

    setUpAll(() {
      Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
    });

    setUp(() async {
      await d.dir('project', [pubspec('project')]).create();
      projectPath = d.path('project');

      await d.dir('skills_src', [
        d.dir('skills', [
          d.dir('my-skill', [skillMd('my-skill')]),
          d.dir('other-skill', [skillMd('other-skill')]),
        ]),
      ]).create();
      sourcePath = p.normalize(p.absolute(d.path('skills_src')));
      linkUri = SkillManifest.linkedSourceUri(sourcePath);

      await d.dir('global_config_dir', []).create();
      GlobalConfig.globalPathOverride = p.join(
        d.path('global_config_dir'),
        'global_config.json',
      );

      logs = [];
      final sub = Logger.root.onRecord.listen((r) => logs.add(r.message));
      addTearDown(sub.cancel);

      fakeDialogSupport = FakeDialogSupport();
      final gitRunner = GitRunner(isAvailableOverride: () async => false);
      runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(LinkCommand(dialogSupport: fakeDialogSupport))
        ..addCommand(
          GetCommand(dialogSupport: fakeDialogSupport, gitRunner: gitRunner),
        )
        ..addCommand(RemoveCommand(dialogSupport: fakeDialogSupport))
        ..addCommand(ListCommand())
        ..addCommand(PruneCommand(dialogSupport: fakeDialogSupport));
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    Future<void> run(List<String> args) => overrideAnsiOutput(
      false,
      () =>
          runner.run([args.first, '--directory', projectPath, ...args.skip(1)]),
    );

    test('throws if no directory is provided', () async {
      expect(
        () => run(['link', '--agent', 'cursor']),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws if more than one directory is provided', () async {
      expect(
        () => run(['link', '--agent', 'cursor', sourcePath, sourcePath]),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws if the directory does not exist', () async {
      expect(
        () => run(['link', '--agent', 'cursor', d.path('missing')]),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws if both --all and --skill are provided', () async {
      expect(
        () => run([
          'link',
          '--agent',
          'cursor',
          '--all',
          '--skill',
          'my-skill',
          sourcePath,
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('links every skill and records the source in the manifest', () async {
      await run(['link', '--agent', 'cursor', '--all', sourcePath]);

      for (final skillName in ['my-skill', 'other-skill']) {
        final link = Link(installedPath(skillName));
        expect(await link.exists(), isTrue, reason: '$skillName is a link');
        expect(
          await link.target(),
          equals(p.join(sourcePath, 'skills', skillName)),
        );
      }

      final entries = (await loadManifest()).sourceUrisForAgent('cursor');
      expect(entries.keys, equals([linkUri]));
      final skills = entries[linkUri]!.skills;
      expect(
        skills.map((s) => s.name),
        unorderedEquals(['my-skill', 'other-skill']),
      );
      expect(skills.map((s) => s.contentHash), everyElement(isNull));
      expect(
        skills.map((s) => s.path),
        unorderedEquals(['skills/my-skill', 'skills/other-skill']),
      );
    });

    test('links only the skills given with --skill', () async {
      await run([
        'link',
        '--agent',
        'cursor',
        '--skill',
        'my-skill',
        sourcePath,
      ]);

      expect(await Link(installedPath('my-skill')).exists(), isTrue);
      expect(await Link(installedPath('other-skill')).exists(), isFalse);
    });

    test('makes edits in the source visible through the link', () async {
      await run(['link', '--agent', 'cursor', '--all', sourcePath]);

      await File(
        p.join(sourcePath, 'skills', 'my-skill', 'SKILL.md'),
      ).writeAsString('edited');

      expect(
        await File(
          p.join(installedPath('my-skill'), 'SKILL.md'),
        ).readAsString(),
        equals('edited'),
      );
    });

    test('replaces a copied skill of the same name with a link', () async {
      await d.dir('project', [
        d.dir('.cursor', [
          d.dir('skills', [
            d.dir('my-skill', [skillMd('my-skill', 'Copied.')]),
          ]),
        ]),
      ]).create();

      await run(['link', '--agent', 'cursor', '--all', sourcePath]);

      expect(await Link(installedPath('my-skill')).exists(), isTrue);
    });

    test(
      'logs an error instead of crashing when a link cannot be created',
      () async {
        final skillsDir = Directory(p.join(projectPath, '.cursor', 'skills'));
        await skillsDir.create(recursive: true);
        await Process.run('chmod', ['555', skillsDir.path]);
        addTearDown(() => Process.run('chmod', ['755', skillsDir.path]));

        await run(['link', '--agent', 'cursor', '--all', sourcePath]);

        expect(logs, contains(contains('Failed to link my-skill')));
        expect(await Link(installedPath('my-skill')).exists(), isFalse);
      },
      testOn: '!windows',
    );

    test('logs when the directory contains no skills', () async {
      await d.dir('empty_src').create();

      await run(['link', '--agent', 'cursor', '--all', d.path('empty_src')]);

      expect(logs, contains(contains('No skills found')));
    });

    group('after linking', () {
      setUp(() async {
        await run(['link', '--agent', 'cursor', '--all', sourcePath]);
      });

      test('get --all links a skill added to the directory later', () async {
        await d.dir('skills_src', [
          d.dir('skills', [
            d.dir('new-skill', [skillMd('new-skill')]),
          ]),
        ]).create();

        await run(['get', '--agent', 'cursor', '--all']);

        expect(await Link(installedPath('new-skill')).exists(), isTrue);
        expect(await Link(installedPath('my-skill')).exists(), isTrue);
        final skills = (await loadManifest())
            .sourceUrisForAgent('cursor')[linkUri]!
            .skills;
        expect(
          skills.map((s) => s.name),
          unorderedEquals(['my-skill', 'other-skill', 'new-skill']),
        );
      });

      test(
        'get prompts to install a skill added to the directory later',
        () async {
          await d.dir('skills_src', [
            d.dir('skills', [
              d.dir('new-skill', [skillMd('new-skill')]),
            ]),
          ]).create();
          fakeDialogSupport.multiSelectResults = [
            {0}, // Browse the linked source.
            {0}, // Install new-skill.
          ];

          await run(['get', '--agent', 'cursor']);

          expect(fakeDialogSupport.allMultiSelectOptions[0], equals([linkUri]));
          expect(
            fakeDialogSupport.allMultiSelectOptions[1],
            equals(['new-skill (New)']),
          );
          expect(await Link(installedPath('new-skill')).exists(), isTrue);
          expect(await Link(installedPath('my-skill')).exists(), isTrue);
        },
      );

      test('get removes the link of a skill deleted from the directory '
          'without prompting', () async {
        await Directory(
          p.join(sourcePath, 'skills', 'other-skill'),
        ).delete(recursive: true);

        await run(['get', '--agent', 'cursor']);

        expect(
          FileSystemEntity.typeSync(
            installedPath('other-skill'),
            followLinks: false,
          ),
          equals(FileSystemEntityType.notFound),
        );
        expect(await Link(installedPath('my-skill')).exists(), isTrue);
        final skills = (await loadManifest())
            .sourceUrisForAgent('cursor')[linkUri]!
            .skills;
        expect(skills.map((s) => s.name), equals(['my-skill']));
        expect(fakeDialogSupport.allMultiSelectOptions, isEmpty);
        expect(logs, contains(contains('other-skill')));
      });

      test('remove --skill deletes the link and keeps the source', () async {
        await run(['remove', '--agent', 'cursor', '--skill', 'my-skill']);

        expect(
          FileSystemEntity.typeSync(
            installedPath('my-skill'),
            followLinks: false,
          ),
          equals(FileSystemEntityType.notFound),
        );
        expect(
          await File(
            p.join(sourcePath, 'skills', 'my-skill', 'SKILL.md'),
          ).exists(),
          isTrue,
        );
        expect(await Link(installedPath('other-skill')).exists(), isTrue);
        final skills = (await loadManifest())
            .sourceUrisForAgent('cursor')[linkUri]!
            .skills;
        expect(skills.map((s) => s.name), equals(['other-skill']));
      });

      test('list shows the linked source and its skills', () async {
        await run(['list']);

        final output = logs.join('\n');
        expect(output, contains('$linkUri:'));
        expect(output, contains('- my-skill (repo path: skills/my-skill)'));
        expect(
          output,
          contains('- other-skill (repo path: skills/other-skill)'),
        );
      });

      test('prune --all leaves linked skills alone', () async {
        await run(['prune', '--agent', 'cursor', '--all']);

        expect(await Link(installedPath('my-skill')).exists(), isTrue);
        expect(await Link(installedPath('other-skill')).exists(), isTrue);
        expect(
          (await loadManifest()).sourceUrisForAgent('cursor').keys,
          equals([linkUri]),
        );
      });
    });
  });
}
