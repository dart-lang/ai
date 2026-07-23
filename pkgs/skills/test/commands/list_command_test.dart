// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';
import 'package:skills/src/commands/list_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils.dart';

void main() {
  late CommandRunner runner;
  late List<String> loggedMessages;
  late StreamSubscription<LogRecord> logSub;

  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

  setUp(() {
    loggedMessages = [];
    logSub = Logger.root.onRecord.listen((r) {
      printOnFailure(r.toString());
      loggedMessages.add(r.message);
    });
    final listCommand = ListCommand();
    runner = SkillsCommandRunner('skills', 'test')..addCommand(listCommand);
  });

  tearDown(() async {
    await logSub.cancel();
  });

  group('Given a project with installed skills in multiple agents', () {
    late SkillManifest manifest;
    late String projectPath;

    setUp(() async {
      manifest = SkillManifest(
        installations: {
          'generic': {
            'https://github.com/foo/bar.git': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'deep-skill',
                  installedAt: DateTime.utc(2026, 2, 25),
                  path: 'packages/deep/path/to/deep-skill',
                ),
                InstalledSkillEntry(
                  name: 'root-skill',
                  installedAt: DateTime.utc(2026, 2, 25),
                  path: '.',
                ),
              ],
            ),
          },
          'cursor': {
            'package:pkg_a': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-code-gen',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
                InstalledSkillEntry(
                  name: 'pkg_a-api-helper',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
            'package:pkg_b': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_b-testing',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
          },
          'claude': {
            'package:pkg_a': SkillsEntry(
              skills: [
                InstalledSkillEntry(
                  name: 'pkg_a-code-gen',
                  installedAt: DateTime.utc(2026, 2, 25),
                ),
              ],
            ),
          },
        },
      );

      await d.dir('project', [pubspec('test_app')]).create();
      projectPath = d.path('project');
      await manifest.save(File(SkillManifest.pathIn(projectPath)));
    });

    test('when listing then all agents and packages are present', () {
      expect(manifest.allAgents, containsAll(['generic', 'cursor', 'claude']));
      expect(manifest.sourceUrisForAgent('generic'), hasLength(1));
      expect(manifest.sourceUrisForAgent('cursor'), hasLength(2));
      expect(manifest.sourceUrisForAgent('claude'), hasLength(1));
    });

    test('when listing then cursor skills are correct', () {
      final cursorPkgA = manifest
          .sourceUrisForAgent('cursor')['package:pkg_a']!
          .skills;
      expect(
        cursorPkgA.map((s) => s.name),
        containsAll(['pkg_a-code-gen', 'pkg_a-api-helper']),
      );
    });

    test('when listing then claude skills are correct', () {
      final claudePkgA = manifest
          .sourceUrisForAgent('claude')['package:pkg_a']!
          .skills;
      expect(claudePkgA.map((s) => s.name), equals(['pkg_a-code-gen']));
    });

    test('when iterating allSkills then returns total across agents', () {
      expect(manifest.allSkills, hasLength(6));
    });

    test('when iterating allSkillsForIde then returns only that agent', () {
      expect(manifest.allSkillsForAgent('generic'), hasLength(2));
      expect(manifest.allSkillsForAgent('cursor'), hasLength(3));
      expect(manifest.allSkillsForAgent('claude'), hasLength(1));
    });

    test('when running list command then formatted output is correct', () async {
      await runner.run(['list', '--directory', projectPath]);

      final output = loggedMessages.join('\n');

      // Requirement 1: Agent labels contain aliases in parenthesis for agents with aliases
      expect(output, contains('generic (antigravity, codex)'));

      // Requirement 2: Actual install directory is messaged for each agent
      expect(output, contains('(installed at .agents/skills)'));
      expect(output, contains('(installed at .cursor/skills)'));
      expect(output, contains('(installed at .claude/skills)'));

      // Requirement 3: Note about managed skills
      expect(
        output,
        contains(
          'Note: These are only managed skills; there may be additional skills installed.',
        ),
      );

      // Requirement 4: Full path listed for git sources with deep path
      expect(
        output,
        contains('- deep-skill (repo path: packages/deep/path/to/deep-skill)'),
      );
      // Root skills (path '.') should not have '.' suffix
      expect(output, contains('- root-skill'));
      expect(output, isNot(contains('- root-skill (.)')));
    });

    test('InstalledSkillEntry JSON serialization preserves path', () {
      final entry = InstalledSkillEntry(
        name: 'test-skill',
        installedAt: DateTime.parse('2026-07-23T18:00:00.000Z'),
        path: 'deep/sub/path',
      );
      final json = entry.toJson();
      expect(json['path'], equals('deep/sub/path'));

      final deserialized = InstalledSkillEntry.fromJson(json);
      expect(deserialized.path, equals('deep/sub/path'));
    });
  });

  group('Given a project with no installed skills', () {
    test('when loading manifest then returns null', () async {
      await d.dir('bare_project').create();

      final manifest = await SkillManifest.loadFromRoot(d.path('bare_project'));

      expect(manifest, isNull);
    });

    test('when creating empty manifest then isEmpty is true', () {
      const manifest = SkillManifest();

      expect(manifest.isEmpty, isTrue);
      expect(manifest.allSkills, isEmpty);
      expect(manifest.allAgents, isEmpty);
    });

    test(
      'when running list command then messages no managed skills installed',
      () async {
        await d.dir('bare_project', [pubspec('bare_app')]).create();

        await runner.run(['list', '--directory', d.path('bare_project')]);

        final output = loggedMessages.join('\n');
        expect(output, contains('No managed skills installed.'));
      },
    );
  });
}
