// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main.dart';

// **************************************************************************
// MCPGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_import, unnecessary_cast

final Tool _tool_add = Tool(
  name: 'add',
  description: 'add two numbers',
  inputSchema: ObjectSchema(
    properties: {'a': NumberSchema(), 'b': NumberSchema()},
    required: ['a', 'b'],
  ),
  annotations: null,
);

FutureOr<CallToolResult> _handler_add(
    MCPDemoServer _impl, CallToolRequest _request) async {
  final _args = _request.arguments ?? const <String, Object?>{};
  final num a = _args['a'] as num;
  final num b = _args['b'] as num;
  final _result = await Future.sync(() => _impl.add(a, b));
  return CallToolResult(content: [TextContent(text: _result.toString())]);
}

final class _GeneratedServer extends MCPServer
    with LoggingSupport, ToolsSupport, ResourcesSupport, RootsTrackingSupport {
  final MCPDemoServer _impl;
  _GeneratedServer(super.channel, this._impl)
      : super.fromStreamChannel(
          implementation:
              ServerImplementation(name: 'demo_server', version: '0.1.0'),
          instructions: '',
        );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(_tool_add, (r) => _handler_add(_impl, r));
    return super.initialize(request);
  }
}

Future<void> _runGeneratedMcpServer(
    List<String> args, MCPDemoServer _impl) async {
  _GeneratedServer? server;
  await runZonedGuarded(
    () async {
      final channel = StreamChannel.withCloseGuarantee(stdin, stdout)
          .transform(StreamChannelTransformer.fromCodec(utf8))
          .transformStream(const LineSplitter())
          .transformSink(StreamSinkTransformer.fromHandlers(
              handleData: (data, sink) => sink.add('$data\n')));
      server = _GeneratedServer(channel, _impl);
    },
    (e, s) {
      if (server != null) {
        try {
          server!.log(LoggingLevel.error, '$e\n$s');
        } catch (_) {}
      } else {
        stderr
          ..writeln(e)
          ..writeln(s);
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, value) {
        if (server != null) {
          try {
            server!.log(LoggingLevel.info, value);
          } catch (_) {}
        }
      },
    ),
  );
}

extension _MCPDemoServerRunner on MCPDemoServer {
  Future<void> run(List<String> args) => _runGeneratedMcpServer(args, this);
}
