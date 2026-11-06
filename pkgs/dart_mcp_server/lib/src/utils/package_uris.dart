// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;

import 'package:file/file.dart';
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
/// Example:
///
///   replaceUriPrefix(
///     content,
///     Uri.parse('/path/to/lib/'),
///     'package',
///     'foo',
///   )
///
/// This will replace all occurrences of the absolute path `/path/to/lib/`
/// with `package:foo/`.
///
/// There is some additional logic to handle Windows paths, where `toFilePath()`
/// might return paths like `/C:/Users/...`. This function will remove the
/// leading slash in that case.
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

/// Verifies that [targetPath] (and its nearest existing ancestor) stays within
/// [packageRootDir] both lexically and after resolving any symlinks.
Future<bool> resolvesWithinPackageRoot(
  Directory packageRootDir,
  String targetPath,
  FileSystem fileSystem,
) async {
  // Reject NUL characters (`\x00`), since `package:path` treats them as
  // ordinary characters during normalization while `dart:io` native calls treat
  // paths as null-terminated strings.
  if (targetPath.contains('\x00')) return false;

  final canonicalPkgRoot = fileSystem.path.canonicalize(packageRootDir.path);
  final canonicalTarget = fileSystem.path.canonicalize(targetPath);
  if (canonicalPkgRoot != canonicalTarget &&
      !fileSystem.path.isWithin(canonicalPkgRoot, canonicalTarget)) {
    return false;
  }

  if (!await packageRootDir.exists()) return true;
  final resolvedRoot = fileSystem.path.canonicalize(
    await packageRootDir.resolveSymbolicLinks(),
  );
  var current = targetPath;
  while (true) {
    final type = await fileSystem.type(current, followLinks: true);
    if (type != FileSystemEntityType.notFound) {
      final resolvedCurrent = fileSystem.path.canonicalize(
        type == FileSystemEntityType.directory
            ? await fileSystem.directory(current).resolveSymbolicLinks()
            : await fileSystem.file(current).resolveSymbolicLinks(),
      );
      return resolvedRoot == resolvedCurrent ||
          fileSystem.path.isWithin(resolvedRoot, resolvedCurrent);
    }
    if (await fileSystem.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      final linkTarget = await fileSystem.link(current).target();
      final resolvedLinkPath = fileSystem.path.isAbsolute(linkTarget)
          ? linkTarget
          : fileSystem.path.join(fileSystem.path.dirname(current), linkTarget);
      final canonicalLinkTarget = fileSystem.path.canonicalize(
        resolvedLinkPath,
      );
      final withinLexicalRoot =
          canonicalPkgRoot == canonicalLinkTarget ||
          fileSystem.path.isWithin(canonicalPkgRoot, canonicalLinkTarget);
      final withinResolvedRoot =
          resolvedRoot == canonicalLinkTarget ||
          fileSystem.path.isWithin(resolvedRoot, canonicalLinkTarget);
      if (!withinLexicalRoot && !withinResolvedRoot) {
        return false;
      }
    }
    final parent = fileSystem.path.dirname(current);
    if (parent == current) return true;
    current = parent;
  }
}
