// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills/src/agent/adapters/custom_adapter.dart';
import 'package:skills/src/agent/agent.dart';
import 'package:skills/src/agent/agent_adapter_factory.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('CustomAdapter', () {
    test('installs skill into custom directory', () async {
      await d.dir('source_pkg', [
        d.dir('skills', [
          d.dir('my-skill', [
            d.file('SKILL.md', '''
---
name: my-skill
description: A test skill.
---

# My Skill
'''),
          ]),
        ]),
      ]).create();

      final agent = Agent.directory('custom_target', projectPath: d.sandbox);
      final adapter = CustomAdapter(agent, d.sandbox);
      await adapter.installSkill(
        ScannedSkill(
          packageName: 'source_pkg',
          skillName: 'my-skill',
          skillPath: d.path('source_pkg/skills/my-skill'),
        ),
      );

      expect(
        File(d.path('custom_target/my-skill/SKILL.md')).existsSync(),
        isTrue,
      );
    });
  });

  group('createAgentAdapter for a directory agent', () {
    test('returns a CustomAdapter for its directory', () {
      final agent = Agent.directory('custom/skills', projectPath: d.sandbox);
      final adapter = createAgentAdapter(agent, d.sandbox, null);

      expect(adapter, isA<CustomAdapter>());
      expect(adapter.agent, same(agent));
      expect(adapter.skillsDirectory, equals(agent.skillsPath(d.sandbox)));
    });
  });
}
