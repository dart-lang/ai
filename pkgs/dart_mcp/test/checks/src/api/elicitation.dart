// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension ElicitRequestChecks on Subject<ElicitRequest> {
  Subject<ElicitationMode> get mode => has((x) => x.mode, 'mode');
  Subject<String> get message => has((x) => x.message, 'message');
  Subject<String?> get elicitationId =>
      has((x) => x.elicitationId, 'elicitationId');
  Subject<String?> get url => has((x) => x.url, 'url');
  Subject<ObjectSchema?> get requestedSchema =>
      has((x) => x.requestedSchema, 'requestedSchema');
}

extension ElicitResultChecks on Subject<ElicitResult> {
  Subject<ElicitationAction> get action => has((x) => x.action, 'action');
  Subject<Map<String, Object?>?> get content =>
      has((x) => x.content, 'content');
}

extension ElicitationCompleteNotificationChecks
    on Subject<ElicitationCompleteNotification> {
  Subject<String> get elicitationId =>
      has((x) => x.elicitationId, 'elicitationId');
}
