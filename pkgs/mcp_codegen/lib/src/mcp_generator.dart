import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:build/build.dart';
import 'package:mcp_annotations/mcp_annotations.dart';
import 'package:source_gen/source_gen.dart';

class MCPGenerator extends Generator {
  static final _mcpToolChecker = TypeChecker.fromRuntime(MCPTool);
  static final _mcpServerChecker = TypeChecker.fromRuntime(MCPServerApp);

  /// HELPER: iterate top level functions in a [LibraryElement].
  Iterable<FunctionElement> _topLevelFunctions(LibraryElement lib) sync* {
    for (final unit in lib.units) {
      for (final func in unit.functions) {
        yield func;
      }
    }
  }

  /// HELPER: iterate all classes in a [LibraryElement].
  Iterable<ClassElement> _classes(LibraryElement lib) sync* {
    for (final unit in lib.units) {
      for (final clazz in unit.classes) {
        yield clazz;
      }
    }
  }

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    final serverAnnotatedElements = <Element, DartObject>{};

    for (final annotated in _topLevelFunctions(library.element)) {
      final annotation = _mcpServerChecker.firstAnnotationOfExact(annotated);
      if (annotation != null) {
        serverAnnotatedElements[annotated] = annotation;
      }
    }

    for (final clazz in _classes(library.element)) {
      final annotation = _mcpServerChecker.firstAnnotationOfExact(clazz);
      if (annotation != null) {
        serverAnnotatedElements[clazz] = annotation;
      }
    }

    if (serverAnnotatedElements.isEmpty) return null;

    // Currently support exactly one per library for simplicity.
    if (serverAnnotatedElements.length > 1) {
      log.warning(
        'Multiple @MCPServerApp annotations found in ${library.element.source.uri}. '
        'Only the first one will be used.',
      );
    }

    final serverElement = serverAnnotatedElements.keys.first;
    final serverAnnotation = serverAnnotatedElements.values.first;

    final serverName =
        serverAnnotation.getField('name')?.toStringValue() ??
        serverElement.name;
    final serverVersion =
        serverAnnotation.getField('version')?.toStringValue() ?? '0.0.0';
    final serverInstructions =
        serverAnnotation.getField('instructions')?.toStringValue();

    // Collect tool functions within the server context.
    final toolFunctions = <ExecutableElement, DartObject>{};

    if (serverElement is ClassElement) {
      for (final method in serverElement.methods) {
        final ann = _mcpToolChecker.firstAnnotationOfExact(method);
        if (ann != null) {
          toolFunctions[method] = ann;
        }
      }
    } else if (serverElement is FunctionElement) {
      for (final function in _topLevelFunctions(library.element)) {
        final ann = _mcpToolChecker.firstAnnotationOfExact(function);
        if (ann != null) {
          toolFunctions[function] = ann;
        }
      }
    }

