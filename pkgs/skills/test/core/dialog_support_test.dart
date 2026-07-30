// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:io/ansi.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:test/test.dart';

void main() {
  group('formatSkillName', () {
    test(
      'bolds skill name after package name prefix when package name is given',
      () {
        overrideAnsiOutput(true, () {
          expect(
            formatSkillName('foo-bar', packageName: 'foo'),
            equals('foo-\x1B[1mbar\x1B[22m'),
          );
          expect(
            formatSkillName('foo-bar-baz', packageName: 'foo'),
            equals('foo-\x1B[1mbar-baz\x1B[22m'),
          );
        });
      },
    );

    test(
      'bolds skill name after flutter- or dart- prefix when package name is omitted',
      () {
        overrideAnsiOutput(true, () {
          expect(
            formatSkillName('flutter-widgets'),
            equals('flutter-\x1B[1mwidgets\x1B[22m'),
          );
          expect(
            formatSkillName('dart-async'),
            equals('dart-\x1B[1masync\x1B[22m'),
          );
        });
      },
    );

    test(
      'bolds entire skill name when package name is omitted and prefix is not flutter-/dart-',
      () {
        overrideAnsiOutput(true, () {
          expect(
            formatSkillName('my_pkg-custom-skill'),
            equals('\x1B[1mmy_pkg-custom-skill\x1B[22m'),
          );
          expect(
            formatSkillName('simpleskill'),
            equals('\x1B[1msimpleskill\x1B[22m'),
          );
        });
      },
    );

    test('returns plain text when ANSI output is disabled', () {
      overrideAnsiOutput(false, () {
        expect(
          formatSkillName('foo-bar', packageName: 'foo'),
          equals('foo-bar'),
        );
        expect(formatSkillName('simpleskill'), equals('simpleskill'));
      });
    });
  });
}
