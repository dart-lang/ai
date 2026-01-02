// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math' show Random;

/// Generates a short, 8-character hex string from 32 bits of random data.
///
/// This is not a standard UUID but is sufficient for use cases where a short,
/// unique-enough identifier is needed.
String generateShortUUID() => _bitsDigits(16, 4) + _bitsDigits(16, 4);

// Note: The following private helpers were copied over from:
// https://github.com/dart-lang/webdev/blob/e2d14f1050fa07e9a60455cf9d2b8e6f4e9c332c/frontend_server_common/lib/src/uuid.dart
final Random _random = Random();

String _bitsDigits(int bitCount, int digitCount) =>
    _printDigits(_generateBits(bitCount), digitCount);

int _generateBits(int bitCount) => _random.nextInt(1 << bitCount);

String _printDigits(int value, int count) =>
    value.toRadixString(16).padLeft(count, '0');
