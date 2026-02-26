// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:mustache_template/mustache_template.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../features_configuration.dart';
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
  Completer<void>? _assetsDiscoveryCompleter = Completer();

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
    // TODO: If we are currently discovering assets, wait for the current
    // discovery to complete before doing it again.
    _assetsDiscoveryCompleter ??= Completer();
    final allPackages = <String, Package>{};
    final knownRoots = await roots;

    for (final root in knownRoots) {
      // TODO: Handle packages in subdirectories.
      final rootDir = fileSystem.directory(Uri.parse(root.uri));
      if (!rootDir.existsSync()) continue;

      // TODO: Make sure we haven't already read this package config.
      // TODO: Elicit for permission to load resources from this package.
      // TODO: Only load resources from immediate dependencies.
      final packageConfig = await findPackageConfig(rootDir);
      if (packageConfig != null) {
        for (final package in packageConfig.packages) {
          // TODO: If we have already read this package config,
          // then only overwrite it if this version is newer.
          allPackages[package.name] = package;
        }
      }
    }

    // TODO: Only update the resources and prompts that have changed.
    _dynamicallyAddedResources.forEach(removeResource);
    _dynamicallyAddedResources.clear();
    _dynamicallyAddedPrompts.forEach(removePrompt);
    _dynamicallyAddedPrompts.clear();

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
      final configPath = fileSystem.path.join(mcpExtensionsDir, 'config.yaml');
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

            // TODO: Do add private resources if they are under a known root.
            final isPrivate = resourceObj['visibility'] == 'private';
            if (isPrivate) continue;

            final rawPath = resourceObj['path'] as String;
            final fullPath = fileSystem.path.join(mcpExtensionsDir, rawPath);
            final name = resourceObj['name'] as String? ?? p.basename(rawPath);
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
            final uri = 'package-root://${package.name}/$osNeutralRelativePath';

            final resource = Resource(
              uri: uri,
              name: name,
              description: title != null
                  ? '$title: ${description ?? ''}'
                  : description,
            );

            addResource(resource, (request) async {
              final targetFile = fileSystem.file(fullPath);
              if (!targetFile.existsSync()) {
                throw ArgumentError('Resource file not found: $uri');
              }
              final contents = await targetFile.readAsString();
              return ReadResourceResult(
                contents: [
                  // TODO: Support other kinds of content like images etc.
                  TextResourceContents(uri: uri, text: contents),
                ],
              );
            });
            _dynamicallyAddedResources.add(uri);
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
            if (isPrivate) continue;

            final rawPath = promptObj['path'] as String;
            final fullPath = p.join(mcpExtensionsDir, rawPath);
            final name = promptObj['name'] as String;
            final title = promptObj['title'] as String?;
            final description = promptObj['description'] as String?;
            final argumentsList = promptObj['arguments'] as YamlList?;

            final promptArguments =
                argumentsList
                    ?.map(
                      (e) => PromptArgument(name: e.toString(), required: true),
                    )
                    .toList() ??
                [];

            final prompt = Prompt(
              name: name,
              title: title,
              description: description,
              arguments: promptArguments,
            )..categories = [FeatureCategory.packageDeps];

            addPrompt(prompt, (request) async {
              final targetFile = fileSystem.file(fullPath);
              if (!targetFile.existsSync()) {
                throw ArgumentError('Prompt file not found');
              }
              final templateContent = await targetFile.readAsString();
              final template = Template(templateContent, name: name);

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
            _dynamicallyAddedPrompts.add(name);
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
    _assetsDiscoveryCompleter?.complete();
    _assetsDiscoveryCompleter = null;
  }

  /// The set of resources that were dynamically added from packaged AI assets.
  final Set<String> _dynamicallyAddedResources = {};

  /// The set of prompts that were dynamically added from packaged AI assets.
  final Set<String> _dynamicallyAddedPrompts = {};
}
