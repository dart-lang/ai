// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';

void main() {
  test('skills pass skills_lint', () async {
    final config = await ConfigParser.loadConfig();
    expect(
      config.parsingErrors,
      isEmpty,
      reason: 'Fix the skills_lint.yaml errors listed in this failure.',
    );
    expect(
      config.directoryConfigs,
      isNotEmpty,
      reason: 'skills_lint.yaml must list at least one skills directory.',
    );

    final passed = await validateSkills(config: config);

    expect(
      passed,
      isTrue,
      reason: 'skills_lint found errors. Its findings are printed above.',
    );
  });
}
