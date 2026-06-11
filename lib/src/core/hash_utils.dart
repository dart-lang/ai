import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Computes a hash of the directory contents.
///
/// If [dir] does not exist, this throws a [StateError].
///
/// Returns a base64 encoded md5 hash.
Future<String> calculateDirectoryHash(Directory dir) async {
  if (!await dir.exists()) {
    throw StateError(
        'Failed to calculate hash for $dir: Directory does not exist');
  }

  final files = await dir
      .list(recursive: true)
      .where((e) => e is File)
      .cast<File>()
      .toList();

  if (files.isEmpty) {
    return base64.encode(md5.convert([]).bytes);
  }

  final combined = Uint8List(16);

  await Future.wait(files.map((file) async {
    var relativePath = p.relative(file.path, from: dir.path);
    if (p.separator != p.url.separator) {
      relativePath = relativePath.replaceAll(p.separator, p.url.separator);
    }

    final bytes = await file.readAsBytes();

    final builder = BytesBuilder()
      ..add(utf8.encode(relativePath))
      ..add(bytes);

    final hashBytes = md5.convert(builder.takeBytes()).bytes;
    assert(hashBytes.length == 16);
    for (var j = 0; j < 16; j++) {
      combined[j] ^= hashBytes[j];
    }
  }));

  return base64.encode(combined);
}

/// Computes a hash of a single file's contents.
///
/// Returns a base64 encoded md5 hash.
Future<String?> tryCalculateFileHash(File file) async {
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  return base64.encode(md5.convert(bytes).bytes);
}
