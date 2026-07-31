// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:skills/src/core/pruner.dart';
import 'package:skills/src/core/pub_runner.dart';
import '../agent/agent.dart';
import 'options.dart';
import 'skills_command.dart';

/// Removes installed skills whose package is no longer in the dependency tree,
/// and cleans up unused git skill sources.
class PruneCommand extends SkillsCommand {
  @override
  final String name = 'prune';

  @override
  final String description =
      'Remove skills whose package is no longer in the dependency tree.';

  final DialogSupport? _dialogSupport;

  PruneCommand({DialogSupport? dialogSupport})
    : _dialogSupport = dialogSupport {
    addAgentOption(argParser);
    argParser.addFlag(
      'all',
      abbr: 'a',
      help: 'Prune all unused packages and empty sources without prompting.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    final workspace = await resolveWorkspace();

    final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
    if (!ready) {
      throw UsageException('Failed to run pub get.', usage);
    }

    final List<Agent>? targetAgents;
    final parsedAgents = parseAgentOption(argResults);
    if (parsedAgents.isNotEmpty) {
      targetAgents = parsedAgents;
    } else {
      targetAgents = null;
    }

    final allFlag = argResults.flag('all');

    await pruneSkills(
      workspace: workspace,
      logger: logger,
      dialogSupport: _dialogSupport,
      targetAgents: targetAgents,
      allFlag: allFlag,
    );
  }
}
