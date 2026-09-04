// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/streamable_http.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

/// Runs the server fixture used by the MCP conformance suite.
///
/// This prints an endpoint to stdout. Run the suite against that endpoint with
///
/// ```sh
/// npx @modelcontextprotocol/conformance@0.2.0-alpha.11 \
///   server --url ENDPOINT --requirements 2026-07-28
/// ```
Future<void> main(List<String> arguments) async {
  final port = arguments.isEmpty ? 0 : int.parse(arguments.single);
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final endpoint = Uri(
    scheme: 'http',
    host: httpServer.address.host,
    port: httpServer.port,
    path: _path,
  );

  stdout.writeln(endpoint);
  httpServer.listen((request) => unawaited(_handleRequest(request)));
}

/// Carries the changes one request's server makes to the listen streams open
/// on other requests.
///
/// A request-scoped server lives for one message. A `tools/call` that
/// mutates a list and a `subscriptions/listen` holding a stream open are two
/// different servers. Every notification goes in here, and each listen request
/// reads back the ones its acknowledged filter selects.
final _subscriptionNotifications =
    StreamController<Map<String, Object?>>.broadcast();

const _path = '/mcp';
const _imageMimeType = 'image/png';
const _audioMimeType = 'audio/wav';
const _textMimeType = 'text/plain';
const _jsonMimeType = 'application/json';
// 1x1 PNG and a silent WAV. tools-call-image and tools-call-audio only
// require a valid payload of the declared mime type.
const _imageData =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==';
const _audioData =
    'UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAAB9AAACABAAZGF0YQIAAAA=';

const _simpleTextTool = 'test_simple_text';
const _imageTool = 'test_image_content';
const _audioTool = 'test_audio_content';
const _embeddedResourceTool = 'test_embedded_resource';
const _mixedContentTool = 'test_multiple_content_types';
const _errorTool = 'test_error_handling';
const _progressTool = 'test_tool_with_progress';
const _missingCapabilityTool = 'test_missing_capability';
const _headerTool = 'test_x_mcp_header';
const _jsonSchemaTool = 'json_schema_2020_12_tool';
const _toolChangeTool = 'test_trigger_tool_change';
const _promptChangeTool = 'test_trigger_prompt_change';
const _addedTool = 'test_added_tool';
const _addedPrompt = 'test_added_prompt';
const _inputElicitationTool = 'test_input_required_result_elicitation';
const _inputSamplingTool = 'test_input_required_result_sampling';
const _inputRootsTool = 'test_input_required_result_list_roots';
const _inputStateTool = 'test_input_required_result_request_state';
const _inputMultipleTool = 'test_input_required_result_multiple_inputs';
const _inputMultiRoundTool = 'test_input_required_result_multi_round';
const _inputTamperedTool = 'test_input_required_result_tampered_state';
const _inputCapabilitiesTool = 'test_input_required_result_capabilities';

const _staticTextUri = 'test://static-text';
const _staticBinaryUri = 'test://static-binary';
const _templateUri = 'test://template/{id}/data';

const _simplePrompt = 'test_simple_prompt';
const _argumentsPrompt = 'test_prompt_with_arguments';
const _embeddedResourcePrompt = 'test_prompt_with_embedded_resource';
const _imagePrompt = 'test_prompt_with_image';
const _inputPrompt = 'test_input_required_result_prompt';

// HMAC-SHA256 over an opaque requestState so
// input-required-result-tampered-state can detect a modified payload.
final _stateRandom = Random.secure();
final _stateKey = List<int>.unmodifiable(
  List<int>.generate(32, (_) => _stateRandom.nextInt(256)),
);
final _stateHmac = Hmac(sha256, _stateKey);

// http-header-validation. Only `region` is annotated with `x-mcp-header`.
final _headerToolSchema = ObjectSchema.fromMap({
  'type': 'object',
  'properties': {
    'region': {
      'type': 'string',
      'description': 'mirrored into Mcp-Param-Region',
      'x-mcp-header': 'Region',
    },
    'level': {'type': 'integer', 'description': 'non-mirrored argument'},
  },
});

