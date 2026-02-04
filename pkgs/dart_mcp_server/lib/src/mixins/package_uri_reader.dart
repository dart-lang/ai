// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../features_configuration.dart';
import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/constants.dart';
import '../utils/file_system.dart';

/// Adds a tool for reading package URIs to an MCP server.
base mixin PackageUriSupport on ToolsSupport, RootsTrackingSupport
    implements FileSystemSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(readPackageUris, _readPackageUris);
    return super.initialize(request);
  }

  /// Used by the arg parser to list the valid tools.
  static final List<Tool> allTools = [readPackageUris];

  Future<CallToolResult> _readPackageUris(CallToolRequest request) async {
    final args = request.arguments!;
    final validated = validateRootConfig(
      args,
      fileSystem: fileSystem,
      knownRoots: await roots,
    );
    if (validated.errorResult case final error?) {
      return error;
    }
    // The root is always non-null if there is no error present.
    final root = validated.root!;

    // Note that we intentionally do not cache this, because the work to deal
    // with invalidating it would likely be more expensive than just
    // re-discovering it.
    final packageConfig = await findPackageConfig(
      fileSystem.directory(Uri.parse(root.uri)),
    );
    if (packageConfig == null) {
      return noPackageConfigFound(root);
    }

    final resultContent = <Content>[];
    for (final uri in (args[ParameterNames.uris] as List).cast<String>()) {
      await for (final content in _readPackageUri(
        Uri.parse(uri),
        packageConfig,
      )) {
        resultContent.add(content);
      }
    }

    return CallToolResult(content: resultContent);
  }

  Stream<Content> _readPackageUri(Uri uri, PackageConfig packageConfig) async* {
    if (uri.scheme != 'package') {
      yield TextContent(text: 'The URI "$uri" was not a "package:" URI.');
      return;
    }
    final packageName = uri.pathSegments.first;
    final path = p.url.joinAll(uri.pathSegments.skip(1));
    final package = packageConfig.packages.firstWhereOrNull(
      (package) => package.name == packageName,
    );
    if (package == null) {
      yield packageNotFoundText(packageName);
      return;
    }

    if (package.root.scheme != 'file') {
      // We expect all package roots to be file URIs.
      yield Content.text(
        text:
            'Unexpected root URI for package $packageName '
            '"${package.root.scheme}", only "file" schemes are supported',
      );
      return;
    }

    final packageRoot = Root(uri: package.root.toString());
    final resolvedUri = package.packageUriRoot.resolve(path);
    if (!isUnderRoot(packageRoot, resolvedUri.toString(), fileSystem)) {
      yield TextContent(
        text: 'The uri "$uri" attempted to escape it\'s package root.',
      );
      return;
    }

    final osFriendlyPath = p.fromUri(resolvedUri);
    final entityType = await fileSystem.type(
      osFriendlyPath,
      followLinks: false,
    );
    switch (entityType) {
      case FileSystemEntityType.directory:
        final dir = fileSystem.directory(osFriendlyPath);
        yield Content.text(text: '## Directory "$uri":');
        await for (final entry in dir.list(followLinks: false)) {
          yield ResourceLink(
            name: p.basename(osFriendlyPath),
            description: entry is Directory ? 'A directory' : 'A file',
            uri: packageConfig.toPackageUri(entry.uri)!.toString(),
            mimeType: lookupMimeType(entry.path) ?? '',
          );
        }
      case FileSystemEntityType.link:
        // We are only returning a reference to the target, so it is ok to not
        // check the path. The agent may have the permissions to read the linked
        // path on its own, even if it is outside of the package root.
        var targetUri = resolvedUri.resolve(
          await fileSystem.link(osFriendlyPath).target(),
        );
        // If we can represent it as a package URI, do so.
        final asPackageUri = packageConfig.toPackageUri(targetUri);
        if (asPackageUri != null) {
          targetUri = asPackageUri;
        }
        yield ResourceLink(
          name: p.basename(targetUri.path),
          description: 'Target of symlink at $uri',
          uri: targetUri.toString(),
          mimeType: lookupMimeType(targetUri.path) ?? '',
        );
      case FileSystemEntityType.file:
        final file = fileSystem.file(osFriendlyPath);
        final mimeType = lookupMimeType(resolvedUri.path) ?? '';
        final resourceUri = packageConfig.toPackageUri(resolvedUri)!.toString();
        // Attempt to treat it as a utf8 String first, if that fails then just
        // return it as bytes.
        try {
          yield Content.embeddedResource(
            resource: TextResourceContents(
              uri: resourceUri,
              text: await file.readAsString(),
              mimeType: mimeType,
            ),
          );
        } catch (_) {
          yield Content.embeddedResource(
            resource: BlobResourceContents(
              uri: resourceUri,
              mimeType: mimeType,
              blob: base64Encode(await file.readAsBytes()),
            ),
          );
        }
      case FileSystemEntityType.notFound:
        yield TextContent(text: 'File not found: $uri');
      default:
        yield TextContent(
          text: 'Unsupported file system entity type $entityType',
        );
    }
  }

  @visibleForTesting
  static final readPackageUris = Tool(
    name: 'read_package_uris',
    description:
        'Reads "package" scheme URIs which represent paths under the lib '
        'directory of Dart package dependencies. Package uris are always '
        'relative, and the first segment is the package name. For example, the '
        'URI "package:test/test.dart" represents the path "lib/test.dart" under '
        'the "test" package. This API supports both reading files and listing '
        'directories.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.uris: Schema.list(
          description: 'All the package URIs to read.',
          items: Schema.string(),
        ),
        ParameterNames.root: rootSchema,
      },
      required: [ParameterNames.uris, ParameterNames.root],
      additionalProperties: false,
    ),
  )..categories = [FeatureCategory.dart, FeatureCategory.flutter];
}

/// Shared error result for when no package config is found.
CallToolResult noPackageConfigFound(Root root) => CallToolResult(
  isError: true,
  content: [
    TextContent(
      text:
          'No package config found for root ${root.uri}. Have you ran `pub '
          'get` in this project?',
    ),
  ],
)..failureReason = CallToolFailureReason.noPackageConfigFound;

TextContent packageNotFoundText(String packageName) => TextContent(
  text:
      'The package "$packageName" was not found in your package config, '
      'make sure it is listed in your dependencies, or use `pub add` to '
      'add it.',
);