    if (toolFunctions.isEmpty) {
      log.warning(
        'No @MCPTool annotated functions found in '
        '${library.element.source.uri}. The generated server will have no tools.',
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln(
      '// ignore_for_file: unused_element, unused_import, unnecessary_cast',
    );
    buffer.writeln();
    // No additional imports inside part files (must contain only code).
    buffer.writeln();

    // Generate per-tool constants & handlers.
    for (final entry in toolFunctions.entries) {
      final func = entry.key;
      final ann = entry.value;

      final toolName = ann.getField('name')?.toStringValue() ?? func.name;
      final description = ann.getField('description')?.toStringValue();

      // Map of parameter name -> (title, description) from annotation metadata.
      final _paramMeta = <String, Map<String, String?>>{};
      final metaList = ann.getField('parameters')?.toListValue();
      if (metaList != null) {
        for (final meta in metaList) {
          final name = meta.getField('name')?.toStringValue();
          if (name == null) continue;
          _paramMeta[name] = {
            'title': meta.getField('title')?.toStringValue(),
            'description': meta.getField('description')?.toStringValue(),
          };
        }
      }

      final propsBuffer = StringBuffer();
      final requiredParams = <String>[];
      for (final param in func.parameters) {
        final meta = _paramMeta[param.name];
        final schema = _schemaForParam(
          param,
          title: meta?['title'],
          description: meta?['description'],
        );
        propsBuffer.writeln("      '${param.name}': $schema,");
        if (!param.isOptional) {
          requiredParams.add("'${param.name}'");
        }
      }

      final inputSchemaCode = '''ObjectSchema(
        properties: {
${propsBuffer.toString()}        },
        required: [${requiredParams.join(', ')}],
      )''';

      // Build ToolAnnotations hints.
      final hintFields = <String>[];
      void addHint(String field) {
        final value = ann.getField(field);
        if (value == null || value.isNull) return;
        hintFields.add(
          '$field: ${value.toBoolValue() ?? value.toStringValue()}',
        );
      }

      addHint('destructiveHint');
      addHint('idempotentHint');
      addHint('openWorldHint');
      addHint('readOnlyHint');
      addHint('title');

      var annotationsCode = 'null';
      if (hintFields.isNotEmpty) {
        annotationsCode = 'ToolAnnotations(${hintFields.join(', ')})';
      }

      buffer
        ..writeln('final Tool _tool_${func.name} = Tool(')
        ..writeln("  name: '$toolName',")
        ..writeln(
          "  description: ${description != null ? '\'${_escape(description)}\'' : 'null'},",
        )
        ..writeln('  inputSchema: $inputSchemaCode,')
        ..writeln('  annotations: $annotationsCode,')
        ..writeln(');')
        ..writeln();

      // Generate handler definition.
      if (serverElement is ClassElement) {
        final className = serverElement.name;
        buffer.writeln('FutureOr<CallToolResult> _handler_${func.name}(');
        buffer.writeln('  $className _impl, CallToolRequest _request) async {');
      } else {
        buffer.writeln(
          'FutureOr<CallToolResult> _handler_${func.name}(CallToolRequest _request) async {',
        );
      }

      buffer.writeln(
        '  final _args = _request.arguments ?? const <String, Object?>{};',
      );

      final callArgsList = <String>[];
      for (final param in func.parameters) {
        final pName = param.name;
        final pTypeCode = param.type.getDisplayString(withNullability: false);
        buffer.writeln(
          '  final $pTypeCode $pName = _args[\'$pName\'] as $pTypeCode;',
        );
        callArgsList.add(pName);
      }

      final callExpr =
          serverElement is ClassElement
              ? '_impl.${func.name}(${callArgsList.join(', ')})'
              : '${func.name}(${callArgsList.join(', ')})';

      buffer.writeln('  final _result = await Future.sync(() => $callExpr);');
      buffer.writeln(
        '  return CallToolResult(content: [TextContent(text: _result.toString())]);',
      );
      buffer.writeln('}');
      buffer.writeln();
    }

    // Generate server subclass.
    buffer.writeln(
      'final class _GeneratedServer extends MCPServer'
      ' with LoggingSupport, ToolsSupport, ResourcesSupport, RootsTrackingSupport {',
    );

    if (serverElement is ClassElement) {
      final className = serverElement.name;
      buffer.writeln('  final $className _impl;');
      buffer.writeln('  _GeneratedServer(super.channel, this._impl)');
    } else {
      buffer.writeln('  _GeneratedServer(super.channel)');
    }

    buffer.writeln('      : super.fromStreamChannel(');
    buffer.writeln(
      "          implementation: ServerImplementation(name: '$serverName', version: '$serverVersion'),",
    );
    buffer.writeln(
      "          instructions: ${serverInstructions != null ? '\'${_escape(serverInstructions)}\'' : '\'\''},",
    );
    buffer.writeln('        );');
    buffer.writeln();

    // initialize override registers tools then defers to super.
    buffer.writeln('  @override');
    buffer.writeln(
      '  FutureOr<InitializeResult> initialize(InitializeRequest request) {',
    );

    if (serverElement is ClassElement) {
      for (final func in toolFunctions.keys) {
        buffer.writeln(
          '    registerTool(_tool_${func.name}, (r) => _handler_${func.name}(_impl, r));',
        );
      }
    } else {
      for (final func in toolFunctions.keys) {
        buffer.writeln(
          '    registerTool(_tool_${func.name}, _handler_${func.name});',
        );
      }
    }

    buffer.writeln('    return super.initialize(request);');
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();

    // Bootstrap helper that sets up the stdio channel and runs the server in a
    // guarded zone which forwards uncaught errors and `print` calls to the
    // client via the logging API when possible.

    if (serverElement is ClassElement) {
      final className = serverElement.name;
      buffer.writeln(
        'Future<void> _runGeneratedMcpServer(List<String> args, $className _impl) async {',
      );
    } else {
      buffer.writeln(
        'Future<void> _runGeneratedMcpServer(List<String> args) async {',
      );
    }

    buffer.writeln('  _GeneratedServer? server;');
    buffer.writeln('  await runZonedGuarded(');
    buffer.writeln('    () async {');
    buffer.writeln(
      '      final channel = StreamChannel.withCloseGuarantee(stdin, stdout)',
    );
    buffer.writeln(
      '          .transform(StreamChannelTransformer.fromCodec(utf8))',
    );
    buffer.writeln('          .transformStream(const LineSplitter())');
    buffer.writeln('          .transformSink(');
    buffer.writeln('        StreamSinkTransformer.fromHandlers(');
    buffer.writeln('          handleData: (data, sink) {');
    buffer.writeln('            sink.add(\'\$data\\n\');');
    buffer.writeln('          },');
    buffer.writeln('        ),');
    buffer.writeln('      );');
    buffer.writeln();

    if (serverElement is ClassElement) {
      buffer.writeln('      server = _GeneratedServer(channel, _impl);');
    } else {
      buffer.writeln('      server = _GeneratedServer(channel);');
    }

    buffer.writeln('    },');
    buffer.writeln('    (e, s) {');
    buffer.writeln('      if (server != null) {');
    buffer.writeln('        try {');
    buffer.writeln('          server!.log(LoggingLevel.error, \'\$e\\n\$s\');');
    buffer.writeln('        } catch (_) {}');
    buffer.writeln('      } else {');
    buffer.writeln('        stderr');
    buffer.writeln('          ..writeln(e)');
    buffer.writeln('          ..writeln(s);');
    buffer.writeln('      }');
    buffer.writeln('    },');
    buffer.writeln('    zoneSpecification: ZoneSpecification(');
    buffer.writeln('      print: (_, __, ___, value) {');
    buffer.writeln('        if (server != null) {');
    buffer.writeln('          try {');
    buffer.writeln('            server!.log(LoggingLevel.info, value);');
    buffer.writeln('          } catch (_) {}');
    buffer.writeln('        }');
    buffer.writeln('      },');
    buffer.writeln('    ),');
    buffer.writeln('  );');
    buffer.writeln('}');

    // If using class-based server, generate a convenience extension for `run`.
    if (serverElement is ClassElement) {
      final className = serverElement.name;
      buffer.writeln();
      buffer.writeln('extension _${className}Runner on $className {');
      buffer.writeln(
        '  Future<void> run(List<String> args) => _runGeneratedMcpServer(args, this);',
      );
      buffer.writeln('}');
    }

    return buffer.toString();
  }

  String _escape(String input) => input.replaceAll("'", "\\'");

  String _schemaForParam(
    ParameterElement param, {
    String? title,
    String? description,
  }) {
    final type = param.type.getDisplayString(withNullability: false);

    String _args() {
      final parts = <String>[];
      if (title != null) parts.add("title: '${_escape(title)}'");
      if (description != null) {
        parts.add("description: '${_escape(description)}'");
      }
      return parts.isEmpty ? '' : parts.join(', ');
    }

    final argStr = _args();

    switch (type) {
      case 'int':
        return argStr.isEmpty ? 'IntegerSchema()' : 'IntegerSchema($argStr)';
      case 'double':
      case 'num':
        return argStr.isEmpty ? 'NumberSchema()' : 'NumberSchema($argStr)';
      case 'String':
        return argStr.isEmpty ? 'StringSchema()' : 'StringSchema($argStr)';
      case 'bool':
        return argStr.isEmpty ? 'BooleanSchema()' : 'BooleanSchema($argStr)';
      default:
        return argStr.isEmpty ? 'ObjectSchema()' : 'ObjectSchema($argStr)';
    }
  }
}
