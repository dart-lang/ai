// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp_server/src/utils/json.dart';
import 'package:test/test.dart';

void main() {
  test('dig with empty path', () {
    expect(dig<Map>({'abc': 'de'}, []), {'abc': 'de'});
    expect(dig<Null>(null, []), null);
    expect(
      () => dig<int>(null, []),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected an int at root. Found null.'),
        ),
      ),
    );
    expect(
      () => dig<Map<String, Object?>>(<Object?>[], []),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected a map at root. Found a list.'),
        ),
      ),
    );
    expect(
      () => dig<Map<String, dynamic>>(<String>[], []),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected a map at root. Found a list.'),
        ),
      ),
    );
  });

  test('dig with array index', () {
    expect(
      dig<Map>(
        [
          {'abc': 'de'},
        ],
        [0],
      ),
      {'abc': 'de'},
    );
    expect(
      () => dig<Map>({'abc': 'de'}, [1]),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected a list at root. Found a map'),
        ),
      ),
    );
    expect(
      () => dig<Map>(
        [
          {'abc': 'de'},
        ],
        [1],
      ),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains(
            'Expected at least 2 element(s) at root. Found only 1 element(s)',
          ),
        ),
      ),
    );
    expect(
      () => dig<Map>(
        {
          'a': [
            {'abc': 'de'},
            {'fg': 'hi'},
          ],
        },
        ['a', 2],
      ),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains(
            'Expected at least 3 element(s) at [a]. Found only 2 element(s)',
          ),
        ),
      ),
    );
  });

  test('dig with map key', () {
    expect(dig<String>({'abc': 'de'}, ['abc']), 'de');
    expect(
      () => dig<String>(['abc', 'de'], ['abc']),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected a map at root'),
        ),
      ),
    );
    expect(
      () => dig<Map>(
        [
          {'abc': 'de'},
        ],
        [1, 'de'],
      ),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains(
            'Expected at least 2 element(s) at root. Found only 1 element(s)',
          ),
        ),
      ),
    );
  });

  test('dig with key-value', () {
    expect(
      dig<Map>(
        {
          'packages': [
            {'name': 'abc', 'age': 5},
            {'name': 'other', 'age': 10},
          ],
        },
        ['packages', ('name', 'abc')],
      ),
      {'name': 'abc', 'age': 5},
    );
    expect(
      () => dig<Map>(
        {
          'packages': [
            {'name': 'abc', 'age': 5},
            {'name': 'other', 'age': 10},
          ],
        },
        ['packages', ('name', 'unknown')],
      ),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('No element with name=unknown at [packages]'),
        ),
      ),
    );
    expect(
      () => dig<Map>(
        {
          'a': {'abc': 'de'},
        },
        [('a', 'b')],
      ),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected a list at root. Found a map.'),
        ),
      ),
    );

    expect(
      () => dig<Map>([1, 2, 3], [('a', 'b')]),
      throwsA(
        isA<FormatException>().having(
          (d) => d.message,
          'message',
          contains('Expected a map at root[0]. Found a number.'),
        ),
      ),
    );
  });
}
