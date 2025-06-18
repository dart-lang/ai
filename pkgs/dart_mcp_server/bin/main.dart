// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/dart_mcp_server.dart';
import 'package:stream_channel/stream_channel.dart';

void main(List<String> args) async {
  final parsedArgs = argParser.parse(args);
  if (parsedArgs.flag(help)) {
    print(argParser.usage);
    io.exit(0);
  }

  DartMCPServer? server;
  final dartSdkPath =
      parsedArgs.option(dartSdkOption) ?? io.Platform.environment['DART_SDK'];
  final flutterSdkPath =
      parsedArgs.option(flutterSdkOption) ??
      io.Platform.environment['FLUTTER_SDK'];
  final logFilePath = parsedArgs.option(logFileOption);
  final logFileSink =
      logFilePath == null ? null : createLogSink(io.File(logFilePath));
  runZonedGuarded(
    () {
      server = DartMCPServer(
        StreamChannel.withCloseGuarantee(io.stdin, io.stdout)
            .transform(StreamChannelTransformer.fromCodec(utf8))
            .transformStream(const LineSplitter())
            .transformSink(
              StreamSinkTransformer.fromHandlers(
                handleData: (data, sink) {
                  sink.add('$data\n');
                },
              ),
            ),
        forceRootsFallback: parsedArgs.flag(forceRootsFallback),
        sdk: Sdk.find(dartSdkPath: dartSdkPath, flutterSdkPath: flutterSdkPath),
        protocolLogSink: logFileSink,
      )..done.whenComplete(() => logFileSink?.close());
    },
    (e, s) {
      if (server != null) {
        try {
          // Log unhandled errors to the client, if we managed to connect.
          server!.log(LoggingLevel.error, '$e\n$s');
        } catch (_) {}
      } else {
        // Otherwise log to stderr.
        io.stderr
          ..writeln(e)
          ..writeln(s);
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, value) {
        if (server != null) {
          try {
            // Don't allow `print` since this breaks stdio communication, but if
            // we have a server we do log messages to the client.
            server!.log(LoggingLevel.info, value);
          } catch (_) {}
        }
      },
    ),
  );
}

final argParser =
    ArgParser(allowTrailingOptions: false)
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
            'the FLUTTER_SDK environment variable, then searching up from the '
            'Dart SDK.',
      )
      ..addFlag(
        forceRootsFallback,
        negatable: true,
        defaultsTo: false,
        help:
            'Forces a behavior for project roots which uses MCP tools instead '
            'of the native MCP roots. This can be helpful for clients like '
            'cursor which claim to have roots support but do not actually '
            'support it.',
      )
      ..addOption(
        logFileOption,
        help:
            'Path to a file to log all MPC protocol traffic to. File will be '
            'overwritten if it exists.',
      )
      ..addFlag(help, abbr: 'h', help: 'Show usage text');

const dartSdkOption = 'dart-sdk';
const flutterSdkOption = 'flutter-sdk';
const forceRootsFallback = 'force-roots-fallback';
const help = 'help';
const logFileOption = 'log-file';

/// Creates a `Sink<String>` for [logFile].
Sink<String> createLogSink(io.File logFile) {
  logFile.createSync(recursive: true);
  final fileByteSink = logFile.openWrite(
    mode: io.FileMode.write,
    encoding: utf8,
  );
  return fileByteSink.transform(
    StreamSinkTransformer.fromHandlers(
      handleData: (data, innerSink) {
        innerSink.add(utf8.encode(data));
        // It's a log, so we want to make sure it's always up-to-date.
        fileByteSink.flush();
      },
      handleDone: (innerSink) {
        innerSink.close();
      },
    ),
  );
}