// json-schema-2020-12 round-trips `$schema`, `$defs`, `$ref`, `$anchor`,
// `allOf`/`anyOf`, and `if`/`then`/`else`. The package validator does not
// implement that draft, so the tool registers with validateArguments: false.
final _jsonSchema = ObjectSchema.fromMap({
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  r'$defs': {
    'address': {
      r'$anchor': 'addressDef',
      'type': 'object',
      'properties': {
        'street': {'type': 'string'},
        'city': {'type': 'string'},
      },
    },
  },
  'properties': {
    'name': {'type': 'string'},
    'address': {r'$ref': r'#/$defs/address'},
    'contactMethod': {
      'type': 'string',
      'enum': ['phone', 'email'],
    },
    'phone': {'type': 'string'},
    'email': {'type': 'string'},
  },
  'allOf': [
    {
      'anyOf': [
        {
          'required': ['phone'],
        },
        {
          'required': ['email'],
        },
      ],
    },
  ],
  'if': {
    'properties': {
      'contactMethod': {'const': 'phone'},
    },
    'required': ['contactMethod'],
  },
  'then': {
    'required': ['phone'],
  },
  'else': {
    'required': ['email'],
  },
  'additionalProperties': false,
});

Future<void> _handleRequest(HttpRequest request) async {
  try {
    if (request.uri.path != _path) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..contentLength = 0;
      await request.response.close();
      return;
    }

    if (!_hasLocalTarget(request)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..contentLength = 0;
      await request.response.close();
      return;
    }

    await handleStreamableHttpRequest(
      request,
      _ConformanceServer.new,
      onNotification: _subscriptionNotifications.add,
      subscriptionNotifications: _subscriptionNotifications.stream,
    );
  } catch (error) {
    stderr.writeln(error);
  }
}

// dns-rebinding-protection. Host must be loopback. Origin, if sent, must be
// too.
bool _hasLocalTarget(HttpRequest request) {
  final hosts = request.headers[HttpHeaders.hostHeader];
  if (hosts == null ||
      hosts.length != 1 ||
      !_isLocalUri(Uri.tryParse('http://${hosts.single}'))) {
    return false;
  }

  final origins = request.headers['origin'];
  return origins == null ||
      (origins.length == 1 && _isLocalUri(Uri.tryParse(origins.single)));
}

bool _isLocalUri(Uri? uri) =>
    uri != null &&
    (uri.host.toLowerCase() == 'localhost' ||
        uri.host == InternetAddress.loopbackIPv4.address ||
        uri.host == InternetAddress.loopbackIPv6.address);

