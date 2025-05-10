// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../builders/handler_builder.dart';
import '../builders/server_builder.dart';

/// Responsible for orchestrating code emission for tools and the server
/// wrapper.
class CodeEmitter {
  final HandlerBuilder _handlerBuilder = HandlerBuilder();
  final ServerBuilder _serverBuilder = ServerBuilder();

  String emit({
    required Element serverElement,
    required DartObject annotation,
    required Map<ExecutableElement, DartObject> tools,
  }) {
    final buffer =
        StringBuffer()
          ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
          ..writeln('// ignore_for_file: unused_import, unnecessary_cast')
          ..writeln();

    // Emit tool constant declarations and their handlers.
    tools.forEach((func, ann) {
      buffer.writeln(
        _handlerBuilder.build(func, ann, serverElement is ClassElement),
      );
      buffer.writeln();
    });

    // Emit the server scaffold and bootstrap code.
    buffer.writeln(
      _serverBuilder.build(
        serverElement: serverElement,
        annotation: annotation,
        tools: tools.keys.toList(),
      ),
    );

    return buffer.toString();
  }
}
