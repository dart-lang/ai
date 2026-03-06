// Copyright (c) 2026 the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'parser.dart';

String renderMustachio(String template, Map<String, Object?> arguments) {
  final ast = MustachioParser(template, 'string').parse();
  final sink = StringBuffer();
  _renderBlock(ast, arguments, sink);
  return sink.toString();
}

void _renderBlock(
  List<MustachioNode> ast,
  Map<String, Object?> arguments,
  StringSink sink,
) {
  for (final node in ast) {
    switch (node) {
      case Text():
        sink.write(node.content);
      case Variable():
        final value = _readValue(arguments, node.key);
        if (value != null) {
          sink.write(value.toString());
        }
      case Section():
        final value = _readValue(arguments, node.key);
        final isTruthy = value != null && value != false;
        if (isTruthy == node.invert) {
          continue;
        }
        if (value is Iterable) {
          throw UnsupportedError(
            'Looping is not supported in this implementation of mustache',
          );
        }
        _renderBlock(node.children, arguments, sink);
      case Partial():
        throw UnsupportedError(
          'Partials are not supported in this implementation of mustache',
        );
    }
  }
}

Object? _readValue(Map<String, Object?> arguments, List<String> keys) {
  Object? value = arguments;
  for (var key in keys) {
    if (value is Map<String, Object?>) {
      value = value[key];
    } else {
      value = null;
      break;
    }
  }
  return value;
}
