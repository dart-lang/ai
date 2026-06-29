// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension IconChecks on Subject<Icon> {
  Subject<String> get src => has((x) => x.src, 'src');
  Subject<String?> get mimeType => has((x) => x.mimeType, 'mimeType');
  Subject<List<String>?> get sizes => has((x) => x.sizes, 'sizes');
  Subject<IconTheme?> get theme => has((x) => x.theme, 'theme');
}
