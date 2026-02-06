// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform, ProcessResult;

import 'package:cli_util/cli_util.dart';
import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';

import '../features_configuration.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import '../utils/names.dart';
import '../utils/process_manager.dart';
import 'package_uri_reader.dart';

/// Adds a tool for grepping files in the project and its dependencies.
base mixin GrepSupport
    on ToolsSupport, RootsTrackingSupport, ElicitationRequestSupport
    implements FileSystemSupport, ProcessManagerSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(ripGrepPackagesTool, _ripGrepPackages);
    return super.initialize(request);
  }

  @visibleForTesting
  static final List<Tool> allTools = [ripGrepPackagesTool];

  /// Grep files in the project and its dependencies using ripgrep, see the
  /// [ripGrepPackagesTool] tool definition.
  Future<CallToolResult> _ripGrepPackages(CallToolRequest request) async {
    final args = request.arguments!;
    final validated = validateRootConfig(
      args,
      fileSystem: fileSystem,
      knownRoots: await roots,
    );
    if (validated.errorResult case final error?) {
      return error;
    }

    final ripGrepExecutable =
        await _checkForRipGrep() ?? await tryInstallRipGrep();
    if (ripGrepExecutable == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'ripgrep not found in PATH. Please install ripgrep and add it '
                'to your PATH: https://github.com/BurntSushi/ripgrep',
          ),
        ],
      );
    }

    // The root is always non-null if there is no error present.
    final root = validated.root!;
    final rootDir = fileSystem.directory(Uri.parse(root.uri));

    // Get the package config for the root so we know where to search.
    final packageConfig = await findPackageConfig(rootDir);
    if (packageConfig == null) {
      return noPackageConfigFound(root);
    }

    final resultContent = <Content>[];
    final packageNames = (args[ParameterNames.packageNames] as List<Object?>)
        .cast<String>();
    final grepArgs = (args[ParameterNames.arguments] as List<Object?>)
        .cast<String>();

    // Note that we don't ever set `isError: true` except for unhandled errors,
    // because some packages might work, while others fail. We just add a note
    // about failures to the output and continue.
    for (var name in packageNames) {
      final package = packageConfig[name];
      if (package == null) {
        resultContent.add(packageNotFoundText(name));
        continue;
      }
      try {
        resultContent.add(
          await runRipGrep(package, ripGrepExecutable, grepArgs),
        );
      } catch (e) {
        resultContent.add(
          TextContent(text: 'Error running ripgrep in `$name`: $e'),
        );
      }
    }

    return CallToolResult(content: resultContent);
  }

  /// Runs ripgrep in [package] with [args].
  Future<Content> runRipGrep(
    Package package,
    String ripGrepExecutable,
    List<String> args,
  ) async {
    var packagePath = package.packageUriRoot.path;
    // On windows, we get paths like "/C:/Users/...", and need to strip out the
    // leading slash.
    if (Platform.isWindows &&
        packagePath.startsWith('/') &&
        packagePath.contains(':')) {
      packagePath = packagePath.substring(1);
    }
    final result = await processManager.run([
      ripGrepExecutable,
      ...args,
      '--path-separator=/', // Ensure paths are in URL format
      packagePath,
    ]);

    if (result.exitCode == 0) {
      final text = (result.stdout as String).replaceAll(
        packagePath,
        'package:${package.name}/',
      );
      return TextContent(text: text);
    } else if (result.exitCode == 1) {
      // Exit code 1 means no matches were found, which is not an error.
      return TextContent(text: 'No matches in package `${package.name}`');
    } else {
      return TextContent(
        text:
            'Error running ripgrep in `${package.name}` (exit code '
            '${result.exitCode}):\n'
            '${result.stderr}',
      );
    }
  }

  static final ripGrepPackagesTool = Tool(
    name: 'rip_grep_packages',
    description:
        'Uses ripgrep to find patterns in package dependencies. Note '
        'that ripgrep must be installed already, see '
        'https://github.com/BurntSushi/ripgrep for instructions.',
    inputSchema: Schema.object(
      properties: {
        ParameterNames.packageNames: Schema.list(
          items: Schema.string(
            description:
                'The names of the packages to run ripgrep in. Each package '
                'will run a separate ripgrep command with the given '
                'arguments and the package URI root search path.',
          ),
        ),
        ParameterNames.arguments: Schema.list(
          description:
              'The arguments to pass to ripgrep. Note that two arguments '
              'will be added to the command: `--path-separator=/` and the '
              'package URI root as the search path.',
          items: Schema.string(),
          minItems: 1,
        ),
        ParameterNames.root: rootSchema,
      },
      required: [
        ParameterNames.arguments,
        ParameterNames.packageNames,
        ParameterNames.root,
      ],
    ),
  )..categories = [FeatureCategory.dart, FeatureCategory.flutter];

  /// Checks if ripgrep is installed and returns the path to the executable if
  /// so.
  ///
  /// This will first use the one on PATH if available, and then fall back to a
  /// custom one installed by this tool, if the user approves the installation.
  Future<String?> _checkForRipGrep() async {
    if (processManager.canRun(_ripGrepName)) return _ripGrepName;
    final customRipGrepPath = _customRipGrepFile().path;
    if (processManager.canRun(customRipGrepPath)) return customRipGrepPath;
    return null;
  }

  /// Elicits for approval to install ripgrep, and installs it if approved.
  ///
  /// Returns the path to the installed executable, or null if the user does not
  /// approve the installation.
  ///
  /// [installDir] is the directory to install ripgrep to. If null, the default
  /// install directory will be used.
  @visibleForTesting
  Future<String?> tryInstallRipGrep({Directory? installDir}) async {
    // If the client does not support elicitation, we cannot install ripgrep
    // because we can't get consent.
    if (clientCapabilities.elicitation == null) return null;
    final elicitResult = await elicit(
      ElicitRequest(
        message: 'Ripgrep is required to run this tool, can I install it?',
        requestedSchema: Schema.object(),
      ),
    );
    // The user did not approve the installation.
    if (elicitResult.action != ElicitationAction.accept) return null;

    // We use a specific version because its hard coded into the release asset
    // name, and we want to avoid hitting the github API and getting rate
    // limited.
    const version = '15.0.0';
    final asset = _ripGrepAssetDownloadName();
    final filename = 'ripgrep-v$version-$asset';
    final url = Uri.parse(
      'https://github.com/microsoft/ripgrep-prebuilt/releases/download/v$version/$filename',
    );

    final downloadDir = await fileSystem.systemTempDirectory.createTemp(
      'dart_mcp_ripgrep',
    );
    try {
      final downloadFile = downloadDir.childFile(filename);
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw StateError(
          'Failed to download ripgrep from $url: ${response.statusCode} '
          '${response.reasonPhrase}',
        );
      }
      await downloadFile.writeAsBytes(response.bodyBytes);

      installDir ??= fileSystem.directory(_defaultInstallDir);
      if (!installDir.existsSync()) {
        await installDir.create(recursive: true);
      }
      ProcessResult result;
      if (filename.endsWith('.zip') && processManager.canRun('powershell')) {
        result = await processManager.run([
          'powershell',
          '-Command',
          'Expand-Archive -Path "${downloadFile.path}" '
              '-DestinationPath "${installDir.path}" -Force',
        ]);
      } else {
        // Linux/Mac + Windows fallback: Use tar
        result = await processManager.run([
          Platform.isWindows ? 'tar.exe' : 'tar',
          'xvf',
          downloadFile.path,
          '-C',
          installDir.path,
        ]);
      }
      if (result.exitCode != 0) {
        throw StateError(
          'Failed to extract ripgrep: ${result.stdout}\n${result.stderr}',
        );
      }

      // Find the binary in the extracted files, ensure it is executable.
      final installedBinary = _customRipGrepFile(installDir);
      if (!(await installedBinary.exists())) {
        throw StateError('Could not find ripgrep binary after extraction');
      }
      if (!Platform.isWindows) {
        await processManager.run(['chmod', '+x', installedBinary.path]);
      }
      return installedBinary.path;
    } finally {
      await downloadDir.delete(recursive: true);
    }
  }

  /// Returns the name of the ripgrep asset to download for the current
  /// platform.
  String _ripGrepAssetDownloadName() {
    final abi = ffi.Abi.current();
    return switch (abi) {
      ffi.Abi.macosArm64 => 'aarch64-apple-darwin.tar.gz',
      ffi.Abi.macosX64 => 'x86_64-apple-darwin.tar.gz',
      ffi.Abi.windowsX64 => 'x86_64-pc-windows-msvc.zip',
      ffi.Abi.windowsArm64 => 'aarch64-pc-windows-msvc.zip',
      ffi.Abi.linuxX64 => 'x86_64-unknown-linux-musl.tar.gz',
      ffi.Abi.linuxArm64 => 'aarch64-unknown-linux-gnu.tar.gz',
      ffi.Abi.linuxArm => 'arm-unknown-linux-gnueabihf.tar.gz',
      _ => throw StateError(
        'Unsupported platform, unable to download ripgrep: $abi',
      ),
    };
  }

  /// The name of the ripgrep executable on this platform.
  String get _ripGrepName => Platform.isWindows ? 'rg.exe' : 'rg';

  /// The path to the custom ripgrep executable installed by this tool.
  File _customRipGrepFile([Directory? installDir]) =>
      (installDir ?? _defaultInstallDir).childFile(_ripGrepName);

  /// The default install directory for ripgrep.
  Directory get _defaultInstallDir => fileSystem
      .directory(applicationConfigHome('dart_mcp_server'))
      .childDirectory('bin');
}
