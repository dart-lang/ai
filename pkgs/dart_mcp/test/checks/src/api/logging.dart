// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension SetLevelRequestChecks on Subject<SetLevelRequest> {
  Subject<LoggingLevel> get level => has((x) => x.level, 'level');
}

extension LoggingMessageNotificationChecks
    on Subject<LoggingMessageNotification> {
  Subject<LoggingLevel> get level => has((x) => x.level, 'level');
  Subject<String?> get logger => has((x) => x.logger, 'logger');
  Subject<Object> get data => has((x) => x.data, 'data');
}
