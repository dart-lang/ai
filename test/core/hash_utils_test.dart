import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:skills/src/core/hash_utils.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('when calculating directory hashes', () {
    test(
      'then cross-platform path separators resolve to the same hash',
      () async {
        await d.dir('dir1', [
          d.dir('sub', [d.file('file.txt', 'content')]),
        ]).create();

        final hash = await tryCalculateDirectoryHash(Directory(d.path('dir1')));
        // Hash of 'sub/file.txt' with 'content'. By running this test on windows
        // and asserting a specific hash, we validate that the results are the
        // same across platforms.
        expect(
          hash,
          '1Yt3grcmDxoKP7iufKHLyA==',
          reason: 'The generated hash should be the same on all platforms',
        );
      },
    );

    test('then hashing an empty directory works', () async {
      await d.dir('empty').create();

      final hash = await tryCalculateDirectoryHash(Directory(d.path('empty')));
      expect(hash, base64.encode(md5.convert([]).bytes));
    });

    test('then hashing a missing directory returns null', () async {
      expect(
        await tryCalculateDirectoryHash(Directory(d.path('empty'))),
        isNull,
      );
    });

    test(
      'then modifying a single deeply nested file produces a different hash',
      () async {
        await d.dir('nested1', [
          d.dir('a', [
            d.dir('b', [
              d.dir('c', [d.file('file.txt', 'content1')]),
            ]),
          ]),
        ]).create();

        await d.dir('nested2', [
          d.dir('a', [
            d.dir('b', [
              d.dir('c', [
                d.file('file.txt', 'content2'), // Modified content
              ]),
            ]),
          ]),
        ]).create();

        final hash1 = await tryCalculateDirectoryHash(
          Directory(d.path('nested1')),
        );
        final hash2 = await tryCalculateDirectoryHash(
          Directory(d.path('nested2')),
        );

        expect(hash1, isNot(equals(hash2)));
      },
    );

    test('then moving a file produces a different hash', () async {
      final file = d.file('file.txt', 'content');
      await file.create();
      final originalHash = await tryCalculateDirectoryHash(
        Directory(d.sandbox),
      );

      await file.io.rename(file.io.uri.resolve('new_file.txt').toFilePath());
      await d.file('new_file.txt', 'content').validate();
      await d.nothing('file.txt').validate();

      final changedHash = await tryCalculateDirectoryHash(Directory(d.sandbox));
      expect(originalHash, isNot(equals(changedHash)));
    });
  });

  group('when calculating file hashes', () {
    test('then missing file returns null', () async {
      final file = File(d.path('missing.txt'));
      expect(await tryCalculateFileHash(file), isNull);
    });

    test('then file with content returns expected hash', () async {
      await d.file('file.txt', 'content').create();
      final hash = await tryCalculateFileHash(File(d.path('file.txt')));
      expect(
        hash,
        equals(base64.encode(md5.convert(utf8.encode('content')).bytes)),
      );
    });

    test('then modifying file content produces different hash', () async {
      await d.file('file.txt', 'content1').create();
      final hash1 = await tryCalculateFileHash(File(d.path('file.txt')));

      await d.file('file.txt', 'content2').create();
      final hash2 = await tryCalculateFileHash(File(d.path('file.txt')));

      expect(hash1, isNot(equals(hash2)));
    });
  });
}
