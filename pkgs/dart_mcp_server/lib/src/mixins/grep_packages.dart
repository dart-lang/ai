// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform, ProcessResult;

import 'package:cli_util/cli_util.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_mcp/server.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';

import '../features_configuration.dart';
import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import '../utils/names.dart';
import '../utils/package_uris.dart';
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
        await _checkForRipGrep() ??
        await tryInstallRipGrep(progressToken: request.meta?.progressToken);
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

    // The `arguments` list is forwarded into ripgrep's argv. ripgrep has flags
    // that execute arbitrary commands (`--pre`), read arbitrary files
    // (`-f`/`--file`), or follow symlinks out of the package (`-L`). Since this
    // tool is callable by an LLM that may be acting on injected instructions,
    // restrict the arguments to a fixed allow-list of read-only, search-shaping
    // options and require patterns to be supplied via `-e`/`--regexp`.
    final validationError = _validateRipGrepArgs(grepArgs);
    if (validationError != null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: validationError)],
      )..failureReason = CallToolFailureReason.argumentError;
    }

    final searchDir = args[ParameterNames.searchDir] as String? ?? 'lib';

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
          await _runRipGrep(
            package,
            ripGrepExecutable,
            grepArgs,
            searchDir: searchDir,
          ),
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
  Future<Content> _runRipGrep(
    Package package,
    String ripGrepExecutable,
    List<String> args, {
    required String searchDir,
  }) async {
    if (package.root.scheme != 'file') {
      return TextContent(
        text:
            'Unexpected root URI for package `${package.name}` '
            '("${package.root.scheme}"), only "file" schemes are supported.',
      );
    }

    final packageRootDir = fileSystem.directory(package.root);
    final searchDirectory = searchDir.isEmpty
        ? packageRootDir
        : fileSystem.directory(
            fileSystem.path.join(packageRootDir.path, searchDir),
          );
    // Don't allow `searchDir` to escape the package root, lexically or via
    // symlinks.
    if (fileSystem.path.isAbsolute(searchDir) ||
        fileSystem.path.isRootRelative(searchDir) ||
        !isUnderRoot(
          Root(uri: packageRootDir.uri.toString()),
          searchDirectory.uri.toString(),
          fileSystem,
        ) ||
        !await resolvesWithinPackageRoot(
          packageRootDir,
          searchDirectory.path,
          fileSystem,
        )) {
      return TextContent(
        text:
            'The searchDir "$searchDir" attempted to escape the root of '
            'package `${package.name}`.',
      );
    }

    final packagePath = cleanFilePath(searchDirectory.uri.path);
    final result = await processManager.run([
      ripGrepExecutable,
      ...args,
      // Ignore `RIPGREP_CONFIG_PATH` so user config files don't alter flags.
      '--no-config',
      // Explicitly disable following symlinks during directory traversal.
      '--no-follow',
      '--path-separator=/', // Ensure paths are in URL format
      '--', // [args] is allow-listed, but be explicit about end-of-options.
      packagePath,
    ]);

    if (result.exitCode == 0) {
      var text = result.stdout as String;
      text = substitutePackageUris(text, package);

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
                'arguments.',
          ),
        ),
        ParameterNames.arguments: Schema.list(
          description:
              'The arguments to pass to ripgrep. Pass the search pattern via '
              '`-e <pattern>`. Only read-only search-shaping flags are '
              'allowed (e.g. -e, -i, -w, -n, -F, -g, -t, -A/-B/-C, -m, -l, '
              '-c, -v, -o, -U, -P, --hidden). The search path and '
              '`--path-separator=/` are appended automatically; do not pass '
              'paths here.',
          items: Schema.string(),
          minItems: 1,
        ),
        ParameterNames.searchDir: Schema.string(
          description:
              'The directory to search within the package. Defaults to "lib". '
              'Pass an empty string to search the entire package root '
              '(e.g. for searching "example" or "test" directories).',
        ),
        ParameterNames.root: rootSchema,
      },
      required: [
        ParameterNames.arguments,
        ParameterNames.packageNames,
        ParameterNames.root,
      ],
      additionalProperties: false,
    ),
  )..categories = [FeatureCategory.packageDeps];

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
  ///
  /// If [progressToken] is passed, it will be added to the [ElicitRequest]
  /// metadata. This is primarily used to forward on progress tokens, which is
  /// required by some clients (it links the elicitation to a tool call).
  @visibleForTesting
  Future<String?> tryInstallRipGrep({
    Directory? installDir,
    ProgressToken? progressToken,
  }) async {
    // If the client does not support elicitation, we cannot install ripgrep
    // because we can't get consent.
    if (clientCapabilities.elicitation == null) return null;
    final meta = progressToken != null
        ? MetaWithProgressToken(progressToken: progressToken)
        : null;
    final elicitResult = await elicit(
      ElicitRequest.form(
        message: 'Ripgrep is required to run this tool, can I install it?',
        requestedSchema: Schema.object(),
        meta: meta,
      ),
    );
    // The user did not approve the installation.
    if (elicitResult.action != ElicitationAction.accept) return null;

    final asset = _ripGrepAsset();
    final filename = 'ripgrep-v$_ripGrepVersion-${asset.name}';
    final url = Uri.parse(
      'https://github.com/microsoft/ripgrep-prebuilt/releases/download/v$_ripGrepVersion/$filename',
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
      // Verify the archive checksum since GitHub release assets are mutable.
      final actualDigest = sha256.convert(response.bodyBytes).toString();
      if (actualDigest != asset.sha256) {
        throw StateError(
          'SHA-256 mismatch for ripgrep download from $url '
          '(expected ${asset.sha256}, got $actualDigest).',
        );
      }
      await downloadFile.writeAsBytes(response.bodyBytes);

      installDir ??= fileSystem.directory(_defaultInstallDir);
      if (!installDir.existsSync()) {
        await installDir.create(recursive: true);
      }
      final tarArgs = ['xvf', downloadFile.path, '-C', installDir.path];
      // Commands to try in order until one succeeds.
      final extractCommands = <List<String>>[];
      if (filename.endsWith('.zip')) {
        // Prefer the built-in `tar.exe` on Windows over `Expand-Archive`,
        // which can fail in some environments. Use its full path since GNU
        // `tar` on `PATH` cannot extract `.zip` files.
        final systemRoot = Platform.environment['SystemRoot'];
        if (systemRoot != null) {
          final systemTar = fileSystem.path.join(
            systemRoot,
            'System32',
            'tar.exe',
          );
          if (processManager.canRun(systemTar)) {
            extractCommands.add([systemTar, ...tarArgs]);
          }
        }
        if (processManager.canRun('powershell')) {
          // Use single-quoted PowerShell strings so `$` in paths is treated
          // literally rather than expanded; in PowerShell single-quoted
          // strings, embedded single quotes are escaped by doubling them
          // (`''`).
          final escapedZip = downloadFile.path.replaceAll("'", "''");
          final escapedDest = installDir.path.replaceAll("'", "''");
          extractCommands.add([
            'powershell',
            // Skip loading user profile scripts and disable interactive prompts
            // during headless archive extraction.
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            // Use `-LiteralPath` so `[` and `]` in paths aren't interpreted as
            // PowerShell wildcard patterns, and `-ErrorAction Stop` so errors
            // cause a non-zero exit code.
            "Expand-Archive -LiteralPath '$escapedZip' "
                "-DestinationPath '$escapedDest' -Force -ErrorAction Stop",
          ]);
        }
      }
      if (extractCommands.isEmpty) {
        // Linux/Mac, and a last resort on Windows.
        extractCommands.add([
          Platform.isWindows ? 'tar.exe' : 'tar',
          ...tarArgs,
        ]);
      }

      late ProcessResult result;
      final failures = <String>[];
      for (final command in extractCommands) {
        result = await processManager.run(command);
        if (result.exitCode == 0) break;
        failures.add(
          '`${command.first}` exited with code ${result.exitCode}:\n'
          '${result.stdout}\n${result.stderr}',
        );
      }
      if (result.exitCode != 0) {
        throw StateError('Failed to extract ripgrep:\n${failures.join('\n')}');
      }

      // Find the binary in the extracted files, ensure it is executable.
      final installedBinary = _customRipGrepFile(installDir);
      if (!(await installedBinary.exists())) {
        // Include diagnostic details in case extraction silently failed (e.g.
        // antivirus quarantined the binary).
        final installDirContents = [
          await for (final entity in installDir.list()) entity.basename,
        ]..sort();
        final contentsDescription = installDirContents.isEmpty
            ? '(empty)'
            : installDirContents.join(', ');
        throw StateError(
          'Could not find ripgrep binary after extraction '
          '(expected ${installedBinary.path}).\n'
          'Contents of ${installDir.path}: $contentsDescription\n'
          'Extraction stdout: ${result.stdout}\n'
          'Extraction stderr: ${result.stderr}',
        );
      }
      if (!Platform.isWindows) {
        await processManager.run(['chmod', '+x', installedBinary.path]);
      }
      return installedBinary.path;
    } finally {
      await downloadDir.delete(recursive: true);
    }
  }

  /// The ripgrep version installed by [tryInstallRipGrep].
  ///
  /// We use a specific version because its hard coded into the release asset
  /// name, and we want to avoid hitting the github API and getting rate
  /// limited.
  ///
  /// Update the digests in [_ripGrepAsset] when changing this.
  static const _ripGrepVersion = '15.0.0';

  /// Returns the [_ripGrepVersion] release asset for the current platform.
  ({String name, String sha256}) _ripGrepAsset() {
    final abi = ffi.Abi.current();
    return switch (abi) {
      ffi.Abi.macosArm64 => (
        name: 'aarch64-apple-darwin.tar.gz',
        sha256:
            '16ded8d87db15333e8c06188ea2635dcde7f9869412f843e463a290f9d7493f3',
      ),
      ffi.Abi.macosX64 => (
        name: 'x86_64-apple-darwin.tar.gz',
        sha256:
            '9787387f2d01ee3382e5984c39beb457f445585d81f928a5b1a089706ffb6c8f',
      ),
      ffi.Abi.windowsX64 => (
        name: 'x86_64-pc-windows-msvc.zip',
        sha256:
            '5b7f6a3020739ac4bdf2c32300f14388456361bea054d35270a18a3c9949b932',
      ),
      ffi.Abi.windowsArm64 => (
        name: 'aarch64-pc-windows-msvc.zip',
        sha256:
            '77757a3a8fc99705062e2594d4bbf48aafaee0faca65816455edb0d671bd534e',
      ),
      ffi.Abi.linuxX64 => (
        name: 'x86_64-unknown-linux-musl.tar.gz',
        sha256:
            '9dd9306a2c44cdda31e2f4f3cf36f4d7148260d9371683e965d3c8992c205349',
      ),
      ffi.Abi.linuxArm64 => (
        name: 'aarch64-unknown-linux-gnu.tar.gz',
        sha256:
            '367e7b3110fb8ef0fd8e7e4907bf6ef6b04c5eed7a54659d98308c449cf3b8d9',
      ),
      ffi.Abi.linuxArm => (
        name: 'arm-unknown-linux-gnueabihf.tar.gz',
        sha256:
            '3a485967f7758a837f3b3838beae0d2f5828470e93f769a8d7cf2e78b1e525fe',
      ),
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
      .directory(BaseDirectories('dart_mcp_server').configHome)
      .childDirectory('bin');

  /// ripgrep long/short flags that consume the *next* argv element as a value.
  static const _rgValueFlags = {
    '-e',
    '--regexp',
    '-g',
    '--glob',
    '--iglob',
    '-t',
    '--type',
    '-T',
    '--type-not',
    '-A',
    '--after-context',
    '-B',
    '--before-context',
    '-C',
    '--context',
    '-m',
    '--max-count',
    '-M',
    '--max-columns',
    '-r',
    '--replace',
    '-E',
    '--encoding',
    '-j',
    '--threads',
    '--max-depth',
    '--max-filesize',
    '--context-separator',
    '--sort',
  };

  /// ripgrep boolean flags that only shape the search/output and are safe to
  /// forward verbatim.
  static const _rgBoolFlags = {
    '-i',
    '--ignore-case',
    '-s',
    '--case-sensitive',
    '-S',
    '--smart-case',
    '-w',
    '--word-regexp',
    '-x',
    '--line-regexp',
    '-F',
    '--fixed-strings',
    '-v',
    '--invert-match',
    '-n',
    '--line-number',
    '-N',
    '--no-line-number',
    '-H',
    '--with-filename',
    '-I',
    '--no-filename',
    '-l',
    '--files-with-matches',
    '--files-without-match',
    '-c',
    '--count',
    '--count-matches',
    '-o',
    '--only-matching',
    '-U',
    '--multiline',
    '--multiline-dotall',
    '-P',
    '--pcre2',
    '-u',
    '--unrestricted',
    '--hidden',
    '--no-ignore',
    '-a',
    '--text',
    '--trim',
    '--column',
    '--no-heading',
    '--heading',
  };

  /// Validates [args] against the ripgrep flag allow-list and returns an error
  /// message if any argument is disallowed or if no pattern flag is supplied.
  ///
  /// An element is allowed iff it is an [_rgBoolFlags] entry, an
  /// [_rgValueFlags] entry (whose following element is then accepted as the
  /// value), a `--flag=value` form of an [_rgValueFlags] entry, or a run of
  /// short boolean flags (e.g. `-in`, `-uuu`). Bare positionals are rejected
  /// and at least one `-e`/`--regexp` pattern flag must be present.
  static String? _validateRipGrepArgs(List<String> args) {
    final rejected = <String>[];
    String? pendingFlag;
    var hasPattern = false;
    for (final arg in args) {
      // Reject NUL characters (`\x00`), which `dart:io` treats as string
      // terminators when passing process arguments to the OS.
      if (arg.contains('\x00')) {
        rejected.add(arg);
        pendingFlag = null;
        continue;
      }
      if (pendingFlag != null) {
        if (pendingFlag == '-e' || pendingFlag == '--regexp') {
          hasPattern = true;
        }
        pendingFlag = null;
        continue;
      }
      if (arg.startsWith('--') && arg.length > 2) {
        final eq = arg.indexOf('=');
        final name = eq == -1 ? arg : arg.substring(0, eq);
        if (_rgValueFlags.contains(name)) {
          if (eq == -1) {
            pendingFlag = name;
          } else if (name == '--regexp') {
            hasPattern = true;
          }
        } else if (eq == -1 && _rgBoolFlags.contains(name)) {
          // Valid long boolean flag.
        } else {
          rejected.add(arg);
        }
      } else if (arg.startsWith('-') && arg.length == 2) {
        if (_rgValueFlags.contains(arg)) {
          pendingFlag = arg;
        } else if (!_rgBoolFlags.contains(arg)) {
          rejected.add(arg);
        }
      } else if (arg.startsWith('-') && arg.length > 2) {
        // Bundled short boolean flags, e.g. `-in`, `-uuu`.
        if (!arg
            .substring(1)
            .split('')
            .every((c) => _rgBoolFlags.contains('-$c'))) {
          rejected.add(arg);
        }
      } else {
        // Bare positional (`--`, `-`, or a path/pattern).
        rejected.add(arg);
      }
    }
    if (pendingFlag != null && args.isNotEmpty) {
      rejected.add(args.last);
    }
    if (rejected.isNotEmpty) {
      return 'Refusing to run ripgrep: the following arguments are not '
          'permitted: ${rejected.join(', ')}. Only search-shaping '
          'flags are allowed (e.g. -e, -i, -w, -n, -F, -g, -A/-B/-C, '
          '-l, -c, -v); pass the pattern via `-e <pattern>`.';
    }
    if (!hasPattern) {
      return 'Refusing to run ripgrep: at least one search pattern must be '
          'provided via `-e <pattern>` or `--regexp=<pattern>`.';
    }
    return null;
  }
}
