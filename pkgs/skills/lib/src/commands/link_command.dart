// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../core/dialog_support.dart';
import '../models/skill_manifest.dart';
import 'get_skills.dart';
import 'options.dart';
import 'skills_command.dart';

/// Command to symlink skills from a local directory into the agent, so that
/// edits to them show up immediately.
class LinkCommand extends SkillsCommand {
  @override
  final String name = 'link';

  @override
  final String description =
      'Symlink skills from a local directory into your agent, so edits to '
      'them show up immediately.';

  final DialogSupport? dialogSupport;

  LinkCommand({this.dialogSupport}) {
    addAgentOption(argParser);
    argParser
      ..addMultiOption(
        'skill',
        abbr: 's',
        help: 'Link the specific skills only.',
      )
      ..addFlag(
        'all',
        abbr: 'a',
        help: 'Link all skills from the given directory.',
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    final argResults = this.argResults!;
    if (argResults.rest.length != 1) {
      throw UsageException(
        'Please provide exactly one directory to link.',
        usage,
      );
    }
    final directory = p.normalize(p.absolute(argResults.rest.single));
    if (!await Directory(directory).exists()) {
      throw UsageException('Directory not found: $directory', usage);
    }
    final skillNames = argResults.multiOption('skill').toSet();
    final allFlag = argResults.flag('all');
    checkAllAndSkillExclusive(argResults, usage);

    final workspace = await resolveWorkspace();
    final agents = await resolveAgents(
      argResults: argResults,
      projectPath: workspace.rootPath,
      dialogSupport: dialogSupport,
    );
    if (agents.isEmpty) return;

    // Record the directory as a source if not present, then let `get` scan
    // and link its skills like any other source.
    final sourceUri = SkillManifest.linkedSourceUri(directory);
    final localFile = manifestFile(workspace.rootPath);
    var manifest = await SkillManifest.loadOrEmpty(localFile);
    for (final agent in agents) {
      if (manifest.sourceUrisForAgent(agent.cliName).containsKey(sourceUri)) {
        continue;
      }
      manifest = manifest.withSourceUri(
        agent.cliName,
        sourceUri,
        const SkillsEntry(),
      );
    }
    await manifest.save(localFile);

    await getSkills(
      agents: agents,
      logger: logger,
      workspace: workspace,
      dialogSupport: dialogSupport,
      usage: usage,
      sourceUris: {sourceUri},
      skillNames: skillNames,
      allFlag: allFlag,
    );
  }
}
