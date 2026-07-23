// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import '../agent/agent.dart';
import '../agent/agent_adapter_factory.dart';
import '../models/skill_manifest.dart';
import 'skills_command.dart';

/// Lists all installed managed skills.
class ListCommand extends SkillsCommand {
  @override
  final String name = 'list';

  @override
  final String description = 'List installed managed skills.';

  ListCommand();

  @override
  Future<void> run() async {
    final workspace = await resolveWorkspace();
    final rootPath = workspace.rootPath;

    final manifest = await SkillManifest.loadOrEmptyFromRoot(rootPath);

    if (manifest.isEmpty) {
      logger.info('No managed skills installed.');
      return;
    }

    final buffer = StringBuffer()
      ..writeln('Installed skills:')
      ..writeln();

    for (final agentName in manifest.allAgents) {
      final pkgs = manifest.sourceUrisForAgent(agentName);
      if (pkgs.isEmpty) continue;

      final agentObj = Agent.fromCliName(agentName);
      final String header;
      if (agentObj != null) {
        final adapter = createAgentAdapter(agentObj, rootPath, null);
        final installDir = p.relative(adapter.skillsDirectory, from: rootPath);
        header = '  ${agentObj.label} (installed at $installDir):';
      } else {
        header = '  $agentName:';
      }
      buffer.writeln(header);

      for (final entry in pkgs.entries) {
        buffer.writeln('    ${entry.key}:');
        for (final skill in entry.value.skills) {
          final pathSuffix =
              skill.path != null && skill.path != '.'
                  ? ' (repo path: ${skill.path})'
                  : '';
          buffer.writeln('      - ${skill.name}$pathSuffix');
        }
      }
    }

    buffer
      ..writeln()
      ..writeln(
        'Note: These are only managed skills; there may be additional skills installed.',
      );

    logger.info(buffer.toString());
  }
}
