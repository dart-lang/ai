// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/version.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  test('--version prints the version', () async {
    final runner = SkillsCommandRunner('skills', 'Test');
    final logs = [];
    await runZoned(
      () async {
        await runner.run(['--version']);
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => logs.add(line),
      ),
    );
    expect(logs, equals([version]));
  });
}
