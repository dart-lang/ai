// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/constants.dart';
import '../utils/file_system.dart';
import '../utils/process_manager.dart';
import '../utils/sdk.dart';

/// Mix this in to any MCPServer to add support for running Dart or Flutter CLI
/// commands like `dart fix`, `dart format`, and `flutter test`.
///
/// The MCPServer must already have the [ToolsSupport] and [LoggingSupport]
/// mixins applied.
base mixin DashCliSupport on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements ProcessManagerSupport, FileSystemSupport, SdkSupport {
  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    try {
      return super.initialize(request);
    } finally {
      // Can't call `supportsRoots` until after `super.initialize`.
      if (supportsRoots && sdk.dartSdkPath != null) {
        registerTool(dartFixTool, _runDartFixTool);
        registerTool(dartFormatTool, _runDartFormatTool);
        registerTool(runTestsTool, _runTests);
        registerTool(createProjectTool, _runCreateProjectTool);
      }
    }
  }

  /// Implementation of the [dartFixTool].
  Future<CallToolResult> _runDartFixTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      commandForRoot: (_, _, sdk) => sdk.dartExecutablePath,
      arguments: ['fix', '--apply'],
      commandDescription: 'dart fix',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [dartFormatTool].
  Future<CallToolResult> _runDartFormatTool(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      commandForRoot: (_, _, sdk) => sdk.dartExecutablePath,
      arguments: ['format'],
      commandDescription: 'dart format',
      processManager: processManager,
      defaultPaths: ['.'],
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [runTestsTool].
  Future<CallToolResult> _runTests(CallToolRequest request) async {
    final testRunnerArguments =
        request.arguments?[ParameterNames.testRunnerArgs]
            as Map<String, Object?>?;
    final hasReporterArg =
        testRunnerArguments?.containsKey('reporter') ?? false;
    return runCommandInRoots(
      request,
      arguments: [
        'test',
        if (!hasReporterArg) '--reporter=failures-only',
        ...?testRunnerArguments?.asCliArgs(),
      ],
      commandDescription: 'dart|flutter test',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [createProjectTool].
  Future<CallToolResult> _runCreateProjectTool(CallToolRequest request) async {
    final args = request.arguments;

    final errors = createProjectTool.inputSchema.validate(args);
    final projectType = args?[ParameterNames.projectType] as String?;
    if (projectType != 'dart' && projectType != 'flutter') {
      errors.add(
        ValidationError(
          ValidationErrorType.custom,
          path: [ParameterNames.projectType],
          details: 'Only `dart` and `flutter` are allowed values.',
        ),
      );
    }
    final directory = args![ParameterNames.directory] as String;
    if (p.isAbsolute(directory)) {
      errors.add(
        ValidationError(
          ValidationErrorType.custom,
          path: [ParameterNames.directory],
          details: 'Directory must be a relative path.',
        ),
      );
    }
    final platforms =
        ((args[ParameterNames.platform] as List?)?.cast<String>() ?? [])
            .toSet();
    if (projectType == 'flutter') {
      // Platforms are ignored for Dart, so no need to validate them.
      final invalidPlatforms = platforms.difference(_allowedFlutterPlatforms);
      if (invalidPlatforms.isNotEmpty) {
        final plural = invalidPlatforms.length > 1
            ? 'are not valid platforms'
            : 'is not a valid platform';
        errors.add(
          ValidationError(
            ValidationErrorType.custom,
            path: [ParameterNames.platform],
            details:
                '${invalidPlatforms.join(',')} $plural. Platforms '
                '${_allowedFlutterPlatforms.map((e) => '`$e`').join(', ')} '
                'are the only allowed values for the platform list argument.',
          ),
        );
      }
    }

    if (errors.isNotEmpty) {
      return CallToolResult(
        content: [
          for (final error in errors) Content.text(text: error.toErrorString()),
        ],
        isError: true,
      )..failureReason = CallToolFailureReason.argumentError;
    }

    final template = args[ParameterNames.template] as String?;

    final commandArgs = [
      'create',
      if (template != null && template.isNotEmpty) ...['--template', template],
      if (projectType == 'flutter' && platforms.isNotEmpty)
        '--platform=${platforms.join(',')}',
      // Create an "empty" project by default so the LLM doesn't have to deal
      // with all the boilerplate and comments.
      if (projectType == 'flutter' &&
          (args[ParameterNames.empty] as bool? ?? true))
        '--empty',
      directory,
    ];

    return runCommandInRoot(
      request,
      arguments: commandArgs,
      commandForRoot: (_, _, sdk) =>
          switch (projectType) {
                'dart' => sdk.dartExecutablePath,
                'flutter' => sdk.flutterExecutablePath,
                _ => StateError('Unknown project type: $projectType'),
              }
              as String,
      commandDescription: '$projectType create',
      fileSystem: fileSystem,
      processManager: processManager,
      knownRoots: await roots,
      sdk: sdk,
    );
  }

  static final dartFixTool = Tool(
    name: 'dart_fix',
    description: 'Runs `dart fix --apply` for the given project roots.',
    annotations: ToolAnnotations(title: 'Dart fix', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.roots: rootsSchema()},
    ),
  );

  static final dartFormatTool = Tool(
    name: 'dart_format',
    description: 'Runs `dart format .` for the given project roots.',
    annotations: ToolAnnotations(title: 'Dart format', destructiveHint: true),
    inputSchema: Schema.object(
      properties: {ParameterNames.roots: rootsSchema(supportsPaths: true)},
    ),
  );

  static final Tool runTestsTool = () {
    final cliSchemaJson =
        jsonDecode(_dartTestCliSchema) as Map<String, Object?>;
    const blocklist = {'color', 'debug', 'help', 'pause-after-load', 'version'};
    cliSchemaJson.removeWhere((argument, _) => blocklist.contains(argument));
    final cliSchema = Schema.fromMap(cliSchemaJson);
    return Tool(
      name: 'run_tests',
      description:
          'Run Dart or Flutter tests with an agent centric UX. '
          'ALWAYS use instead of `dart test` or `flutter test` shell commands.',
      annotations: ToolAnnotations(title: 'Run tests', readOnlyHint: true),
      inputSchema: Schema.object(
        properties: {
          ParameterNames.roots: rootsSchema(supportsPaths: true),
          ParameterNames.testRunnerArgs: cliSchema,
        },
      ),
    );
  }();

  static final createProjectTool = Tool(
    name: 'create_project',
    description: 'Creates a new Dart or Flutter project.',
    annotations: ToolAnnotations(
      title: 'Create project',
      destructiveHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.root: rootSchema,
        ParameterNames.directory: Schema.string(
          description:
              'The subdirectory in which to create the project, must '
              'be a relative path.',
        ),
        ParameterNames.projectType: Schema.string(
          description: "The type of project: 'dart' or 'flutter'.",
        ),
        ParameterNames.template: Schema.string(
          description:
              'The project template to use (e.g., "console-full", "app").',
        ),
        ParameterNames.platform: Schema.list(
          items: Schema.string(),
          description:
              'The list of platforms this project supports. Only valid '
              'for Flutter projects. The allowed values are '
              '${_allowedFlutterPlatforms.map((e) => '`$e`').join(', ')}. '
              'Defaults to creating a project for all platforms.',
        ),
        ParameterNames.empty: Schema.bool(
          description:
              'Whether or not to create an "empty" project with minimized '
              'boilerplate and example code. Defaults to true.',
        ),
      },
      required: [
        ParameterNames.directory,
        ParameterNames.projectType,
        ParameterNames.root,
      ],
    ),
  );

  static const _allowedFlutterPlatforms = {
    'web',
    'linux',
    'macos',
    'windows',
    'android',
    'ios',
  };
}

