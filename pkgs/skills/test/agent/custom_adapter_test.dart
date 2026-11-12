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

      final customDir = d.path('custom_target');
      final adapter = CustomAdapter(customDir);
      await adapter.installSkill(
        ScannedSkill(
          packageName: 'source_pkg',
          skillName: 'my-skill',
          skillPath: d.path('source_pkg/skills/my-skill'),
        ),
      );

      expect(File('$customDir/my-skill/SKILL.md').existsSync(), isTrue);
    });
  });

  group('createAgentAdapter for Agent.custom', () {
    test('resolves relative path against projectPath', () {
      final adapter = createAgentAdapter(
        Agent.custom,
        '/my/project',
        null,
        customInstallDir: 'custom/skills',
      );
      expect(adapter, isA<CustomAdapter>());
      expect(adapter.skillsDirectory, equals('/my/project/custom/skills'));
    });

    test('preserves absolute path', () {
      final adapter = createAgentAdapter(
        Agent.custom,
        '/my/project',
        null,
        customInstallDir: '/absolute/custom/skills',
      );
      expect(adapter.skillsDirectory, equals('/absolute/custom/skills'));
    });
  });
}
