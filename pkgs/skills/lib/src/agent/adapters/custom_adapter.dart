// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';

import '../agent.dart';
import 'agent_skills_adapter.dart';

/// Custom agent adapter.
///
/// Installs skills to a custom directory.
class CustomAdapter extends AgentSkillsAdapter {
  @override
  final Logger logger = Logger('CustomAdapter');

  CustomAdapter(Agent agent, String projectPath, {super.dialogSupport})
    : super(agent, agent.skillsPath(projectPath));
}