extension on Map<String, Object?> {
  Iterable<String> asCliArgs() sync* {
    for (final MapEntry(:key, :value) in entries) {
      if (value is List) {
        for (final element in value) {
          yield '--$key';
          yield element as String;
        }
        continue;
      }
      yield '--$key';
      if (value is bool) continue;
      yield value as String;
    }
  }
}

// Generated by the test runner using an un-merged commit.
// To update merge the latest argument changes to the `json-schema` branch and
// run with the `--json-help` argument. Pipe to `sed 's/\\/\\\\/g'` to escape
// as a Dart source string.
// https://github.com/dart-lang/test/pull/2508
const _dartTestCliSchema = '''
{"type":"object","properties":{"help":{"type":"boolean","description":"Show this usage information.\\ndefaults to \\"false\\""},"version":{"type":"boolean","description":"Show the package:test version.\\ndefaults to \\"false\\""},"name":{"type":"array","description":"A substring of the name of the test to run.\\nRegular expression syntax is supported.\\nIf passed multiple times, tests must match all substrings.\\ndefaults to \\"[]\\"","items":{"type":"string"}},"plain-name":{"type":"array","description":"A plain-text substring of the name of the test to run.\\nIf passed multiple times, tests must match all substrings.\\ndefaults to \\"[]\\"","items":{"type":"string"}},"tags":{"type":"array","description":"Run only tests with all of the specified tags.\\nSupports boolean selector syntax.\\ndefaults to \\"[]\\"","items":{"type":"string"}},"exclude-tags":{"type":"array","description":"Don't run tests with any of the specified tags.\\nSupports boolean selector syntax.\\ndefaults to \\"[]\\"","items":{"type":"string"}},"run-skipped":{"type":"boolean","description":"Run skipped tests instead of skipping them.\\ndefaults to \\"false\\""},"platform":{"type":"array","description":"The platform(s) on which to run the tests.\\n[vm (default), chrome, firefox, edge, node].\\nEach platform supports the following compilers:\\n[vm]: kernel (default), source, exe\\n[chrome]: dart2js (default), dart2wasm\\n[firefox]: dart2js (default), dart2wasm\\n[edge]: dart2js (default)\\n[node]: dart2js (default), dart2wasm\\ndefaults to \\"[]\\"","items":{"type":"string"}},"compiler":{"type":"array","description":"The compiler(s) to use to run tests, supported compilers are [dart2js, dart2wasm, exe, kernel, source].\\nEach platform has a default compiler but may support other compilers.\\nYou can target a compiler to a specific platform using arguments of the following form [<platform-selector>:]<compiler>.\\nIf a platform is specified but no given compiler is supported for that platform, then it will use its default compiler.\\ndefaults to \\"[]\\"","items":{"type":"string"}},"preset":{"type":"array","description":"The configuration preset(s) to use.\\ndefaults to \\"[]\\"","items":{"type":"string"}},"concurrency":{"type":"string","description":"The number of concurrent test suites run.\\ndefaults to \\"8\\""},"total-shards":{"type":"string","description":"The total number of invocations of the test runner being run."},"shard-index":{"type":"string","description":"The index of this test runner invocation (of --total-shards)."},"timeout":{"type":"string","description":"The default test timeout. For example: 15s, 2x, none\\ndefaults to \\"30s\\""},"ignore-timeouts":{"type":"boolean","description":"Ignore all timeouts (useful if debugging)\\ndefaults to \\"false\\""},"pause-after-load":{"type":"boolean","description":"Pause for debugging before any tests execute.\\nImplies --concurrency=1, --debug, and --ignore-timeouts.\\nCurrently only supported for browser tests.\\ndefaults to \\"false\\""},"debug":{"type":"boolean","description":"Run the VM and Chrome tests in debug mode.\\ndefaults to \\"false\\""},"coverage":{"type":"string","description":"Gather coverage and output it to the specified directory.\\nImplies --debug."},"chain-stack-traces":{"type":"boolean","description":"Use chained stack traces to provide greater exception details\\nespecially for asynchronous code. It may be useful to disable\\nto provide improved test performance but at the cost of\\ndebuggability.\\ndefaults to \\"false\\""},"no-retry":{"type":"boolean","description":"Don't rerun tests that have retry set.\\ndefaults to \\"false\\""},"test-randomize-ordering-seed":{"type":"string","description":"Use the specified seed to randomize the execution order of test cases.\\nMust be a 32bit unsigned integer or \\"random\\".\\nIf \\"random\\", pick a random seed to use.\\nIf not passed, do not randomize test case execution order."},"fail-fast":{"type":"boolean","description":"Stop running tests after the first failure.\\n\\ndefaults to \\"false\\""},"reporter":{"type":"string","description":"Set how to print test results.\\ndefaults to \\"compact\\"\\nallowed values: compact, expanded, failures-only, github, json, silent"},"file-reporter":{"type":"string","description":"Enable an additional reporter writing test results to a file.\\nShould be in the form <reporter>:<filepath>, Example: \\"json:reports/tests.json\\""},"verbose-trace":{"type":"boolean","description":"Emit stack traces with core library frames.\\ndefaults to \\"false\\""},"js-trace":{"type":"boolean","description":"Emit raw JavaScript stack traces for browser tests.\\ndefaults to \\"false\\""},"color":{"type":"boolean","description":"Use terminal colors.\\n(auto-detected by default)\\ndefaults to \\"false\\""}},"required":[]}
''';
