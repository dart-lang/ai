// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:checks/checks.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('client can set the logging level', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithLogging.new,
    );
    final initializeResult = await environment.initializeServer();

    check(
      initializeResult.capabilities.logging as Map<String, Object?>?,
    ).isNotNull().deepEquals(Logging() as Map<String, Object?>);

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    check(
      server.loggingLevel,
      because: 'The default level is warning',
    ).equals(LoggingLevel.warning);

    await serverConnection.setLogLevel(
      SetLevelRequest(level: LoggingLevel.debug),
    );
    check(server.loggingLevel).equals(LoggingLevel.debug);

    await serverConnection.setLogLevel(
      SetLevelRequest(level: LoggingLevel.error),
    );
    check(server.loggingLevel).equals(LoggingLevel.error);
  });

  test('client can receive log messages', () async {
    final environment = TestEnvironment(
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
    final notifications = [
      for (var level in LoggingLevel.values)
        LoggingMessageNotification(
          data: '${level.name} message',
          level: level,
          logger: logger,
        ),
    ];

    final expectedNotifications = [
      for (var notification in notifications)
        if (notification.level >= LoggingLevel.warning) notification,
    ];

    final queue1 = StreamQueue(serverConnection.onLog);
    final queue2 = StreamQueue(serverConnection.onLog);

    final inOrderFuture = check(queue1).inOrder([
      for (var expected in expectedNotifications)
        .it()..emits(
          .it()
            ..has(
              (x) => x as Map<String, Object?>,
              'as Map',
            ).deepEquals(expected as Map<String, Object?>),
        ),
    ]);

    final neverEmitsFuture = check(queue2).neverEmits(
      .it()
        ..has(
          (x) => x.level,
          'level',
        ).has((l) => l < LoggingLevel.warning, 'is less than warning').isTrue(),
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

    await inOrderFuture;
    await queue1.cancel();

    unawaited(environment.shutdown());
    await neverEmitsFuture;
  });

  test('server can log functions for lazy evaluation', () async {
    final environment = TestEnvironment(
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

    final queue = StreamQueue(serverConnection.onLog);

    final inOrderFuture = check(queue).inOrder([
      for (var expected in notifications)
        .it()..emits(
          .it()
            ..has(
              (x) => x as Map<String, Object?>,
              'as Map',
            ).deepEquals(expected as Map<String, Object?>),
        ),
    ]);

    // A function with no arguments
    server.log(notifications[0].level, () => notifications[0].data);

    // A function with an optional positional argument
    server.log(notifications[1].level, ([int? x]) => notifications[1].data);

    // A function with an optional named argument
    server.log(notifications[2].level, ({int? x}) => notifications[2].data);

    check(
      () => server.log(LoggingLevel.warning, () => null),
      because: 'Lazy message functions should not have a nullable return type',
    ).throws<ArgumentError>();

    check(
      () => server.log(LoggingLevel.warning, (int x) => 'hello'),
      because:
          'Lazy message functions should not have required positional '
          'arguments',
    ).throws<ArgumentError>();

    check(
      () => server.log(LoggingLevel.warning, ({required int x}) => 'hello'),
      because:
          'Lazy message functions should not have required named arguments',
    ).throws<ArgumentError>();

    // Below logging level, never gets evaluated.
    server.log(LoggingLevel.info, () => throw StateError('Unreachable'));

    await inOrderFuture;
    await queue.cancel();
  });
}

final class TestMCPServerWithLogging extends TestMCPServer with LoggingSupport {
  TestMCPServerWithLogging(super.channel);
}
