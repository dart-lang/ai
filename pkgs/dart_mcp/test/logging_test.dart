// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client can set the logging level', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithLogging.new,
    );
    final initializeResult = await environment.initializeServer();

    expect(initializeResult.capabilities.logging, Logging());

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    expect(
      server.loggingLevel,
      LoggingLevel.warning,
      reason: 'The default level is warning',
    );

    await serverConnection.setLogLevel(
      SetLevelRequest(level: LoggingLevel.debug),
    );
    expect(server.loggingLevel, LoggingLevel.debug);

    await serverConnection.setLogLevel(
      SetLevelRequest(level: LoggingLevel.error),
    );
    expect(server.loggingLevel, LoggingLevel.error);
  });

  test('client can receive log messages', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithLogging.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    await serverConnection.setLogLevel(
      SetLevelRequest(level: LoggingLevel.warning),
    );

    final logger = 'myLogger';
    var notifications = [
      for (var level in LoggingLevel.values)
        LoggingMessageNotification(
          data: '${level.name} message',
          level: level,
          logger: logger,
        ),
    ];

    expect(
      serverConnection.onLog,
      emitsInOrder([
        for (var notification in notifications)
          if (notification.level >= LoggingLevel.warning) notification,
      ]),
    );

    expect(
      serverConnection.onLog,
      neverEmits([
        for (var notification in notifications)
          if (notification.level < LoggingLevel.warning) notification,
      ]),
    );

    for (var notification in notifications) {
      server.log(
        notification.level,
        notification.data,
        logger: notification.logger,
      );
    }

    /// Allow the notifications to propagate.
    await pumpEventQueue();

    /// Closes the log stream so that `neverEmits` can complete above.
    await environment.shutdown();
  });

  test('server can log functions for lazy evaluation', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithLogging.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    await serverConnection.setLogLevel(
      SetLevelRequest(level: LoggingLevel.warning),
    );

    final notifications = [
      for (var i = 0; i < 3; i++)
        LoggingMessageNotification(level: LoggingLevel.warning, data: i),
    ];

    expect(serverConnection.onLog, emitsInOrder(notifications));

    // A function with no arguments
    server.log(notifications[0].level, () => notifications[0].data);

    // A function with an optional positional argument
    server.log(notifications[1].level, ([int? x]) => notifications[1].data);

    // A function with an optional named argument
    server.log(notifications[2].level, ({int? x}) => notifications[2].data);

    expect(
      () => server.log(LoggingLevel.warning, () => null),
      throwsA(isA<ArgumentError>()),
      reason: 'Lazy message functions should not have a nullable return type',
    );

    expect(
      () => server.log(LoggingLevel.warning, (int x) => 'hello'),
      throwsA(isA<ArgumentError>()),
      reason:
          'Lazy message functions should not have required positional '
          'arguments',
    );

    expect(
      () => server.log(LoggingLevel.warning, ({required int x}) => 'hello'),
      throwsA(isA<ArgumentError>()),
      reason: 'Lazy message functions should not have required named arguments',
    );

    // Below logging level, never gets evaluated.
    server.log(LoggingLevel.info, () => throw StateError('Unreachable'));
  });
}

final class TestMCPServerWithLogging extends TestMCPServer with LoggingSupport {
  TestMCPServerWithLogging(super.channel) : super();
}
