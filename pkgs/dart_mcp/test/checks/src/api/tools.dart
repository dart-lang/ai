// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension ListToolsRequestChecks on Subject<ListToolsRequest> {}

extension ListToolsResultChecks on Subject<ListToolsResult> {
  Subject<List<Tool>> get tools => has((x) => x.tools, 'tools');
}

extension CallToolRequestChecks on Subject<CallToolRequest> {
  Subject<String> get name => has((x) => x.name, 'name');
  Subject<Map<String, Object?>?> get arguments =>
      has((x) => x.arguments, 'arguments');
}

extension CallToolResultChecks on Subject<CallToolResult> {
  Subject<List<Content>> get content => has((x) => x.content, 'content');
  Subject<Map<String, Object?>?> get structuredContent =>
      has((x) => x.structuredContent, 'structuredContent');
  Subject<bool?> get isError => has((x) => x.isError, 'isError');
}

extension ToolChecks on Subject<Tool> {
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<ObjectSchema> get inputSchema =>
      has((x) => x.inputSchema, 'inputSchema');
  Subject<ObjectSchema?> get outputSchema =>
      has((x) => x.outputSchema, 'outputSchema');
  Subject<List<Icon>?> get icons => has((x) => x.icons, 'icons');
}

extension ValidationErrorChecks on Subject<ValidationError> {
  Subject<ValidationErrorType> get error => has((x) => x.error, 'error');
  Subject<List<String>> get path => has((x) => x.path, 'path');
  Subject<String?> get details => has((x) => x.details, 'details');
}
