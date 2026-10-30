// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:manual_evals/manual_evals.dart';
import 'package:test/test.dart';

void main() {
  test('runManualEval runs without error', () {
    expect(() => runManualEval(['--help']), returnsNormally);
  });
}
