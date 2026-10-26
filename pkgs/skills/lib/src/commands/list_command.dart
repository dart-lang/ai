// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent/agent.dart';
import '../agent/agent_adapter.dart';
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

    var hasInstalledSkills = false;

    for (final agentName in manifest.allAgents) {
      hasInstalledSkills =
          await _appendAgentSkills(agentName, manifest, rootPath, buffer) ||
          hasInstalledSkills;
    }

    if (!hasInstalledSkills) {
      logger.info('No managed skills installed.');
      return;
    }

    buffer
      ..writeln()
      ..writeln(
        'Note: These are only managed skills; there may be additional skills installed.',
      );

    logger.info(buffer.toString());
  }
}

Future<bool> _appendAgentSkills(
  String agentName,
  SkillManifest manifest,
  String rootPath,
  StringBuffer buffer,
) async {
  final pkgs = manifest.sourceUrisForAgent(agentName);
  if (pkgs.isEmpty) return false;

  final agentObj = Agent.fromCliName(agentName);
  final adapter = agentObj != null
      ? createAgentAdapter(agentObj, rootPath, null)
      : null;

  final agentBuffer = StringBuffer();
  var agentHasSkills = false;

  for (final entry in pkgs.entries) {
    agentHasSkills =
        await _appendPackageSkills(entry, adapter, agentBuffer) ||
        agentHasSkills;
  }

  if (agentHasSkills) {
    final String header;
    if (agentObj != null && adapter != null) {
      final installDir = p
          .split(p.relative(adapter.skillsDirectory, from: rootPath))
          .join('/');
      header = '  ${agentObj.label} (installed at $installDir):';
    } else {
      header = '  $agentName:';
    }
    buffer.writeln(header);
    buffer.write(agentBuffer.toString());
    return true;
  }
  return false;
}

Future<bool> _appendPackageSkills(
  MapEntry<String, SkillsEntry> entry,
  AgentAdapter? adapter,
  StringBuffer agentBuffer,
) async {
  final pkgBuffer = StringBuffer();
  var pkgHasSkills = false;

  for (final skill in entry.value.skills) {
    if (!skill.isInstalled) continue;
    if (adapter != null) {
      final skillDir = Directory(p.join(adapter.skillsDirectory, skill.name));
      if (!await skillDir.exists()) continue;
    }

    final pathSuffix = skill.path != null && skill.path != '.'
        ? ' (repo path: ${skill.path})'
        : '';
    pkgBuffer.writeln('      - ${skill.name}$pathSuffix');
    pkgHasSkills = true;
  }

  if (pkgHasSkills) {
    agentBuffer.writeln('    ${entry.key}:');
    agentBuffer.write(pkgBuffer.toString());
    return true;
  }
  return false;
}
