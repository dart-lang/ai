// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension ListRootsRequestChecks on Subject<ListRootsRequest> {}

extension ListRootsResultChecks on Subject<ListRootsResult> {
  Subject<List<Root>> get roots => has((x) => x.roots, 'roots');
}

extension RootChecks on Subject<Root> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
  Subject<String?> get name => has((x) => x.name, 'name');
}

extension RootsListChangedNotificationChecks
    on Subject<RootsListChangedNotification> {}
