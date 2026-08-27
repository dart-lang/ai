// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/streamable_http.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

const _path = '/mcp';
const _imageMimeType = 'image/png';
const _audioMimeType = 'audio/wav';
const _textMimeType = 'text/plain';
const _jsonMimeType = 'application/json';
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
const _jsonSchemaTool = 'json_schema_2020_12_tool';
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

const _requestState = 'request-state';
const _multipleRequestState = 'multiple-request-state';
const _roundOneState = 'round-one-state';
const _roundTwoState = 'round-two-state';
const _tamperState = 'tamper-state';

final _headerToolSchema = ObjectSchema.fromMap({
  'type': 'object',
  'properties': {
    'name': {'type': 'string', 'x-mcp-header': 'Name'},
  },
});

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

/// Runs the server fixture used by the MCP conformance suite.
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

Future<void> _handleRequest(HttpRequest request) async {
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

  try {
    await handleStreamableHttpRequest(request, _ConformanceServer.new);
  } catch (error, stackTrace) {
    stderr
      ..writeln(error)
      ..writeln(stackTrace);
  }
}

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
    with ToolsSupport, ResourcesSupport, PromptsSupport, CompletionsSupport {
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

  void _registerTools() {
    registerTool(
      Tool(
        name: _simpleTextTool,
        description: _simpleTextTool,
        inputSchema: _headerToolSchema,
      ),
      (_) => CallToolResult(
        content: [
          TextContent(text: 'This is a simple text response for testing.'),
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

  Future<CallToolResult> _requireSampling(CallToolRequest _) async {
    if (!supportsSampling) {
      await createMessage(CreateMessageRequest(messages: [], maxTokens: 1));
    }
    return CallToolResult(content: [TextContent(text: 'Success')]);
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
    if (_inputResponse(request, 'user_name') != null) {
      return _completeTool('Hello');
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
    if (_inputResponse(request, 'capital_question') != null) {
      return _completeTool('Sampling complete');
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
    if (_inputResponse(request, 'client_roots') != null) {
      return _completeTool('Roots received');
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
    if (_inputResponse(request, 'confirm') != null &&
        request.requestState == _requestState) {
      return _completeTool('state-ok');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'confirm': _elicitBool(message: 'Please confirm', property: 'ok'),
        },
        requestState: _requestState,
      ),
    );
  }

  CallToolResult _requestMultipleInputs(CallToolRequest request) {
    if (_inputResponse(request, 'user_name') != null &&
        _inputResponse(request, 'greeting') != null &&
        _inputResponse(request, 'client_roots') != null &&
        request.requestState == _multipleRequestState) {
      return _completeTool('Multiple inputs received');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'user_name': _elicitString(
            message: 'What is your name?',
            property: 'name',
          ),
          'greeting': _sample('Write a short greeting', maxTokens: 50),
          'client_roots': InputRequest.listRoots(ListRootsRequest()),
        },
        requestState: _multipleRequestState,
      ),
    );
  }

  CallToolResult _requestMultiRoundInput(CallToolRequest request) {
    if (_inputResponse(request, 'step2') != null &&
        request.requestState == _roundTwoState) {
      return _completeTool('Two rounds complete');
    }
    if (_inputResponse(request, 'step1') != null &&
        request.requestState == _roundOneState) {
      return _toolInputRequired(
        InputRequiredResult(
          inputRequests: {
            'step2': _elicitString(
              message: 'What is your favorite color?',
              property: 'color',
            ),
          },
          requestState: _roundTwoState,
        ),
      );
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'step1': _elicitString(
            message: 'What is your name?',
            property: 'name',
          ),
        },
        requestState: _roundOneState,
      ),
    );
  }

  CallToolResult _requestTamperCheckedInput(CallToolRequest request) {
    if (_inputResponse(request, 'confirm') != null) {
      if (request.requestState != _tamperState) {
        throw RpcException.invalidParams(
          'Received requestState "${request.requestState}". '
          'Expected "$_tamperState".',
        );
      }
      return _completeTool('State accepted');
    }
    return _toolInputRequired(
      InputRequiredResult(
        inputRequests: {
          'confirm': _elicitBool(message: 'Please confirm', property: 'ok'),
        },
        requestState: _tamperState,
      ),
    );
  }

  CallToolResult _requestCapabilityInputs(CallToolRequest _) {
    final requests = <String, InputRequest>{};
    if (clientCapabilities.sampling != null) {
      requests['sampling'] = _sample('Say hello', maxTokens: 20);
    }
    if (clientCapabilities.elicitation != null) {
      requests['elicitation'] = _elicitString(
        message: 'What is your name?',
        property: 'name',
      );
    }
    if (clientCapabilities.roots != null) {
      requests['roots'] = InputRequest.listRoots(ListRootsRequest());
    }
    if (requests.isEmpty) return _completeTool('No inputs requested');
    return _toolInputRequired(InputRequiredResult(inputRequests: requests));
  }

  Result? _inputResponse(WithInputResponses request, String key) {
    final responses = request.inputResponses;
    if (responses == null || !responses.containsKey(key)) return null;
    return responses[key];
  }

  CallToolResult _completeTool(String text) =>
      CallToolResult(content: [TextContent(text: text)]);

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
      if (_inputResponse(request, 'user_context') != null) {
        return GetPromptResult(
          messages: [
            PromptMessage(
              role: Role.user,
              content: TextContent(text: 'Context received'),
            ),
          ],
        );
      }
      return _promptInputRequired(
        InputRequiredResult(
          inputRequests: {
            'user_context': _elicitString(
              message: 'Please provide context',
              property: 'context',
            ),
          },
        ),
      );
    });
  }

  @override
  FutureOr<CompleteResult> handleComplete(CompleteRequest request) =>
      CompleteResult(
        completion: Completion(values: const [], total: 0, hasMore: false),
      );
}
