// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import 'schema_builder.dart';

/// Creates handler functions and their corresponding `Tool` declarations for
/// each tool method or top-level function.
class HandlerBuilder {
  String build(ExecutableElement func, DartObject ann, bool isClass) {
    final params = func.parameters
        .map(
          (p) =>
              "final ${p.type.getDisplayString(withNullability: false)} ${p.name} = _args['${p.name}'] as ${p.type.getDisplayString(withNullability: false)};",
        )
        .join('\n    ');

    final call =
        isClass
            ? '_impl.${func.name}(${func.parameters.map((p) => p.name).join(', ')})'
            : '${func.name}(${func.parameters.map((p) => p.name).join(', ')})';

    return '''final Tool _tool_${func.name} = Tool(
  name: '${ann.getField('name')?.toStringValue() ?? func.name}',
  description: ${ann.getField('description')?.toStringValue() != null ? "'${ann.getField('description')!.toStringValue()}'" : 'null'},
  inputSchema: ${SchemaBuilder().build(func.parameters, ann.getField('parameters')?.toListValue())},
  annotations: ${_buildAnnotations(ann)},
);

FutureOr<CallToolResult> _handler_${func.name}(${isClass ? '${func.enclosingElement.name} _impl, ' : ''}CallToolRequest _request) async {
    final _args = _request.arguments ?? const <String, Object?>{};
    $params
    final _result = await Future.sync(() => $call);
    return CallToolResult(content: [TextContent(text: _result.toString())]);
}''';
  }

  String _buildAnnotations(DartObject ann) {
    final flags = [
      'destructiveHint',
      'idempotentHint',
      'openWorldHint',
      'readOnlyHint',
      'title',
    ];

    final entries = <String>[];
    for (var flag in flags) {
      final v = ann.getField(flag);
      if (v != null && !v.isNull) {
        final val = v.toBoolValue() ?? v.toStringValue();
        entries.add('$flag: $val');
      }
    }
    return entries.isEmpty ? 'null' : 'ToolAnnotations(${entries.join(', ')})';
  }
}
