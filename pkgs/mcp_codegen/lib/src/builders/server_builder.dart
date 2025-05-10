// Copyright (c) 2023, the Dart project authors.
// See the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license in the LICENSE file.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

class ServerBuilder {
  String build({
    required Element serverElement,
    required DartObject annotation,
    required List<ExecutableElement> tools,
  }) {
    final isClass = serverElement is ClassElement;
    final name =
        annotation.getField('name')?.toStringValue() ?? serverElement.name;
    final version = annotation.getField('version')?.toStringValue() ?? '0.0.0';
    final instructions =
        annotation.getField('instructions')?.toStringValue() ?? '';

    final buffer =
        StringBuffer()
          ..writeln(
            'final class _GeneratedServer extends MCPServer with LoggingSupport, ToolsSupport, ResourcesSupport, RootsTrackingSupport {',
          )
          ..write(
            isClass
                ? '  final ${serverElement.name} _impl;\n  _GeneratedServer(super.channel, this._impl)'
                : '  _GeneratedServer(super.channel)',
          )
          ..writeln('      : super.fromStreamChannel(')
          ..writeln(
            "          implementation: ServerImplementation(name: '$name', version: '$version'),",
          )
          ..writeln("          instructions: '$instructions',")
          ..writeln('        );')
          ..writeln()
          ..writeln('  @override')
          ..writeln(
            '  FutureOr<InitializeResult> initialize(InitializeRequest request) {',
          );

    for (var f in tools) {
      buffer.writeln(
        isClass
            ? '    registerTool(_tool_${f.name}, (r) => _handler_${f.name}(_impl, r));'
            : '    registerTool(_tool_${f.name}, _handler_${f.name});',
      );
    }

    buffer
      ..writeln('    return super.initialize(request);')
      ..writeln('  }')
      ..writeln('}');

    buffer.writeln(_bootstrap(isClass, serverElement.name!));
    if (isClass) {
      buffer
        ..writeln()
        ..writeln(
          'extension _${serverElement.name}Runner on ${serverElement.name} {',
        )
        ..writeln(
          '  Future<void> run(List<String> args) => _runGeneratedMcpServer(args, this);',
        )
        ..writeln('}');
    }

    return buffer.toString();
  }

  String _bootstrap(bool includeImpl, String implType) {
    final paramSig = includeImpl ? ', $implType _impl' : '';
    final argCall = includeImpl ? ', _impl' : '';
    return '''
Future<void> _runGeneratedMcpServer(List<String> args$paramSig) async {
  _GeneratedServer? server;
  await runZonedGuarded(
    () async {
      final channel = StreamChannel.withCloseGuarantee(stdin, stdout)
        .transform(StreamChannelTransformer.fromCodec(utf8))
        .transformStream(const LineSplitter())
        .transformSink(StreamSinkTransformer.fromHandlers(handleData: (data, sink) => sink.add('\$data\\n')));
      ${includeImpl ? 'server = _GeneratedServer(channel$argCall);' : 'server = _GeneratedServer(channel);'}
    },
    (e, s) {
      if (server != null) {
        try { server!.log(LoggingLevel.error, '\$e\\n\$s'); } catch (_) {}
      } else {
        stderr..writeln(e)..writeln(s);
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, value) {
        if (server != null) {
          try { server!.log(LoggingLevel.info, value); } catch (_) {}
        }
      },
    ),
  );
}''';
  }
}
