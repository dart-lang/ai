// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/server.dart';

/// A namespace for all the parameter names.
extension ParameterNames on Never {
  static const column = 'column';
  static const command = 'command';
  static const directory = 'directory';
  static const empty = 'empty';
  static const line = 'line';
  static const name = 'name';
  static const packageName = 'packageName';
  static const paths = 'paths';
  static const platform = 'platform';
  static const position = 'position';
  static const projectType = 'projectType';
  static const query = 'query';
  static const root = 'root';
  static const roots = 'roots';
  static const template = 'template';
  static const testRunnerArgs = 'testRunnerArgs';
  static const uri = 'uri';
  static const uris = 'uris';
}

/// A shared success response for tools.
final success = CallToolResult(content: [Content.text(text: 'Success')]);
