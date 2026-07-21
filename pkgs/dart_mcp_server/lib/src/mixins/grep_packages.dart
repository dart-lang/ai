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
import '../utils/extensions.dart';
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
    final rejectedArgs = _rejectedRipGrepArgs(grepArgs);
    if (rejectedArgs.isNotEmpty) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'Refusing to run ripgrep: the following arguments are not '
                'permitted: ${rejectedArgs.join(', ')}. Only search-shaping '
                'flags are allowed (e.g. -e, -i, -w, -n, -F, -g, -A/-B/-C, '
                '-l, -c, -v); pass the pattern via `-e <pattern>`.',
          ),
        ],
      );
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
          await runRipGrep(
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
  Future<Content> runRipGrep(
    Package package,
    String ripGrepExecutable,
    List<String> args, {
    required String searchDir,
  }) async {
    final searchUri = searchDir.isEmpty
        ? package.root
        : package.root.resolve(searchDir.withTrailingSlash);
    // Don't allow the `searchDir` to escape the package root.
    if (!isUnderRoot(
      Root(uri: package.root.toString()),
      searchUri.toString(),
      fileSystem,
    )) {
      return TextContent(
        text:
            'The searchDir "$searchDir" attempted to escape the root of '
            'package `${package.name}`.',
      );
    }

    final packagePath = cleanFilePath(searchUri.path);
    final result = await processManager.run([
      ripGrepExecutable,
      ...args,
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

  /// Returns the elements of [args] that are not on the ripgrep allow-list.
  ///
  /// An element is allowed iff it is an [_rgBoolFlags] entry, an
  /// [_rgValueFlags] entry (whose following element is then accepted as the
  /// value), a `--flag=value` form of either, or a run of short boolean flags
  /// (e.g. `-in`, `-uuu`). Bare positionals are rejected so callers cannot add
  /// extra search paths; patterns must be passed via `-e`.
  static List<String> _rejectedRipGrepArgs(List<String> args) {
    final rejected = <String>[];
    var expectValue = false;
    for (final arg in args) {
      if (expectValue) {
        expectValue = false;
        continue;
      }
      if (arg.startsWith('--') && arg.length > 2) {
        final eq = arg.indexOf('=');
        final name = eq == -1 ? arg : arg.substring(0, eq);
        if (_rgValueFlags.contains(name)) {
          if (eq == -1) expectValue = true;
        } else if (!_rgBoolFlags.contains(name)) {
          rejected.add(arg);
        }
      } else if (arg.startsWith('-') && arg.length == 2) {
        if (_rgValueFlags.contains(arg)) {
          expectValue = true;
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
    return rejected;
  }
}
