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

  group('ResourceLink', () {
    test('reads the icons a server sent', () {
      final link = ResourceLink.fromMap({
        'type': 'resource_link',
        'uri': 'file:///a',
        'name': 'a',
        'icons': <Object?>[
          {
            'src': 'https://example.com/a.png',
            'sizes': <Object?>['48x48'],
          },
        ],
      });
      final icon = link.icons!.single;
      expect(icon.src, 'https://example.com/a.png');
      expect(icon.sizes, ['48x48']);
    });

    test('writes the icons it is given', () {
      final link = ResourceLink(
        uri: 'file:///a',
        name: 'a',
        icons: [Icon(src: 'https://example.com/a.png')],
      );
      expect((link as Map<String, Object?>)['icons'], [
        {'src': 'https://example.com/a.png'},
      ]);
      expect(link.icons!.single.src, 'https://example.com/a.png');
    });

    test('reads null icons when the server left them out', () {
      final link = ResourceLink(uri: 'file:///a', name: 'a');
      expect(link.icons, null);
    });
  });
}
