// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/add_command.dart';
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
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
    const gitRunner = GitRunner();
    final runner = SkillsCommandRunner('skills', 'Test')
      ..addCommand(
        GetCommand(dialogSupport: dialogSupport, gitRunner: gitRunner),
      )
      ..addCommand(
        AddCommand(dialogSupport: dialogSupport, gitRunner: gitRunner),
      );
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
  Future<Map<String, bool>> recordedCopies({String agent = 'generic'}) async {
    final manifest = await SkillManifest.loadOrEmptyFromRoot(projectPath);
    return {
      for (final MapEntry(key: sourceUri, value: entry)
          in manifest.sourceUrisForAgent(agent).entries)
        for (final skill in entry.skills)
          if (skill.name == _skill) sourceUri: skill.isInstalled,
    };
  }

  Future<void> recordPackageCopyAsSkipped({String agent = 'generic'}) async {
    final file = File(SkillManifest.pathIn(projectPath));
    final manifest = await SkillManifest.loadOrEmpty(file);
    final skipped = InstalledSkillEntry(
      name: _skill,
      installedAt: DateTime.utc(2026),
      isInstalled: false,
    );
    await manifest
        .withSourceUri(agent, _package, SkillsEntry(skills: [skipped]))
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

    test('when running get --all then it warns and changes nothing', () async {
      await run(['get', '--all']);

      expect(warnings(), hasLength(1));
      expect(installedContent(), 'git content');
      expect(await recordedCopies(), {repoUrl: true});
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

  group('Given the first two steps of the issue', () {
    setUp(() async {
      await run(['add', repoUrl, '--skill', 'pkg_a']);
      await run(['get', '--package', 'pkg_a', '--all']);
    });

    test('when running get --all as the third step then the package copy '
        'stays and nothing warns', () async {
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
    await recordPackageCopyAsSkipped();

    await run(['get', '--package', 'pkg_a', '--all']);

    expect(installedContent(), 'package content');
    expect(await recordedCopies(), {repoUrl: false, _package: true});
  });

  test('Given two agents, one in conflict and one with both copies skipped, '
      'when the question is answered then only the agent in conflict '
      'changes', () async {
    await run(['add', repoUrl, '--all']);
    await run(['add', repoUrl, '--skill', 'pkg_a'], agents: ['claude']);
    await recordPackageCopyAsSkipped(agent: 'claude');
    dialogs.singleSelectResults.add(0);
    dialogs.multiSelectResults.addAll([
      {0},
      {0},
    ]);

    await run(['get'], interactive: true, agents: ['generic', 'claude']);

    expect(installedContent(), 'package content');
    expect(installedContent(agentDirectory: '.claude'), isNull);
    expect(await recordedCopies(), {repoUrl: false, _package: true});
    expect(await recordedCopies(agent: 'claude'), {
      repoUrl: false,
      _package: false,
    });
  });
}
