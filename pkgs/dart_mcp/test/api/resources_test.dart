// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:test/test.dart';

void main() {
  group('Resource', () {
    test('reads a size off a decoded map', () {
      final resource = Resource.fromMap({
        'uri': 'file:///a',
        'name': 'a',
        'size': 12,
      });
      expect(resource.size, 12);
    });

    test('reads a null size when the server left it out', () {
      final resource = Resource.fromMap({'uri': 'file:///a', 'name': 'a'});
      expect(resource.size, null);
    });
  });
}
