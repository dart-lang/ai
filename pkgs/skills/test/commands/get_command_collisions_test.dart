// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/add_command.dart';
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../fake_dialog_support.dart';
import '../utils.dart';

const _skill = 'pkg_a-skill';
const _package = 'package:pkg_a';

d.FileDescriptor _skillFile(String name, String body) =>
    d.file('SKILL.md', '---\nname: $name\ndescription: A skill.\n---\n$body\n');

void main() {
  late String projectPath;
  late String repoUrl;
  late FakeDialogSupport dialogs;
  late List<LogRecord> logs;

  setUp(() async {
    await d.dir('pkg_a', [
      pubspec('pkg_a'),
      d.dir('skills', [
        d.dir(_skill, [_skillFile(_skill, 'package content')]),
      ]),
    ]).create();
    await d.dir('repo', [
      d.dir('skills', [
        d.dir('pkg_a', [_skillFile('pkg_a', 'entry content')]),
      ]),
      d.dir('packages', [
        d.dir('pkg_a', [
          d.dir('skills', [
            d.dir(_skill, [_skillFile(_skill, 'git content')]),
          ]),
        ]),
      ]),
    ]).create();
    final repoPath = p.normalize(p.absolute(d.path('repo')));
    for (final args in [
      ['init'],
      ['config', 'user.email', 'test@test'],
      ['config', 'user.name', 'Test'],
      ['add', '.'],
      ['commit', '-m', 'init'],
    ]) {
      await Process.run('git', args, workingDirectory: repoPath);
    }
    repoUrl = Platform.isWindows
        ? 'file:///${repoPath.replaceAll(r'\', '/')}'
        : 'file://$repoPath';

    await d.dir('project', [
      pubspec('project', dependencies: [const Dependency('pkg_a')]),
    ]).create();
    projectPath = d.path('project');

    GlobalConfig.globalPathOverride = d.path('global_config.json');
    addTearDown(() => GlobalConfig.globalPathOverride = null);

    dialogs = FakeDialogSupport();
    logs = [];
    final sub = Logger.root.onRecord.listen((record) {
      printOnFailure(record.toString());
      logs.add(record);
    });
    addTearDown(sub.cancel);
  });

  Future<void> run(
    List<String> args, {
    bool interactive = false,
    List<String> agents = const ['generic'],
  }) async {
    final dialogSupport = interactive ? dialogs : null;
    final runner = SkillsCommandRunner('skills', 'Test')
      ..addCommand(GetCommand(dialogSupport: dialogSupport))
      ..addCommand(AddCommand(dialogSupport: dialogSupport));
    await runner.run([
      ...args,
      '--directory',
      projectPath,
      for (final agent in agents) ...['--agent', agent],
    ]);
  }

  String? installedContent({String agentDirectory = '.agents'}) {
    final file = File(
      p.join(projectPath, agentDirectory, 'skills', _skill, 'SKILL.md'),
    );
    return file.existsSync() ? file.readAsLinesSync().last : null;
  }

  /// Whether the manifest records pkg_a-skill as installed, by source.
  Future<Map<String, bool>> recordedCopies() async {
    final manifest = await SkillManifest.loadOrEmptyFromRoot(projectPath);
    return {
      for (final MapEntry(key: sourceUri, value: entry)
          in manifest.sourceUrisForAgent('generic').entries)
        for (final skill in entry.skills)
          if (skill.name == _skill) sourceUri: skill.isInstalled,
    };
  }

  /// Records pkg_a-skill from the package as skipped, or as installed with a
  /// hash that the installed directory does not have.
  Future<void> recordPackageCopy({required bool isInstalled}) async {
    final file = File(SkillManifest.pathIn(projectPath));
    final manifest = await SkillManifest.loadOrEmpty(file);
    final entry = InstalledSkillEntry(
      name: _skill,
      installedAt: DateTime.utc(2026),
      contentHash: isInstalled ? 'package copy hash' : null,
      isInstalled: isInstalled,
    );
    await manifest
        .withSourceUri('generic', _package, SkillsEntry(skills: [entry]))
        .save(file);
  }

  Iterable<LogRecord> warnings() => logs.where(
    (r) => r.level == Level.WARNING && r.message.contains('left as it is'),
  );

  group('Given the package copy unrecorded and the git copy installed', () {
    setUp(() async {
      await run(['add', repoUrl, '--all']);
    });

    test('when interactive get is answered with the package then the package '
        'copy is installed and the next get asks nothing', () async {
      dialogs.singleSelectResults.add(0);
      dialogs.multiSelectResults.addAll([
        {0},
        {0},
      ]);

      await run(['get'], interactive: true);

      expect(dialogs.lastSingleSelectOptions.single, [_package, repoUrl]);
      expect(dialogs.allInitialSelected.last, {0});
      expect(installedContent(), 'package content');
      expect(await recordedCopies(), {repoUrl: false, _package: true});
      expect(warnings(), isEmpty);

      dialogs.reset();
      await run(['get'], interactive: true);
      expect(dialogs.singleSelectCallCount, 0);
    });

    test('when interactive get is answered with the git repo then the package '
        'copy is skipped', () async {
      dialogs.singleSelectResults.add(1);

      await run(['get'], interactive: true);

      expect(installedContent(), 'git content');
      expect(await recordedCopies(), {repoUrl: true, _package: false});
    });

    test('when the question is cancelled then nothing changes', () async {
      dialogs.singleSelectResults.add(null);

      await run(['get'], interactive: true);

      expect(installedContent(), 'git content');
      expect(await recordedCopies(), {repoUrl: true});
    });

    test('when the question is answered with the package and the sources '
        'dialog is cancelled or the package is unticked then nothing '
        'changes', () async {
      File(
        p.join(projectPath, '.agents', 'skills', 'pkg_a', 'SKILL.md'),
      ).writeAsStringSync('edited');
      for (final selectedSources in [
        null,
        <int>{},
        {0},
      ]) {
        dialogs.reset();
        dialogs.singleSelectResults.add(0);
        dialogs.multiSelectResults.addAll([
          selectedSources,
          {0},
        ]);

        await run(['get'], interactive: true);

        expect(installedContent(), 'git content');
        expect(await recordedCopies(), {repoUrl: true});
      }
    });

    test('when running get --all in a terminal then it asks nothing, warns, '
        'leaves the skill as it is and installs the others', () async {
      final skillsPath = p.join(projectPath, '.agents', 'skills');
      File(p.join(skillsPath, _skill, 'SKILL.md')).writeAsStringSync('edited');
      await d.dir('pkg_a', [
        d.dir('skills', [
          d.dir('pkg_a-other', [_skillFile('pkg_a-other', 'other content')]),
        ]),
      ]).create();

      await run(['get', '--all'], interactive: true);

      expect(dialogs.singleSelectCallCount, 0);
      expect(warnings(), hasLength(1));
      expect(installedContent(), 'edited');
      expect(await recordedCopies(), {repoUrl: true});
      expect(Directory(p.join(skillsPath, 'pkg_a-other')).existsSync(), isTrue);
    });

    test(
      'when running get --package --all then it warns and changes nothing',
      () async {
        await run(['get', '--package', 'pkg_a', '--all']);

        expect(warnings(), hasLength(1));
        expect(installedContent(), 'git content');
        expect(await recordedCopies(), {repoUrl: true});
      },
    );

    test('when running get --package --skill then the package copy is '
        'installed', () async {
      await run(['get', '--package', 'pkg_a', '--skill', _skill]);

      expect(installedContent(), 'package content');
      expect(await recordedCopies(), {repoUrl: false, _package: true});
    });
  });

  group('Given the package copy installed and the git copy skipped', () {
    setUp(() async {
      await run(['add', repoUrl, '--skill', 'pkg_a']);
      await run(['get', '--package', 'pkg_a', '--all']);
    });

    test('when running get --all then the package copy stays and nothing '
        'warns', () async {
      await run(['get', '--all']);

      expect(installedContent(), 'package content');
      expect(await recordedCopies(), {repoUrl: false, _package: true});
      expect(warnings(), isEmpty);
    });

    test(
      'when running get --git --all then the git copy is not installed',
      () async {
        await run(['get', '--git', repoUrl, '--all']);

        expect(installedContent(), 'package content');
        expect(await recordedCopies(), {repoUrl: false, _package: true});
      },
    );

    test(
      'when running get --git --skill then the git copy is installed',
      () async {
        await run(['get', '--git', repoUrl, '--skill', _skill]);

        expect(installedContent(), 'git content');
        expect(await recordedCopies(), {repoUrl: true, _package: false});
      },
    );
  });

  test('Given both copies skipped when running get --package --all then the '
      'package copy is installed', () async {
    await run(['add', repoUrl, '--skill', 'pkg_a']);
    await recordPackageCopy(isInstalled: false);

    await run(['get', '--package', 'pkg_a', '--all']);

    expect(installedContent(), 'package content');
    expect(await recordedCopies(), {repoUrl: false, _package: true});
  });

  test('Given both copies recorded as installed and the git copy on disk, '
      'when interactive get is answered with the package then the package '
      'copy starts ticked and is installed', () async {
    await run(['add', repoUrl, '--all']);
    await recordPackageCopy(isInstalled: true);
    dialogs.singleSelectResults.add(0);
    dialogs.multiSelectResults.addAll([
      {0},
      {0},
    ]);

    await run(['get'], interactive: true);

    expect(dialogs.allMultiSelectOptions.last.single, contains('Local edits'));
    expect(dialogs.allInitialSelected.last, {0});
    expect(installedContent(), 'package content');
    expect(await recordedCopies(), {repoUrl: false, _package: true});
  });

  test('Given two agents, one in conflict and one with the git copy skipped, '
      'when the question is answered with the package then only the package '
      'copy of the agent in conflict starts ticked', () async {
    await run(['add', repoUrl, '--all']);
    await run(['add', repoUrl, '--skill', 'pkg_a'], agents: ['claude']);
    dialogs.singleSelectResults.add(0);
    dialogs.multiSelectResults.addAll([
      {0},
      {0},
    ]);

    await run(['get'], interactive: true, agents: ['generic', 'claude']);

    expect(dialogs.allMultiSelectOptions.last, [
      contains('for generic'),
      contains('for claude'),
    ]);
    expect(dialogs.allInitialSelected.last, {0});
    expect(installedContent(), 'package content');
    expect(installedContent(agentDirectory: '.claude'), isNull);
  });
}
