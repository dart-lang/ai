// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:mime/mime.dart';
import 'package:mustache_template/mustache_template.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../features_configuration.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import 'roots_fallback_support.dart';

/// Implements the Packaged AI Assets proposal at
/// https://flutter.dev/go/packaged-ai-assets
///
/// Discover resources and prompts from `extensions/mcp/config.yaml` of the
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
    await _assetsDiscoveryCompleter?.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    return await super.listPrompts(request);
  }

  /// Discover resources and prompts from `extensions/mcp/config.yaml` of the
  /// workspace roots and their dependencies.
  Future<void> _discoverAssets() async {
    // TODO: Elicit for permission to load AI assets from packages.
    if (_assetsDiscoveryCompleter != null &&
        !_assetsDiscoveryCompleter!.isCompleted) {
      return _assetsDiscoveryCompleter!.future;
    }
    _assetsDiscoveryCompleter = Completer<void>();
    try {
      final allPackages = <String, Package>{};
      final knownRoots = await roots;

      for (final root in knownRoots) {
        final rootDir = fileSystem.directory(Uri.parse(root.uri));
        if (!rootDir.existsSync()) continue;

        final pubspecDirs = _findPubspecDirectories(rootDir, fileSystem);
        await for (final dir in pubspecDirs) {
          final packageConfig = await findPackageConfig(dir);
          if (packageConfig == null) continue;
          // TODO: Only load resources and prompts from immediate dependencies.
          for (final package in packageConfig.packages) {
            // Only overwrite if this version is newer (for now, just add if
            // not present).
            // We also load all resources rather than just immediate dependencies,
            // because transient dependencies might have important tools too.
            if (!allPackages.containsKey(package.name)) {
              allPackages[package.name] = package;
            }
          }
        }
      }

      final newResources = <String>{};
      final newPrompts = <String>{};

      for (final package in allPackages.values) {
        if (package.root.scheme != 'file') {
          log(
            LoggingLevel.warning,
            'Package ${package.name} has a non-file root: ${package.root}',
          );
          continue;
        }

        final packageRootDir = fileSystem.directory(package.root.toFilePath());
        final mcpExtensionsDir = fileSystem.path.join(
          packageRootDir.path,
          'extensions',
          'mcp',
        );
        final configPath = fileSystem.path.join(
          mcpExtensionsDir,
          'config.yaml',
        );
        final configFile = fileSystem.file(configPath);

        if (!configFile.existsSync()) continue;

        try {
          final content = await configFile.readAsString();
          final yaml = loadYaml(content);

          if (yaml is! YamlMap) continue;

          final resources = yaml['resources'];
          if (resources is YamlList) {
            for (final resourceObj in resources) {
              if (resourceObj is! YamlMap) continue;

              final isPrivate = resourceObj['visibility'] == 'private';
              final rawPath = resourceObj['path'] as String;
              final fullPath = fileSystem.path.join(mcpExtensionsDir, rawPath);
              if (isPrivate &&
                  !knownRoots.any(
                    (r) => isUnderRoot(r, fullPath, fileSystem),
                  )) {
                continue;
              }

              final name =
                  resourceObj['name'] as String? ?? p.basename(rawPath);
              final title = resourceObj['title'] as String?;
              final description = resourceObj['description'] as String?;

              final relativeToRoot = p.relative(
                fullPath,
                from: packageRootDir.path,
              );
              final osNeutralRelativePath = relativeToRoot.replaceAll(
                p.separator,
                '/',
              );
              final uri =
                  'package-root://${package.name}/$osNeutralRelativePath';

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

          final prompts = yaml['prompts'];
          if (prompts is YamlList) {
            for (final promptObj in prompts) {
              if (promptObj is! YamlMap) {
                log(
                  LoggingLevel.warning,
                  'Invalid prompt object from package '
                  '${package.name}: $promptObj',
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
              final fullPath = p.join(mcpExtensionsDir, rawPath);
              final name = promptObj['name'] as String;
              final title = promptObj['title'] as String?;
              final description = promptObj['description'] as String?;
              final promptArguments = (promptObj['arguments'] as YamlList?)
                  ?.map((entry) {
                    if (entry is! YamlMap) {
                      log(
                        LoggingLevel.warning,
                        'Invalid prompt argument object from package '
                        '${package.name}: $entry',
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
                  final templateContent = await targetFile.readAsString();
                  final template = Template(
                    templateContent,
                    name: name,
                    lenient: true,
                  );

                  final mapArgs = request.arguments ?? <String, dynamic>{};
                  final rendered = template.renderString(mapArgs);

                  return GetPromptResult(
                    description: description,
                    messages: [
                      PromptMessage(
                        role: Role.user,
                        content: TextContent(text: rendered),
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
            '${package.name}: $e\n$s',
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
