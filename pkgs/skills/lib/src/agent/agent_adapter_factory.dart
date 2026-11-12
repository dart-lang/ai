// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:skills/src/core/dialog_support.dart';

import 'adapters/claude_adapter.dart';
import 'adapters/cline_adapter.dart';
import 'adapters/copilot_adapter.dart';
import 'adapters/cursor_adapter.dart';
import 'adapters/custom_adapter.dart';
import 'adapters/generic_adapter.dart';
import 'adapters/opencode_adapter.dart';
import 'agent.dart';
import 'agent_adapter.dart';

/// Creates the appropriate [AgentAdapter] for the given [agent] and [projectPath].
AgentAdapter createAgentAdapter(
  Agent agent,
  String projectPath,
  DialogSupport? dialogSupport, {
  String? customInstallDir,
}) {
  return switch (agent) {
    Agent.cursor => CursorAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.generic => GenericAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.claude => ClaudeAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.copilot => CopilotAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.cline => ClineAdapter(projectPath, dialogSupport: dialogSupport),
    Agent.opencode => OpenCodeAdapter(
      projectPath,
      dialogSupport: dialogSupport,
    ),
    Agent.custom => CustomAdapter(
      p.normalize(p.join(projectPath, customInstallDir!)),
      dialogSupport: dialogSupport,
    ),
  };
}
