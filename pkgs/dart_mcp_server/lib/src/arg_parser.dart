// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

final argParser = ArgParser(allowTrailingOptions: false)
  ..addOption(
    dartSdkOption,
    help:
        'The path to the root of the desired Dart SDK. Defaults to the '
        'DART_SDK environment variable.',
  )
  ..addOption(
    flutterSdkOption,
    help:
        'The path to the root of the desired Flutter SDK. Defaults to '
        'the FLUTTER_SDK environment variable, then searching up from '
        'the Dart SDK.',
  )
  ..addFlag(
    forceRootsFallbackFlag,
    negatable: true,
    defaultsTo: false,
    help:
        'Forces a behavior for project roots which uses MCP tools '
        'instead of the native MCP roots. This can be helpful for '
        'clients like cursor which claim to have roots support but do '
        'not actually support it.',
  )
  ..addOption(
    logFileOption,
    help:
        'Path to a file to log all MPC protocol traffic to. File will be '
        'overwritten if it exists.',
  )
  ..addFlag(helpFlag, abbr: 'h', help: 'Show usage text');

const dartSdkOption = 'dart-sdk';
const flutterSdkOption = 'flutter-sdk';
const forceRootsFallbackFlag = 'force-roots-fallback';
const helpFlag = 'help';
const logFileOption = 'log-file';
