// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

/// Builds a JSON schema representation for a list of [ParameterElement]s.
class SchemaBuilder {
  String build(List<ParameterElement> params, List<DartObject>? meta) {
    final props = <String>[];
    final required = <String>[];
    final paramMeta = {
      for (var m in meta ?? []) m.getField('name')?.toStringValue(): m,
    };

    for (var p in params) {
      final m = paramMeta[p.name];
      final title = m?.getField('title')?.toStringValue();
      final desc = m?.getField('description')?.toStringValue();
      props.add(
        "'${p.name}': ${_schemaFor(p.type.getDisplayString(withNullability: false), title, desc)}",
      );
      if (!p.isOptional) required.add("'${p.name}'");
    }

    return '''ObjectSchema(
      properties: {${props.join(', ')}},
      required: [${required.join(', ')}],
    )''';
  }

  String _schemaFor(String type, String? title, String? description) {
    final args = [
      if (title != null) "title: '$title'",
      if (description != null) "description: '$description'",
    ];
    final argStr = args.isEmpty ? '' : args.join(', ');
    switch (type) {
      case 'int':
        return 'IntegerSchema($argStr)';
      case 'double':
      case 'num':
        return 'NumberSchema($argStr)';
      case 'String':
        return 'StringSchema($argStr)';
      case 'bool':
        return 'BooleanSchema($argStr)';
      default:
        return 'ObjectSchema($argStr)';
    }
  }
}
