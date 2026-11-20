// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills/src/core/skill_collisions.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';

void main() {
  bool isCollision(ScannedSkill a, ScannedSkill b) => findCollisions(
    skills: [a, b],
    manifest: const SkillManifest(),
    agentName: 'generic',
    runSourceUris: const {},
  ).isNotEmpty;

  test('Given the same name from two git repos then it is no collision', () {
    const a = ScannedSkill(gitUrl: 'a.git', skillName: 's', skillPath: 'a');
    const b = ScannedSkill(gitUrl: 'b.git', skillName: 's', skillPath: 'b');
    expect(isCollision(a, b), isFalse);
  });

  test('Given the same name from two packages then it is no collision', () {
    const a = ScannedSkill(packageName: 'a', skillName: 's', skillPath: 'a');
    const b = ScannedSkill(packageName: 'b', skillName: 's', skillPath: 'b');
    expect(isCollision(a, b), isFalse);
  });
}
