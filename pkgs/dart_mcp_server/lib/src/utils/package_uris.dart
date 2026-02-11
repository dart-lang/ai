// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:package_config/package_config.dart';

/// Cleans up a file path, particularly for Windows where `toFilePath()`
/// might return paths like `/C:/Users/...`.
String cleanFilePath(String path) {
  if (Platform.isWindows && path.startsWith('/') && path.contains(':')) {
    return path.substring(1);
  }
  return path;
}

/// Replaces all occurrences of [prefixUri] in [content] with a URI defined by
/// [scheme] and [packageName].
///
/// Example: `replaceUriPrefix(content, libUri, 'package', 'foo')` will replace
/// all occurrences of the absolute path to `lib/` with `package:foo/`.
String replaceUriPrefix(
  String content,
  Uri prefixUri,
  String scheme,
  String packageName,
) {
  final path = cleanFilePath(prefixUri.path);
  return content.replaceAll(path, '$scheme:$packageName/');
}

/// Substitutes absolute file paths within [package] with their corresponding
/// `package:` and `package-root:` URIs in the given [content].
///
/// This first tries to replace the `lib/` directory path with `package:`,
/// and then replaces any remaining paths within the package root with
/// `package-root:`.
String substitutePackageUris(String content, Package package) {
  final text = replaceUriPrefix(
    content,
    package.packageUriRoot,
    'package',
    package.name,
  );
  return replaceUriPrefix(text, package.root, 'package-root', package.name);
}