base class _ConformanceServer extends MCPServer
    with
        ToolsSupport,
        ResourcesSupport,
        PromptsSupport,
        CompletionsSupport,
        SubscriptionsSupport {
  _ConformanceServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'dart_mcp conformance server',
          version: '0.1.0',
        ),
      ) {
    _registerTools();
    _registerResources();
    _registerPrompts();
  }

  // Tools named by the tools-call-* and input-required-result-* scenarios.
  void _registerTools() {
    registerTool(
      Tool(
        name: _simpleTextTool,
        description: _simpleTextTool,
        inputSchema: ObjectSchema(),
      ),
      (_) => CallToolResult(
        content: [
          TextContent(text: 'This is a simple text response for testing.'),
        ],
      ),
    );
    registerTool(
      Tool(
        name: _headerTool,
        description: _headerTool,
        inputSchema: _headerToolSchema,
      ),
      (request) => CallToolResult(
        content: [
          TextContent(
            text: 'region=${request.arguments?['region'] ?? '<none>'}',
          ),
        ],
      ),
    );
    registerTool(
      Tool(
        name: _imageTool,
        description: _imageTool,
        inputSchema: ObjectSchema(),
      ),
      (_) => CallToolResult(
        content: [ImageContent(data: _imageData, mimeType: _imageMimeType)],
      ),
    );
    registerTool(
      Tool(
        name: _audioTool,
        description: _audioTool,
        inputSchema: ObjectSchema(),
      ),
      (_) => CallToolResult(
        content: [AudioContent(data: _audioData, mimeType: _audioMimeType)],
      ),
    );
    registerTool(
      Tool(
        name: _embeddedResourceTool,
        description: _embeddedResourceTool,
        inputSchema: ObjectSchema(),
      ),
      (_) => CallToolResult(
        content: [
          EmbeddedResource(
            resource: TextResourceContents(
              uri: 'test://embedded-resource',
              mimeType: _textMimeType,
              text: 'This is an embedded resource content.',
            ),
          ),
        ],
      ),
    );
    registerTool(
      Tool(
        name: _mixedContentTool,
        description: _mixedContentTool,
        inputSchema: ObjectSchema(),
      ),
      (_) => CallToolResult(
        content: [
          TextContent(text: 'Multiple content types test:'),
          ImageContent(data: _imageData, mimeType: _imageMimeType),
          EmbeddedResource(
            resource: TextResourceContents(
              uri: 'test://mixed-content-resource',
              mimeType: _jsonMimeType,
              text: jsonEncode({'test': 'data', 'value': 123}),
            ),
          ),
        ],
      ),
    );
    registerTool(
      Tool(
        name: _errorTool,
        description: _errorTool,
        inputSchema: ObjectSchema(),
      ),
      (_) =>
          throw StateError(
            'This tool intentionally returns an error for testing',
          ),
    );
    registerTool(
      Tool(
        name: _progressTool,
        description: _progressTool,
        inputSchema: ObjectSchema(),
      ),
      _reportProgress,
    );
    registerTool(
      Tool(
        name: _missingCapabilityTool,
        description: _missingCapabilityTool,
        inputSchema: ObjectSchema(),
      ),
      _requireSampling,
    );
    registerTool(
      Tool(
        name: _inputElicitationTool,
        description: _inputElicitationTool,
        inputSchema: ObjectSchema(),
      ),
      _requestElicitationInput,
    );
    registerTool(
      Tool(
        name: _inputSamplingTool,
        description: _inputSamplingTool,
        inputSchema: ObjectSchema(),
      ),
      _requestSamplingInput,
    );
    registerTool(
      Tool(
        name: _inputRootsTool,
        description: _inputRootsTool,
        inputSchema: ObjectSchema(),
      ),
      _requestRootsInput,
    );
    registerTool(
      Tool(
        name: _inputStateTool,
        description: _inputStateTool,
        inputSchema: ObjectSchema(),
      ),
      _requestStateInput,
    );
    registerTool(
      Tool(
        name: _inputMultipleTool,
        description: _inputMultipleTool,
        inputSchema: ObjectSchema(),
      ),
      _requestMultipleInputs,
    );
    registerTool(
      Tool(
        name: _inputMultiRoundTool,
        description: _inputMultiRoundTool,
        inputSchema: ObjectSchema(),
      ),
      _requestMultiRoundInput,
    );
    registerTool(
      Tool(
        name: _inputTamperedTool,
        description: _inputTamperedTool,
        inputSchema: ObjectSchema(),
      ),
      _requestTamperCheckedInput,
    );
    registerTool(
      Tool(
        name: _inputCapabilitiesTool,
        description: _inputCapabilitiesTool,
        inputSchema: ObjectSchema(),
      ),
      _requestCapabilityInputs,
    );
    registerTool(
      Tool(
        name: _jsonSchemaTool,
        description: _jsonSchemaTool,
        inputSchema: _jsonSchema,
      ),
      (_) => CallToolResult(content: [TextContent(text: _jsonSchemaTool)]),
      validateArguments: false,
    );
    // server-stateless calls these two on a second request to change a list
    // while it holds a subscriptions/listen stream open on the first.
    registerTool(
      Tool(
        name: _toolChangeTool,
        description: _toolChangeTool,
        inputSchema: ObjectSchema(),
      ),
      (_) {
        registerTool(
          Tool(
            name: _addedTool,
            description: _addedTool,
            inputSchema: ObjectSchema(),
          ),
          (_) => CallToolResult(content: [TextContent(text: _addedTool)]),
        );
        return CallToolResult(content: [TextContent(text: _addedTool)]);
      },
    );
    registerTool(
      Tool(
        name: _promptChangeTool,
        description: _promptChangeTool,
        inputSchema: ObjectSchema(),
      ),
      (_) {
        addPrompt(
          Prompt(name: _addedPrompt, description: _addedPrompt),
          (_) => GetPromptResult(
            messages: [
              PromptMessage(
                role: Role.user,
                content: TextContent(text: _addedPrompt),
              ),
            ],
          ),
        );
        return CallToolResult(content: [TextContent(text: _addedPrompt)]);
      },
    );
  }

  Future<CallToolResult> _reportProgress(CallToolRequest request) async {
    final progressToken = request.meta?.progressToken;
    if (progressToken != null) {
      for (final progress in [0, 50, 100]) {
        notifyProgress(
          ProgressNotification(
            progressToken: progressToken,
            progress: progress,
            total: 100,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    return CallToolResult(content: [TextContent(text: '$progressToken')]);
  }

  // Resources named by resources-read-text, resources-read-binary, and
  // resources-templates-read.
  void _registerResources() {
    addResource(
      Resource(
        uri: _staticTextUri,
        name: 'static-text',
        description: _staticTextUri,
        mimeType: _textMimeType,
      ),
      (_) => ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: _staticTextUri,
            mimeType: _textMimeType,
            text: 'This is the content of the static text resource.',
          ),
        ],
      ),
    );
    addResource(
      Resource(
        uri: _staticBinaryUri,
        name: 'static-binary',
        description: _staticBinaryUri,
        mimeType: _imageMimeType,
      ),
      (_) => ReadResourceResult(
        contents: [
          BlobResourceContents(
            uri: _staticBinaryUri,
            mimeType: _imageMimeType,
            blob: _imageData,
          ),
        ],
      ),
    );
    addResourceTemplate(
      ResourceTemplate(
        uriTemplate: _templateUri,
        name: 'template',
        description: _templateUri,
        mimeType: _jsonMimeType,
      ),
      _readTemplate,
    );
  }

  CallToolResult _requireSampling(CallToolRequest request) {
    final text = _sampledText(request, 'capability_sample');
    if (text != null) {
      return _completeTool('Success');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'capability_sample': _sample(
            'Need sampling to continue',
            maxTokens: 1,
          ),
        },
      ),
    );
  }

  ReadResourceResult? _readTemplate(ReadResourceRequest request) {
    final uri = Uri.tryParse(request.uri);
    if (uri == null ||
        uri.scheme != 'test' ||
        uri.host != 'template' ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.last != 'data') {
      return null;
    }
    final id = uri.pathSegments.first;
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: request.uri,
          mimeType: _jsonMimeType,
          text: jsonEncode({
            'id': id,
            'templateTest': true,
            'data': 'Data for ID: $id',
          }),
        ),
      ],
    );
  }

  CallToolResult _requestElicitationInput(CallToolRequest request) {
    final name = _acceptedString(request, 'user_name', 'name');
    if (name != null) {
      return _completeTool('Hello, $name!');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'user_name': _elicitString(
            message: 'What is your name?',
            property: 'name',
          ),
        },
      ),
    );
  }

  CallToolResult _requestSamplingInput(CallToolRequest request) {
    final text = _sampledText(request, 'capital_question');
    if (text != null) {
      return _completeTool('Sampling response: $text');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'capital_question': _sample(
            'What is the capital of France?',
            maxTokens: 100,
          ),
        },
      ),
    );
  }

  CallToolResult _requestRootsInput(CallToolRequest request) {
    final roots = _rootsResponse(request, 'client_roots');
    if (roots != null) {
      final uris = roots.map((root) => root['uri']).join(', ');
      return _completeTool('Client exposed ${roots.length} root(s): $uris');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'client_roots': InputRequest.listRoots(ListRootsRequest()),
        },
      ),
    );
  }

  CallToolResult _requestStateInput(CallToolRequest request) {
    final confirmation = _acceptedBool(request, 'confirm', 'ok');
    if (confirmation != null) {
      _verifyState(request.requestState, expectedTool: _inputStateTool);
      return _completeTool(
        'state-ok: requestState verified and confirmation received',
      );
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'confirm': _elicitBool(message: 'Please confirm', property: 'ok'),
        },
        requestState: _mintState({'tool': _inputStateTool}),
      ),
    );
  }

  CallToolResult _requestMultipleInputs(CallToolRequest request) {
    if (request.requestState != null) {
      _verifyState(request.requestState, expectedTool: _inputMultipleTool);
    }
    final name = _acceptedString(request, 'user_name', 'name');
    final greeting = _sampledText(request, 'greeting');
    final roots = _rootsResponse(request, 'client_roots');
    if (name != null && greeting != null && roots != null) {
      return _completeTool('$greeting $name, ${roots.length} root(s) visible');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'user_name': _elicitString(
            message: 'What is your name?',
            property: 'name',
          ),
          'greeting': _sample('Generate a greeting', maxTokens: 50),
          'client_roots': InputRequest.listRoots(ListRootsRequest()),
        },
        requestState: _mintState({'tool': _inputMultipleTool}),
      ),
    );
  }

  CallToolResult _requestMultiRoundInput(CallToolRequest request) {
    if (request.requestState == null) {
      return _toolInputRequired(
        InputRequiredResult(
          inputRequests: {
            'step1': _elicitString(
              message: 'Step 1: What is your name?',
              property: 'name',
            ),
          },
          requestState: _mintState({'tool': _inputMultiRoundTool, 'round': 1}),
        ),
      );
    }
    final state = _verifyState(
      request.requestState,
      expectedTool: _inputMultiRoundTool,
    );
    switch (state['round']) {
      case 1:
        final name = _acceptedString(request, 'step1', 'name');
        if (name == null) {
          return _toolInputRequired(
            InputRequiredResult(
              inputRequests: {
                'step1': _elicitString(
                  message: 'Step 1: What is your name?',
                  property: 'name',
                ),
              },
              requestState: request.requestState,
            ),
          );
        }
        return _toolInputRequired(
          InputRequiredResult(
            inputRequests: {
              'step2': _elicitString(
                message: 'Step 2: What is your favorite color?',
                property: 'color',
              ),
            },
            requestState: _mintState({
              'tool': _inputMultiRoundTool,
              'round': 2,
              'name': name,
            }),
          ),
        );
      case 2:
        final color = _acceptedString(request, 'step2', 'color');
        if (color == null) {
          return _toolInputRequired(
            InputRequiredResult(
              inputRequests: {
                'step2': _elicitString(
                  message: 'Step 2: What is your favorite color?',
                  property: 'color',
                ),
              },
              requestState: request.requestState,
            ),
          );
        }
        return _completeTool(
          'Multi-round complete: ${state['name']} likes $color',
        );
      default:
        throw RpcException.invalidParams(
          'Received requestState with round "${state['round']}". '
          'Expected round 1 or 2.',
        );
    }
  }

  CallToolResult _requestTamperCheckedInput(CallToolRequest request) {
    if (request.requestState != null) {
      _verifyState(request.requestState, expectedTool: _inputTamperedTool);
      if (_acceptedBool(request, 'confirm', 'ok') != null) {
        return _completeTool('integrity-ok: requestState verified');
      }
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'confirm': _elicitBool(message: 'Please confirm', property: 'ok'),
        },
        requestState: _mintState({'tool': _inputTamperedTool}),
      ),
    );
  }

  CallToolResult _requestCapabilityInputs(CallToolRequest request) {
    if (request.inputResponses != null) {
      return _completeTool('Capability-aware input requests fulfilled');
    }
    final requests = <String, InputRequest>{};
    if (clientCapabilities.sampling != null) {
      requests['greeting'] = _sample(
        'Generate a short greeting',
        maxTokens: 50,
      );
    }
    if (clientCapabilities.elicitation != null) {
      requests['user_name'] = _elicitString(
        message: 'What is your name?',
        property: 'name',
      );
    }
    if (clientCapabilities.roots != null) {
      requests['client_roots'] = InputRequest.listRoots(ListRootsRequest());
    }
    if (requests.isEmpty) {
      return _completeTool(
        'No declared client capability supports an in-band input request',
      );
    }
    return _toolInputRequired(InputRequiredResult(inputRequests: requests));
  }

  Map<String, Object?>? _inputResponse(WithInputResponses request, String key) {
    final values = request as Map<String, Object?>;
    final responses = values['inputResponses'];
    if (responses is! Map || !responses.containsKey(key)) return null;
    final response = responses[key];
    return response is Map ? response.cast<String, Object?>() : null;
  }

  String? _acceptedString(
    WithInputResponses request,
    String key,
    String property,
  ) {
    final content = _acceptedContent(request, key);
    final value = content?[property];
    return value is String ? value : null;
  }

  bool? _acceptedBool(WithInputResponses request, String key, String property) {
    final content = _acceptedContent(request, key);
    final value = content?[property];
    return value is bool ? value : null;
  }

  Map<String, Object?>? _acceptedContent(
    WithInputResponses request,
    String key,
  ) {
    final response = _inputResponse(request, key);
    if (response?['action'] != 'accept') return null;
    final content = response?['content'];
    return content is Map ? content.cast<String, Object?>() : null;
  }

  String? _sampledText(WithInputResponses request, String key) {
    final response = _inputResponse(request, key);
    final content = response?['content'];
    if (content is! Map) return null;
    final values = content.cast<String, Object?>();
    final text = values['text'];
    return values['type'] == 'text' && text is String ? text : null;
  }

  List<Map<String, Object?>>? _rootsResponse(
    WithInputResponses request,
    String key,
  ) {
    final response = _inputResponse(request, key);
    final roots = response?['roots'];
    if (roots is! List) return null;
    final result = <Map<String, Object?>>[];
    for (final root in roots) {
      if (root is! Map) return null;
      final values = root.cast<String, Object?>();
      if (values['uri'] is! String) return null;
      result.add(values);
    }
    return result;
  }

  String _mintState(Map<String, Object?> state) {
    final envelope = {
      'p': {
        ...state,
        'nonce': base64UrlEncode(
          List<int>.generate(16, (_) => _stateRandom.nextInt(256)),
        ),
      },
      'exp':
          DateTime.now().millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond +
          600,
    };
    final body = base64UrlEncode(
      utf8.encode(jsonEncode(envelope)),
    ).replaceAll('=', '');
    final signature = base64UrlEncode(
      _stateHmac.convert(utf8.encode('v1.$body')).bytes,
    ).replaceAll('=', '');
    return 'v1.$body.$signature';
  }

  Map<String, Object?> _verifyState(
    String? state, {
    required String expectedTool,
  }) {
    try {
      if (state == null) throw const FormatException('Missing state');
      final signatureSeparator = state.lastIndexOf('.');
      if (!state.startsWith('v1.') || signatureSeparator <= 3) {
        throw const FormatException('Invalid state');
      }
      final body = state.substring(3, signatureSeparator);
      final expectedSignature = base64UrlEncode(
        _stateHmac.convert(utf8.encode('v1.$body')).bytes,
      ).replaceAll('=', '');
      if (!_constantTimeEquals(
        state.substring(signatureSeparator + 1),
        expectedSignature,
      )) {
        throw const FormatException('Invalid signature');
      }
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(_withBase64Padding(body))),
      );
      if (decoded is! Map) throw const FormatException('Invalid envelope');
      final envelope = decoded.cast<String, Object?>();
      final expiresAt = envelope['exp'];
      final now =
          DateTime.now().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
      if (expiresAt is! num || expiresAt < now) {
        throw const FormatException('Expired state');
      }
      final statePayload = envelope['p'];
      if (statePayload is! Map) {
        throw const FormatException('Invalid payload');
      }
      final payload = statePayload.cast<String, Object?>();
      if (payload['tool'] != expectedTool) {
        throw const FormatException('Invalid tool');
      }
      return payload;
    } on FormatException {
      throw RpcException.invalidParams(
        'Received a requestState that failed integrity validation. '
        'Expected an unmodified state issued by this server.',
      );
    }
  }

  String _withBase64Padding(String value) {
    final padding = (4 - value.length % 4) % 4;
    return value.padRight(value.length + padding, '=');
  }

  bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index++) {
      final leftCode = index < left.length ? left.codeUnitAt(index) : 0;
      final rightCode = index < right.length ? right.codeUnitAt(index) : 0;
      difference |= leftCode ^ rightCode;
    }
    return difference == 0;
  }

  CallToolResult _completeTool(String text) =>
      CallToolResult(content: [TextContent(text: text)]);

  // A handler's return type does not admit an `InputRequiredResult` yet, so
  // the tool goes through the map the two extension types share. The wire
  // shape is the one the spec asks for either way, and these two lines are
  // where a widened signature would let the tool return the result directly.
  CallToolResult _toolInputRequired(InputRequiredResult result) =>
      CallToolResult.fromMap(result as Map<String, Object?>);

  GetPromptResult _promptInputRequired(InputRequiredResult result) =>
      GetPromptResult.fromMap(result as Map<String, Object?>);

  InputRequest _elicitString({
    required String message,
    required String property,
  }) => InputRequest.elicit(
    ElicitRequest.form(
      message: message,
      requestedSchema: ObjectSchema(
        properties: {property: Schema.string()},
        required: [property],
      ),
    ),
  );

  InputRequest _elicitBool({
    required String message,
    required String property,
  }) => InputRequest.elicit(
    ElicitRequest.form(
      message: message,
      requestedSchema: ObjectSchema(
        properties: {property: Schema.bool()},
        required: [property],
      ),
    ),
  );

  InputRequest _sample(String text, {required int maxTokens}) =>
      InputRequest.sample(
        CreateMessageRequest(
          messages: [
            SamplingMessage(role: Role.user, content: TextContent(text: text)),
          ],
          maxTokens: maxTokens,
        ),
      );

  // Prompts named by prompts-get-* and input-required-result-non-tool-request.
  void _registerPrompts() {
    addPrompt(
      Prompt(name: _simplePrompt, description: _simplePrompt),
      (_) => GetPromptResult(
        messages: [
          PromptMessage(
            role: Role.user,
            content: TextContent(text: 'This is a simple prompt for testing.'),
          ),
        ],
      ),
    );
    addPrompt(
      Prompt(
        name: _argumentsPrompt,
        description: _argumentsPrompt,
        arguments: [
          PromptArgument(name: 'arg1', required: true),
          PromptArgument(name: 'arg2', required: true),
        ],
      ),
      (request) {
        final arguments = request.arguments ?? const <String, Object?>{};
        return GetPromptResult(
          messages: [
            PromptMessage(
              role: Role.user,
              content: TextContent(
                text:
                    "Prompt with arguments: arg1='${arguments['arg1']}', "
                    "arg2='${arguments['arg2']}'",
              ),
            ),
          ],
        );
      },
    );
    addPrompt(
      Prompt(
        name: _embeddedResourcePrompt,
        description: _embeddedResourcePrompt,
        arguments: [PromptArgument(name: 'resourceUri', required: true)],
      ),
      (request) {
        final resourceUri = request.arguments!['resourceUri'] as String;
        return GetPromptResult(
          messages: [
            PromptMessage(
              role: Role.user,
              content: EmbeddedResource(
                resource: TextResourceContents(
                  uri: resourceUri,
                  mimeType: _textMimeType,
                  text: 'Embedded resource content for testing.',
                ),
              ),
            ),
            PromptMessage(
              role: Role.user,
              content: TextContent(
                text: 'Please process the embedded resource above.',
              ),
            ),
          ],
        );
      },
    );
    addPrompt(
      Prompt(name: _imagePrompt, description: _imagePrompt),
      (_) => GetPromptResult(
        messages: [
          PromptMessage(
            role: Role.user,
            content: ImageContent(data: _imageData, mimeType: _imageMimeType),
          ),
          PromptMessage(
            role: Role.user,
            content: TextContent(text: 'Please analyze the image above.'),
          ),
        ],
      ),
    );
    addPrompt(Prompt(name: _inputPrompt, description: _inputPrompt), (request) {
      final context = _acceptedString(request, 'user_context', 'context');
      if (context != null) {
        return GetPromptResult(
          messages: [
            PromptMessage(
              role: Role.user,
              content: TextContent(text: 'Use the following context: $context'),
            ),
          ],
        );
      }
      return _promptInputRequired(
        InputRequiredResult(
          inputRequests: {
            'user_context': _elicitString(
              message: 'What context should the prompt use?',
              property: 'context',
            ),
          },
        ),
      );
    });
  }

  // completion-complete only needs the method to answer. Empty values are
  // enough.
  @override
  FutureOr<CompleteResult> handleComplete(CompleteRequest request) =>
      CompleteResult(
        completion: Completion(values: const [], total: 0, hasMore: false),
      );
}
