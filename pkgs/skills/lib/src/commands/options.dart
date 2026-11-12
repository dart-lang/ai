// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:skills/src/core/dialog_support.dart';

import '../agent/agent.dart';

/// Parses the --agent option from [argResults].
/// Returns the agents that were specified via --agent.
List<Agent> parseAgentOption(ArgResults argResults) {
  final parsedAgents = argResults.multiOption('agent');
  // Agent names are already validated by the `allowed` list on the option.
  return [for (var agent in parsedAgents) Agent.fromCliName(agent)!];
}

/// Registers the shared `--agent` option on [argParser].
void addAgentOption(ArgParser argParser) {
  argParser.addMultiOption(
    'agent',
    aliases: ['ide'],
    help: 'Target agent',
    allowed: Agent.cliNames,
  );
}

/// Registers the shared `--install-dir` option on [argParser].
void addInstallDirOption(ArgParser argParser) {
  argParser.addOption(
    'install-dir',
    abbr: 'd',
    help: 'Custom install directory.',
  );
}

/// Resolves the agents to operate on.
///
/// Checks `--agent` and `--install-dir`, then `SKILLS_AGENT` env var, then
/// auto-detects, and finally prompts the user via [dialogSupport].
///
/// Throws if no agent can be determined.
///
/// Uses [environment] (defaults to [Platform.environment]) for environment
/// variables.
Future<List<Agent>> resolveAgents({
  required ArgResults? argResults,
  required String projectPath,
  DialogSupport? dialogSupport,
  @visibleForTesting Map<String, String>? environment,
}) async {
  if (argResults != null) {
    final agents = parseAgentOption(argResults);
    final installDir = argResults.option('install-dir');
    if (installDir != null) {
      if (installDir.trim().isEmpty) {
        throw UsageException('--install-dir requires a non-empty path.', '');
      }
      agents.add(Agent.directory(installDir, projectPath: projectPath));
    }
    if (agents.isNotEmpty) return agents;
  }

  // No explicit option, next we check for environment variables.
  environment ??= Platform.environment;
  final env =
      environment['SKILLS_AGENT'] ??
      // Legacy fallback
      environment['SKILLS_IDE'];
  if (env != null) {
    final agent = Agent.fromCliName(env);
    // Only accepts built-in agents, like --agent.
    if (agent != null && Agent.values.contains(agent)) return [agent];
    throw UsageException(
      'Unknown AGENT "$env". Valid values: ${Agent.validNames}',
      '',
    );
  }

  // Finally, try to auto-detect agents.
  final detected = const AgentDetector().detectAll(projectPath);
  if (detected.isNotEmpty) return detected;

  if (dialogSupport case var dialogSupport?) {
    final options = [for (var agent in Agent.values) agent.label];
    final result = await dialogSupport.showMultiSelectDialog(
      options,
      title: 'Unable to auto-detect agent. Please select one or more:',
    );
    if (result != null && result.isNotEmpty) {
      return result.map((e) => Agent.values[e]).toList();
    }
  }
  throw UsageException(
    'Could not auto-detect agent and none selected. Use --agent to specify one of: '
        '${Agent.validNames}',
    '',
  );
}
