// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:extension_discovery/extension_discovery.dart';
import 'package:file/file.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../features_configuration.dart';
import '../mustachio/render_simple.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import 'roots_fallback_support.dart';

/// Implements the Packaged AI Assets proposal at
/// https://flutter.dev/go/packaged-ai-assets
///
/// Discover resources and prompts from `extension/mcp/config.yaml` of the
/// workspace roots and their dependencies.
base mixin PackagedAiAssetsSupport
    on ResourcesSupport, PromptsSupport, RootsFallbackSupport
    implements FileSystemSupport {
  /// Completer for the assets discovery process.
  Completer<void>? _assetsDiscoveryCompleter;

  /// The set of resources that were dynamically added from packaged AI assets.
  final Set<String> _dynamicallyAddedResources = {};

  /// The set of prompts that were dynamically added from packaged AI assets.
  final Set<String> _dynamicallyAddedPrompts = {};

  @override
  Future<void> updateRoots() async {
    await super.updateRoots();
    await _discoverAssets();
  }

  @override
  FutureOr<ListPromptsResult> listPrompts([ListPromptsRequest? request]) async {
    try {
      /// Wait for the assets to be discovered, but don't fail if it times out.
      await _assetsDiscoveryCompleter?.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } catch (e, s) {
      log(
        LoggingLevel.warning,
        'Timed out waiting for package prompts to be discovered: $e\n$s',
      );
    }
    return await super.listPrompts(request);
  }

  /// Discover resources and prompts from `extension/mcp/config.yaml` of the
  /// workspace roots and their dependencies.
  Future<void> _discoverAssets() async {
    // TODO: Elicit for permission to load AI assets from packages.
    if (_assetsDiscoveryCompleter != null &&
        !_assetsDiscoveryCompleter!.isCompleted) {
      return _assetsDiscoveryCompleter!.future;
    }
    _assetsDiscoveryCompleter = Completer<void>();
    try {
      final knownRoots = await roots;
      // Extensions by package name.
      final extensions = <String, Extension>{};
      final seenPackageConfigs = <Uri>{};

      for (final root in knownRoots) {
        final rootDir = fileSystem.directory(Uri.parse(root.uri));
        if (!rootDir.existsSync()) continue;

        final pubspecDirs = _findPubspecDirectories(rootDir, fileSystem);
        await for (var dir in pubspecDirs) {
          final packageConfigUri = findPackageConfig(dir.uri);
          if (packageConfigUri == null ||
              !seenPackageConfigs.add(packageConfigUri)) {
            continue;
          }

          try {
            final foundExtensions = await findExtensions(
              'mcp',
              packageConfig: packageConfigUri,
            );

            for (final extension in foundExtensions) {
              // TODO: Replace with newer version of the package if we find one.
              if (!extensions.containsKey(extension.package)) {
                extensions[extension.package] = extension;
              }
            }
          } catch (e, s) {
            log(
              LoggingLevel.warning,
              'Error discovering extensions for ${dir.path}: $e\n$s',
            );
          }
        }
      }

      final newResources = <String>{};
      final newPrompts = <String>{};

      for (final extension in extensions.values) {
        try {
          if (extension.rootUri.scheme != 'file') {
            log(
              LoggingLevel.warning,
              'Package ${extension.package} has a non-file root: '
              '${extension.rootUri}',
            );
            continue;
          }

          final packageRootDir = fileSystem.directory(
            extension.rootUri,
          );
          final mcpExtensionDir = fileSystem.path.join(
            packageRootDir.path,
            'extension',
            'mcp',
          );

          final config = extension.config;
          final resources = config['resources'];
          if (resources is List) {
            for (final resourceObj in resources) {
              if (resourceObj is! Map) continue;

              final isPrivate = resourceObj['visibility'] == 'private';
              final rawPath = resourceObj['path'] as String;

              // The config path is always in URL format, so we need to split
              // it by the URL separator and join using the current file system
              // semantics.
              final fullPath = fileSystem.path.joinAll([
                mcpExtensionDir,
                ...rawPath.split(p.url.separator),
              ]);

              if (isPrivate &&
                  !knownRoots.any(
                    (r) => isUnderRoot(r, fullPath, fileSystem),
                  )) {
                continue;
              }

              final name =
                  resourceObj['name'] as String? ?? p.url.basename(rawPath);
              final title = resourceObj['title'] as String?;
              final description = resourceObj['description'] as String?;

              final relativeToRoot = fileSystem.path.relative(
                fullPath,
                from: packageRootDir.path,
              );
              final uriRelativePath = relativeToRoot.replaceAll(
                fileSystem.path.separator,
                p.url.separator,
              );
              final uri = 
                  'package-root:${extension.package}/$uriRelativePath';

              final resource = Resource(
                uri: uri,
                name: name,
                description: title != null
                    ? '$title: ${description ?? ''}'
                    : description,
              );

              newResources.add(uri);
              if (_dynamicallyAddedResources.add(uri)) {
                addResource(resource, (request) async {
                  final targetFile = fileSystem.file(fullPath);
                  if (!targetFile.existsSync()) {
                    throw ArgumentError('Resource file not found: $uri');
                  }

                  final mimeType = lookupMimeType(fullPath) ?? '';
                  ResourceContents contentResult;
                  try {
                    // Try to read as text first, then fall back on a
                    // binary blob if that fails.
                    final contents = await targetFile.readAsString();
                    contentResult = TextResourceContents(
                      uri: uri,
                      text: contents,
                      mimeType: mimeType.isEmpty ? null : mimeType,
                    );
                  } catch (_) {
                    final bytes = await targetFile.readAsBytes();
                    contentResult = BlobResourceContents(
                      uri: uri,
                      blob: base64Encode(bytes),
                      mimeType: mimeType.isEmpty ? null : mimeType,
                    );
                  }
                  return ReadResourceResult(contents: [contentResult]);
                });
              } else {
                updateResource(resource);
              }
            }
          }

          final prompts = config['prompts'];
          if (prompts is List) {
            for (final promptObj in prompts) {
              if (promptObj is! Map) {
                log(
                  LoggingLevel.warning,
                  'Invalid prompt object from package '
                  '${extension.package}: $promptObj',
                );
                continue;
              }

              final isPrivate = promptObj['visibility'] == 'private';
              if (isPrivate &&
                  !knownRoots.any(
                    (r) => packageRootDir.path.startsWith(
                      Uri.parse(r.uri).toFilePath(),
                    ),
                  )) {
                continue;
              }

              final rawPath = promptObj['path'] as String;
              final fullPath = p.join(mcpExtensionDir, rawPath);
              final name = promptObj['name'] as String;
              final title = promptObj['title'] as String?;
              final description = promptObj['description'] as String?;
              final promptArguments = (promptObj['arguments'] as List?)
                  ?.map((entry) {
                    if (entry is! Map) {
                      log(
                        LoggingLevel.warning,
                        'Invalid prompt argument object from package '
                        '${extension.package}: $entry',
                      );
                      return null;
                    }
                    return PromptArgument.fromMap(
                      entry.cast<String, Object?>(),
                    );
                  })
                  // Can't use .nonNulls because PromptArgument technically is
                  // an Object?, and we just get Iterable<Object?> back.
                  .whereType<PromptArgument>()
                  .toList();

              final prompt = Prompt(
                name: name,
                title: title,
                description: description,
                arguments: promptArguments,
              )..categories = [FeatureCategory.packageDeps];

              newPrompts.add(name);
              if (_dynamicallyAddedPrompts.add(name)) {
                addPrompt(prompt, (request) async {
                  final targetFile = fileSystem.file(fullPath);
                  if (!targetFile.existsSync()) {
                    throw ArgumentError('Prompt file not found');
                  }
                  final mapArgs = request.arguments ?? <String, Object?>{};
                  for (final arg in (prompt.arguments ?? []).where(
                    (arg) => arg.required == true,
                  )) {
                    if (!mapArgs.containsKey(arg.name)) {
                      throw ArgumentError(
                        'Missing required prompt argument: ${arg.name}',
                      );
                    }
                  }
                  final templateContent = await targetFile.readAsString();
                  final renderedContent = renderMustachio(
                    templateContent,
                    mapArgs,
                  );

                  return GetPromptResult(
                    description: description,
                    messages: [
                      PromptMessage(
                        role: Role.user,
                        content: TextContent(text: renderedContent),
                      ),
                    ],
                  );
                });
              } else {
                // TODO: If the prompt changed, remove it and add it back.
                // Prompts do not support change notifications.
              }
            }
          }
        } catch (e, s) {
          log(
            LoggingLevel.error,
            'Error loading packaged AI assets from package '
            '${extension.package}: $e\n$s',
          );
        }
      }
      final resourcesToRemove = _dynamicallyAddedResources.difference(
        newResources,
      );
      for (final uri in resourcesToRemove) {
        removeResource(uri);
      }
      _dynamicallyAddedResources.removeAll(resourcesToRemove);

      final promptsToRemove = _dynamicallyAddedPrompts.difference(newPrompts);
      for (final name in promptsToRemove) {
        removePrompt(name);
      }
      _dynamicallyAddedPrompts.removeAll(promptsToRemove);
    } finally {
      _assetsDiscoveryCompleter?.complete();
      _assetsDiscoveryCompleter = null;
    }
  }

  /// Recursively find all directories containing a `pubspec.yaml` file.
  Stream<Directory> _findPubspecDirectories(
    Directory dir,
    FileSystem fileSystem, {
    int depth = 0,
    int maxDepth = 5,
  }) async* {
    if (depth > maxDepth) return;
    try {
      final hasPubspec = fileSystem
          .file(p.join(dir.path, 'pubspec.yaml'))
          .existsSync();
      if (hasPubspec) yield dir;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.startsWith('.') ||
              name == 'build' ||
              name == 'ios' ||
              name == 'android') {
            continue;
          }
          yield* _findPubspecDirectories(
            entity,
            fileSystem,
            depth: depth + 1,
            maxDepth: maxDepth,
          );
        }
      }
    } catch (e, s) {
      log(LoggingLevel.error, 'Error finding pubspec.yaml files: $e\n$s');
    }
  }
}
