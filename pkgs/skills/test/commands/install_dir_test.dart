// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:io/ansi.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/list_command.dart';
import 'package:skills/src/commands/remove_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  late SkillsCommandRunner runner;
  late List<String> loggedMessages;
  late StreamSubscription<LogRecord> logSub;
  late FakeDialogSupport fakeDialogSupport;

  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

  setUp(() {
    loggedMessages = [];
    logSub = Logger.root.onRecord.listen((r) {
      printOnFailure(r.toString());
      loggedMessages.add(r.message);
    });
    fakeDialogSupport = FakeDialogSupport();
    runner = SkillsCommandRunner('skills', 'test')
      ..addCommand(
        GetCommand(
          dialogSupport: fakeDialogSupport,
          gitRunner: GitRunner(isAvailableOverride: () async => false),
        ),
      )
      ..addCommand(ListCommand())
      ..addCommand(RemoveCommand(dialogSupport: fakeDialogSupport));
  });

  tearDown(() async {
    await logSub.cancel();
  });

  group('Given a project with dependencies containing skills', () {
    late String projectPath;

    setUp(() async {
      await d.dir('dep_a', [
        pubspec('dep_a'),
        d.dir('skills', [
          d.dir('dep_a-skill1', [
            d.file('SKILL.md', '''
---
name: dep_a-skill1
description: Skill 1 from dep_a.
---

# Skill 1
'''),
          ]),
        ]),
      ]).create();

      await d.dir('project', [
        pubspec('project', dependencies: [.new('dep_a')]),
      ]).create();

      projectPath = d.path('project');
    });

    test(
      'installing, listing, and removing custom skills updates manifest, list, and disk',
      () async {
        await overrideAnsiOutput(false, () async {
          await runner.run([
            'get',
            '--directory',
            projectPath,
            '--install-dir',
            'third_party/skills',
            '--all',
          ]);
          loggedMessages.clear();

          await runner.run(['list', '--directory', projectPath]);
        });

        final manifest = await SkillManifest.loadFromRoot(projectPath);
        expect(manifest, isNotNull);
        expect(manifest!.allAgents, equals(['dir:third_party/skills']));
        expect(
          manifest
              .sourceUrisForAgent('dir:third_party/skills')['package:dep_a']!
              .skills,
          hasLength(1),
        );

        expect(
          loggedMessages.any(
            (m) => m.contains(
              'dir:third_party/skills (installed at third_party/skills):',
            ),
          ),
          isTrue,
        );

        final skillFile = File(
          p.join(
            projectPath,
            'third_party',
            'skills',
            'dep_a-skill1',
            'SKILL.md',
          ),
        );
        expect(await skillFile.exists(), isTrue);

        await overrideAnsiOutput(false, () async {
          await runner.run(['remove', '--directory', projectPath, '--all']);
        });

        expect(await skillFile.exists(), isFalse);
        expect(await SkillManifest.loadFromRoot(projectPath), isNull);
      },
    );

    test('two custom directories coexist and remove cleans both', () async {
      await overrideAnsiOutput(false, () async {
        for (final dir in ['first_dir', 'second_dir']) {
          await runner.run([
            'get',
            '--directory',
            projectPath,
            '--install-dir',
            dir,
            '--all',
          ]);
        }
      });

      final skillFiles = [
        for (final dir in ['first_dir', 'second_dir'])
          File(p.join(projectPath, dir, 'dep_a-skill1', 'SKILL.md')),
      ];
      for (final skillFile in skillFiles) {
        expect(await skillFile.exists(), isTrue);
      }
      final manifest = await SkillManifest.loadFromRoot(projectPath);
      expect(manifest!.allAgents, equals(['dir:first_dir', 'dir:second_dir']));

      await overrideAnsiOutput(false, () async {
        await runner.run(['remove', '--directory', projectPath, '--all']);
      });

      for (final skillFile in skillFiles) {
        expect(await skillFile.exists(), isFalse);
      }
      expect(await SkillManifest.loadFromRoot(projectPath), isNull);
    });
  });
}
