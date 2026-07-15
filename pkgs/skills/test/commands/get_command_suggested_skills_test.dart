// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_repos.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('Suggested skills dialog', () {
    late String projectPath;
    late String globalConfigPath;
    late FakeDialogSupport fakeDialogSupport;
    late SkillsCommandRunner runner;

    setUpAll(() {
      Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
    });

    setUp(() async {
      // Hack to try and give windows some time to clean up file handles held
      // by processes.
      addTearDown(() async {
        final dir = Directory(d.sandbox);
        for (var i = 0; i < 4; i++) {
          try {
            await dir.delete(recursive: true);
            // Now, we have to recreate it so that the test descriptor package
            // doesn't fail since it doesn't check if it exists.
            await dir.create();
            return;
          } catch (_) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      });

      await d.dir('flutter', [pubspec('flutter')]).create();
      await d.dir('project', [
        pubspec('project', dependencies: [const Dependency('flutter')]),
      ]).create();
      projectPath = d.path('project');

      await d.dir('global_config_dir', []).create();
      globalConfigPath = p.join(
        d.path('global_config_dir'),
        'global_config.json',
      );
      GlobalConfig.globalPathOverride = globalConfigPath;

      fakeDialogSupport = FakeDialogSupport(skipSuggestedRepos: false);
      final getCommand = GetCommand(
        dialogSupport: fakeDialogSupport,
        gitRunner: GitRunner(isAvailableOverride: () async => false),
      );
      runner = SkillsCommandRunner('skills', 'Test')..addCommand(getCommand);
    });

    tearDown(() {
      GlobalConfig.globalPathOverride = null;
    });

    test('prompts and installs selected repo globally', () async {
      // 0 = dart-lang/skills, 1 = flutter/skills, 2 = never ask again
      fakeDialogSupport.multiSelectResults.add({0, 1}); // Select both repos
      fakeDialogSupport.singleSelectResults.add(1); // Select Global

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      expect(globalConfig.gitRepos, hasLength(2));
      expect(
        globalConfig.gitRepos.map((r) => r.cloneUrl).toList(),
        containsAll([
          'https://github.com/dart-lang/skills.git',
          'https://github.com/flutter/agent-plugins.git',
        ]),
      );
      expect(globalConfig.neverPromptForSuggestedSkills, isFalse);

      final localFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(localFile);
      expect(manifest.suggestedRepos, hasLength(2));
    });

    test('prompts and installs selected repo locally', () async {
      fakeDialogSupport.multiSelectResults.add({0}); // Select dart-lang/skills
      fakeDialogSupport.singleSelectResults.add(0); // Select Local

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      expect(globalConfig.gitRepos, isEmpty);

      final localFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(localFile);
      expect(manifest.suggestedRepos, hasLength(2));
      expect(
        manifest
            .sourceUrisForAgent('cursor')
            .containsKey('https://github.com/dart-lang/skills.git'),
        isTrue,
      );
    });

    test('never ask again sets global config', () async {
      fakeDialogSupport.multiSelectResults.add({2}); // Select never ask again

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      expect(globalConfig.gitRepos, isEmpty);
      expect(globalConfig.neverPromptForSuggestedSkills, isTrue);
    });

    test('never ask again skips the dialog', () async {
      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      await globalConfig
          .withNeverPromptForSuggestedSkills(true)
          .save(File(globalConfigPath));

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      expect(fakeDialogSupport.allTitles, isEmpty);
    });

    test('already prompted repos are skipped', () async {
      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(manifestFile);
      await manifest
          .withPromptedSuggestedRepos({
            'https://github.com/dart-lang/skills.git',
            'https://github.com/flutter/agent-plugins.git',
          })
          .save(manifestFile);

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      expect(fakeDialogSupport.allTitles, isEmpty);
    });

    test('already globally installed repos are not suggested', () async {
      final globalConfig = await GlobalConfig.loadOrEmpty(
        File(globalConfigPath),
      );
      await globalConfig
          .withGitRepo(
            const GitRepo(cloneUrl: 'https://github.com/dart-lang/skills.git'),
          )
          .withGitRepo(
            const GitRepo(
              cloneUrl: 'https://github.com/flutter/agent-plugins.git',
            ),
          )
          .save(File(globalConfigPath));

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      expect(fakeDialogSupport.allTitles, isEmpty);
    });

    test('already locally installed repos are not suggested', () async {
      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.loadOrEmpty(manifestFile);
      await manifest
          .withSourceUri(
            'cursor',
            'https://github.com/dart-lang/skills.git',
            const SkillsEntry(),
          )
          .withSourceUri(
            'cursor',
            'https://github.com/flutter/agent-plugins.git',
            const SkillsEntry(),
          )
          .save(manifestFile);

      await runner.run(['get', '--directory', projectPath, '--ide', 'cursor']);

      expect(fakeDialogSupport.allTitles, isEmpty);
    });
  });
}
