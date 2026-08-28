// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/src/utils/constants.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('request dispatcher', () {
    test('serves a request on a fresh initialized server', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(harness.servers, hasLength(1));
      final result = _result(response);
      final toolResult = CallToolResult.fromMap(result);
      expect(
        (toolResult.content.single as TextContent).text,
        'ready: true',
        reason: 'initialized must complete before the message is handled',
      );
    });

    test('records server info on the response', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      final serverInfo = Implementation.fromMap(
        meta[Keys.serverInfoMeta] as Map<String, Object?>,
      );
      expect(serverInfo.name, 'test server');
      expect(serverInfo.version, '0.1.0');
    });

    test('preserves an existing server info entry', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('custom_info'),
        _initialization(),
      );

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      final serverInfo = Implementation.fromMap(
        meta[Keys.serverInfoMeta] as Map<String, Object?>,
      );
      expect(serverInfo.name, 'already there');
    });

    test('records a result type on the response', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(
        _result(response),
        containsPair(Keys.resultType, ResultTypes.complete),
      );
    });

    test('preserves the result type a handler chose', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('interim'),
        _initialization(),
      );

      expect(
        _result(response),
        containsPair(Keys.resultType, ResultTypes.inputRequired),
      );
    });

    test('records caching hints on a result which takes them', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_listTools(), _initialization());

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('leaves caching hints off results which do not take them', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(_result(response), isNot(contains(Keys.ttlMs)));
      expect(_result(response), isNot(contains(Keys.cacheScope)));
    });

    test('records caching hints on a read as well as a list', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _readResource(),
        _initialization(),
      );

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('preserves the caching hints a handler chose', () async {
      final response = await _dispatchShapedList(
        (result) => {...result, Keys.ttlMs: 5000, Keys.cacheScope: 'public'},
      );

      expect(_result(response), containsPair(Keys.ttlMs, 5000));
      expect(_result(response), containsPair(Keys.cacheScope, 'public'));

      // Zero is the edge of what the schema allows, and a handler which sends
      // it means it: the answer is stale as soon as it arrives.
      final errors = <Object>[];
      Map<String, Object?>? withZero;
      await runZonedGuarded(() async {
        withZero = await _dispatchShapedList(
          (result) => {...result, Keys.ttlMs: 0},
        );
      }, (error, _) => errors.add(error));

      expect(errors, isEmpty);
      expect(_result(withZero), containsPair(Keys.ttlMs, 0));
    });

    test('sends none of these fields on an earlier revision', () async {
      // All of them are 2026-07-28 vocabulary, including the reserved
      // metadata key.
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _listTools(),
        _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
      );

      expect(_result(response), isNot(contains(Keys.resultType)));
      expect(_result(response), isNot(contains(Keys.ttlMs)));
      expect(_result(response), isNot(contains(Keys.cacheScope)));
      expect(_result(response), isNot(contains(Keys.meta)));
    });

    test('fills in fields a handler left null', () async {
      // A null is a field the handler did not answer, not an answer of null:
      // sending one on the wire would be a value the schema does not allow.
      final response = await _dispatchShapedList(
        (result) => {
          ...result,
          Keys.resultType: null,
          Keys.ttlMs: null,
          Keys.cacheScope: null,
        },
      );

      expect(
        _result(response),
        containsPair(Keys.resultType, ResultTypes.complete),
      );
      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('fills in the caching hint a handler left out', () async {
      final withTtl = await _dispatchShapedList(
        (result) => {...result, Keys.ttlMs: 5000},
      );
      expect(_result(withTtl), containsPair(Keys.ttlMs, 5000));
      expect(_result(withTtl), containsPair(Keys.cacheScope, 'private'));

      final withScope = await _dispatchShapedList(
        (result) => {...result, Keys.cacheScope: 'public'},
      );
      expect(_result(withScope), containsPair(Keys.ttlMs, 0));
      expect(_result(withScope), containsPair(Keys.cacheScope, 'public'));
    });

    test('rejects a ttl the schema does not allow', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await _dispatchShapedList((result) => {...result, Keys.ttlMs: -1});
      }, (error, _) => errors.add(error));

      expect(errors.single, isA<AssertionError>());
      expect(errors.single.toString(), contains(Keys.ttlMs));
      // A compiled executable has asserts stripped, so there is nothing to
      // catch there.
    }, testOn: '!exe');

    test('rejects a cache scope the schema does not allow', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await _dispatchShapedList(
          (result) => {...result, Keys.cacheScope: 'shared'},
        );
      }, (error, _) => errors.add(error));

      expect(errors.single, isA<AssertionError>());
      expect(errors.single.toString(), contains(Keys.cacheScope));
    }, testOn: '!exe');

    test('records caching hints despite a result type the schema does not '
        'give the request', () async {
      // `tools/list` has no interim arm, so a non-complete type there does not
      // make the result one the caching rules exempt. The schema types
      // `resultType` as a bare string, so a server may send one this package
      // has no name for; `input_required` is not among the ones it may send
      // here, and the dispatcher refuses that separately.
      final response = await _dispatchShapedList(
        (result) => {...result, Keys.resultType: 'io.example/other'},
      );

      expect(_result(response), containsPair(Keys.ttlMs, 0));
      expect(_result(response), containsPair(Keys.cacheScope, 'private'));
    });

    test('leaves caching hints off an interim result', () async {
      // The schema gives `resources/read` an interim arm; `tools/list` has
      // none, so a list result is never the one waiting on input.
      final response = await _dispatchShapedRead(
        (result) => {
          ...result,
          Keys.resultType: ResultTypes.inputRequired,
          Keys.requestState: 'waiting',
        },
      );

      expect(_result(response), isNot(contains(Keys.ttlMs)));
      expect(_result(response), isNot(contains(Keys.cacheScope)));
    });

    test('answers even when a result has malformed metadata', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('bad_meta'),
        _initialization(),
      );

      // Server info stamping is skipped rather than throwing and wedging.
      expect(_result(response)[Keys.meta], 'not a map');
    });

    test('answers even when metadata has non-string keys', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('bad_meta_keys'),
        _initialization(),
      );

      // Server info stamping is skipped rather than throwing and wedging.
      expect(_result(response)[Keys.meta], {1: 'kept'});
    });

    test('stamps server info on an unmodifiable result', () async {
      final harness = _DispatcherHarness();
      // The built-in ping handler returns `EmptyResult()`, which is backed
      // by a const map.
      final response = await harness.dispatch(_ping(), _initialization());

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      expect(meta[Keys.serverInfoMeta], isNotNull);
    });

    test('leaves the result map a handler returned unmodified', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('retained'),
        _initialization(),
      );

      expect(_result(response)[Keys.meta], isNotNull);
      final retained = harness.servers.single.retainedResult!;
      expect(retained, isNot(contains(Keys.meta)));
    });

    test('declares client capabilities per request', () async {
      final harness = _DispatcherHarness();
      await harness.dispatch(
        _callTool('probe'),
        _initialization(
          capabilities: ClientCapabilities(roots: RootsCapabilities()),
        ),
      );
      await harness.dispatch(_callTool('probe'), _initialization());

      expect(harness.servers, hasLength(2));
      final first = harness.servers[0];
      final second = harness.servers[1];
      expect(first, isNot(same(second)));
      expect(first.clientCapabilities.roots, isNotNull);
      expect(second.clientCapabilities.roots, isNull);
    });

    test('serves a request which declares no client info', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('probe'),
        _initialization(),
      );

      expect(harness.servers.single.clientInfo, isNull);
      expect(_result(response), isNotEmpty);
    });

    test('passes emitted notifications to onNotification', () async {
      final harness = _DispatcherHarness();
      final notifications = <Map<String, Object?>>[];
      await harness.dispatch(
        _callTool('notify'),
        _initialization(logLevel: LoggingLevel.error),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(ProgressNotification.methodName));
      expect(methods, contains(LoggingMessageNotification.methodName));
    });

    test('delivers notifications emitted during initialization', () async {
      final servers = <_RootsTrackingDispatcherServer>[];
      final notifications = <Map<String, Object?>>[];
      // Without the roots capability, roots tracking logs a warning as it
      // initializes, before the dispatched message is handled.
      await handleRequestScopedMessage(
        _listTools(),
        _initialization(logLevel: LoggingLevel.warning),
        (channel) {
          final server = _RootsTrackingDispatcherServer(channel);
          servers.add(server);
          return server;
        },
        onNotification: notifications.add,
      );

      expect(
        notifications.map((n) => n[Keys.method]),
        contains(LoggingMessageNotification.methodName),
      );
    });

    test('drops a handler log when the request named no level', () async {
      final harness = _DispatcherHarness();
      final notifications = <Map<String, Object?>>[];
      await harness.dispatch(
        _callTool('notify'),
        _initialization(),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(ProgressNotification.methodName));
      expect(methods, isNot(contains(LoggingMessageNotification.methodName)));
    });

    test('applies the level a request asked for', () async {
      final harness = _DispatcherHarness();
      final notifications = <Map<String, Object?>>[];
      // The `notify` tool logs at error, which is below emergency.
      await harness.dispatch(
        _callTool('notify'),
        _initialization(logLevel: LoggingLevel.emergency),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(ProgressNotification.methodName));
      expect(methods, isNot(contains(LoggingMessageNotification.methodName)));
    });

    test('keeps logging on a revision with no per-request level', () async {
      final harness = _DispatcherHarness();
      final notifications = <Map<String, Object?>>[];
      await harness.dispatch(
        _callTool('notify'),
        _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(LoggingMessageNotification.methodName));
    });

    test('drops a level the server picked for itself', () async {
      final harness = _DispatcherHarness(pickedLogLevel: LoggingLevel.warning);
      final notifications = <Map<String, Object?>>[];
      await harness.dispatch(
        _callTool('notify'),
        _initialization(),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(ProgressNotification.methodName));
      expect(
        methods,
        isNot(contains(LoggingMessageNotification.methodName)),
        reason: 'a level the server picked is not a level the request named',
      );
    });

    test('keeps a level the server picked on an earlier revision', () async {
      final harness = _DispatcherHarness(
        pickedLogLevel: LoggingLevel.emergency,
      );
      final notifications = <Map<String, Object?>>[];
      // Starting at the `warning` default instead would send the error the
      // `notify` tool logs.
      await harness.dispatch(
        _callTool('notify'),
        _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
        onNotification: notifications.add,
      );

      final methods = [for (final n in notifications) n[Keys.method]];
      expect(methods, contains(ProgressNotification.methodName));
      expect(methods, isNot(contains(LoggingMessageNotification.methodName)));
    });

    test('serves logging/setLevel only where the revision has it', () async {
      final harness = _DispatcherHarness();
      final modern = await harness.dispatch(_setLevel(), _initialization());
      final legacy = await harness.dispatch(
        _setLevel(),
        _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
      );

      expect(
        (modern![Keys.error] as Map<String, Object?>?)?[Keys.code],
        error_code.METHOD_NOT_FOUND,
        reason: 'setLevel would hand a level to a request that named none',
      );
      expect(legacy![Keys.result], isNotNull);
    });

    test('fails server to client requests instead of hanging', () async {
      final harness = _DispatcherHarness();
      // The client declares roots, so `listRoots` reaches the transport rather
      // than being refused for the missing capability.
      final response = await harness.dispatch(
        _callTool('roots'),
        _initialization(
          capabilities: ClientCapabilities(roots: RootsCapabilities()),
        ),
      );

      final error = response![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.INTERNAL_ERROR);
      expect(error[Keys.message], contains('request-scoped transport'));
    });

    test('refuses input_required on a request it is not allowed on', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _complete('input_required'),
        _initialization(),
      );

      final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
      final error = wire['error'] as Map<String, Object?>;
      expect(error['code'], -32603);
      expect(error['message'], contains(CompleteRequest.methodName));
      expect(error['message'], contains(CallToolRequest.methodName));
    });

    test('serves input_required on allowed requests', () async {
      final harness = _DispatcherHarness();
      for (final (method, response) in [
        (
          CallToolRequest.methodName,
          await harness.dispatch(_callTool('interim'), _initialization()),
        ),
        (
          GetPromptRequest.methodName,
          await harness.dispatch(_getPrompt('interim'), _initialization()),
        ),
        (
          ReadResourceRequest.methodName,
          await _dispatchShapedRead(
            (result) => {
              ...result,
              Keys.resultType: ResultTypes.inputRequired,
              Keys.requestState: 'waiting',
            },
          ),
        ),
      ]) {
        final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
        expect(wire['error'], isNull, reason: method);
        expect(
          (wire['result'] as Map<String, Object?>)['resultType'],
          'input_required',
          reason: method,
        );
      }
    });

    test('refuses an input request the client cannot answer', () async {
      final harness = _DispatcherHarness();
      for (final (tool, capability, required) in [
        (
          'asks_to_elicit',
          'elicitation.form',
          {
            'elicitation': {'form': <String, Object?>{}},
          },
        ),
        ('asks_to_sample', 'sampling', {'sampling': <String, Object?>{}}),
        ('asks_for_roots', 'roots', {'roots': <String, Object?>{}}),
      ]) {
        final response = await harness.dispatch(
          _callTool(tool),
          _initialization(),
        );

        final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
        final error = wire['error'] as Map<String, Object?>;
        expect(error['code'], -32021, reason: tool);
        expect(error['message'], contains(capability), reason: tool);
        final data = error['data'] as Map<String, Object?>;
        expect(data['requiredCapabilities'], required, reason: tool);
      }
    });

    test('requires sampling.tools for tools and toolChoice', () async {
      for (final field in [Keys.tools, Keys.toolChoice]) {
        Map<String, Object?> shape(Map<String, Object?> result) => {
          ...result,
          Keys.resultType: ResultTypes.inputRequired,
          Keys.inputRequests: {
            CreateMessageRequest.methodName: InputRequest.sample(
              CreateMessageRequest.fromMap({
                Keys.messages: <Object?>[],
                Keys.maxTokens: 1,
                field:
                    field == Keys.tools
                        ? <Object?>[]
                        : ToolChoice(mode: ToolChoiceMode.auto),
              }),
            ),
          },
        };

        final refused = await _dispatchShapedRead(
          shape,
          capabilities: ClientCapabilities(sampling: {}),
        );
        final wire = jsonDecode(jsonEncode(refused)) as Map<String, Object?>;
        final rawError = wire['error'];
        expect(rawError, isA<Map<String, Object?>>(), reason: field);
        final error = rawError as Map<String, Object?>;
        expect(error['code'], -32021, reason: field);
        expect(error['message'], contains('sampling.tools'), reason: field);
        final data = error['data'] as Map<String, Object?>;
        expect(data['requiredCapabilities'], {
          'sampling': {'tools': <String, Object?>{}},
        }, reason: field);

        final served = await _dispatchShapedRead(
          shape,
          capabilities: ClientCapabilities(
            sampling: {Keys.tools: <String, Object?>{}},
          ),
        );
        final servedWire =
            jsonDecode(jsonEncode(served)) as Map<String, Object?>;
        expect(servedWire['error'], isNull, reason: field);
      }
    });

    test('checks every input request, not just the first', () async {
      final response = await _dispatchShapedRead(
        (result) => {
          ...result,
          Keys.resultType: ResultTypes.inputRequired,
          Keys.inputRequests: {
            ElicitRequest.methodName: InputRequest.elicit(
              ElicitRequest.form(
                message: 'Fill this in',
                requestedSchema: ObjectSchema(),
              ),
            ),
            ListRootsRequest.methodName: InputRequest.listRoots(
              ListRootsRequest(),
            ),
          },
        },
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
      );

      final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
      final error = wire['error'] as Map<String, Object?>;
      expect(error['code'], -32021);
      expect(error['message'], contains('roots'));
      final data = error['data'] as Map<String, Object?>;
      expect(data['requiredCapabilities'], {'roots': <String, Object?>{}});
    });

    test('serves an input request the client declared', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('asks_to_elicit'),
        _initialization(
          capabilities: ClientCapabilities(
            elicitation: ElicitationCapability(form: {}),
          ),
        ),
      );

      expect(response![Keys.error], isNull);
      expect(_result(response)[Keys.inputRequests], isNotEmpty);
    });

    test('reads the elicitation mode the way the request does', () async {
      // A client which declared only url elicitation cannot answer a form
      // request, and `ElicitationRequestSupport.elicit` refuses the same
      // request on a connected transport.
      final harness = _DispatcherHarness();
      final urlOnly = _initialization(
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(url: {}),
        ),
      );
      final refused = await harness.dispatch(
        _callTool('asks_to_elicit'),
        urlOnly,
      );

      final refusedWire =
          jsonDecode(jsonEncode(refused)) as Map<String, Object?>;
      final error = refusedWire['error'] as Map<String, Object?>;
      expect(error['code'], -32021);
      expect(error['message'], contains('elicitation.form'));
      expect((error['data'] as Map)['requiredCapabilities'], {
        'elicitation': {'form': <String, Object?>{}},
      });

      // And the other way around: a client with only form support cannot
      // answer a url request.
      final formOnly = _initialization(
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
      );
      final urlRefused = await harness.dispatch(
        _callTool('asks_to_elicit_by_url'),
        formOnly,
      );

      final urlWire =
          jsonDecode(jsonEncode(urlRefused)) as Map<String, Object?>;
      final urlError = urlWire['error'] as Map<String, Object?>;
      expect(urlError['code'], -32021);
      expect(urlError['message'], contains('elicitation.url'));
      expect((urlError['data'] as Map)['requiredCapabilities'], {
        'elicitation': {'url': <String, Object?>{}},
      });

      final urlServed = await harness.dispatch(
        _callTool('asks_to_elicit_by_url'),
        urlOnly,
      );
      expect(urlServed![Keys.error], isNull);

      // An empty `elicitation` object still counts as form support, the
      // backwards compatibility rule the mode split came with.
      final bare = await harness.dispatch(
        _callTool('asks_to_elicit'),
        _initialization(
          capabilities: ClientCapabilities(
            elicitation: ElicitationCapability.fromMap({}),
          ),
        ),
      );
      expect(bare![Keys.error], isNull);
    });

    test('treats a missing elicitation mode as form', () async {
      final params = <String, Object?>{
        Keys.message: 'Fill this in',
        Keys.requestedSchema: {
          Keys.type: JsonType.object.typeName,
          Keys.properties: <String, Object?>{},
        },
      };
      Map<String, Object?> shape(Map<String, Object?> result) => {
        ...result,
        Keys.resultType: ResultTypes.inputRequired,
        Keys.inputRequests: {
          ElicitRequest.methodName: InputRequest.fromMap({
            Keys.method: ElicitRequest.methodName,
            Keys.params: params,
          }),
        },
      };

      final refused = await _dispatchShapedRead(
        shape,
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(url: {}),
        ),
      );
      final wire = jsonDecode(jsonEncode(refused)) as Map<String, Object?>;
      final error = wire['error'] as Map<String, Object?>;
      expect(error['code'], -32021);
      expect(error['message'], contains('elicitation.form'));

      final served = await _dispatchShapedRead(
        shape,
        capabilities: ClientCapabilities(
          elicitation: ElicitationCapability(form: {}),
        ),
      );
      final servedWire = jsonDecode(jsonEncode(served)) as Map<String, Object?>;
      expect(servedWire['error'], isNull);
    });

    test('rejects unknown elicitation modes', () async {
      for (final mode in ['voice', 1]) {
        Map<String, Object?> shape(Map<String, Object?> result) => {
          ...result,
          Keys.resultType: ResultTypes.inputRequired,
          Keys.inputRequests: {
            ElicitRequest.methodName: InputRequest.fromMap({
              Keys.method: ElicitRequest.methodName,
              Keys.params: {
                Keys.mode: mode,
                Keys.message: 'Fill this in',
                Keys.requestedSchema: {
                  Keys.type: JsonType.object.typeName,
                  Keys.properties: <String, Object?>{},
                },
              },
            }),
          },
        };

        final response = await _dispatchShapedRead(shape);
        final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
        final rawError = wire['error'];
        expect(rawError, isA<Map<String, Object?>>(), reason: '$mode');
        final error = rawError as Map<String, Object?>;
        expect(error['code'], -32603, reason: '$mode');
        expect(error['message'], contains('form'), reason: '$mode');
        expect(error['message'], contains('url'), reason: '$mode');
      }
    });

    test('rejects malformed inputRequests', () async {
      for (final requests in [
        'not a map',
        {'answer': 'not a map either'},
      ]) {
        final response = await _dispatchShapedRead(
          (result) => {
            ...result,
            Keys.resultType: ResultTypes.inputRequired,
            Keys.inputRequests: requests,
          },
        );

        final rawError = response![Keys.error];
        expect(rawError, isA<Map<String, Object?>>(), reason: '$requests');
        final error = rawError as Map<String, Object?>;
        expect(
          error[Keys.code],
          error_code.INTERNAL_ERROR,
          reason: '$requests',
        );
      }
    });

    test('rejects an input request the revision has no arm for', () async {
      // A request with no method at all lands here too.
      for (final request in [
        <String, Object?>{Keys.params: <String, Object?>{}},
        <String, Object?>{Keys.method: 'io.example/ask'},
      ]) {
        final response = await _dispatchShapedRead(
          (result) => {
            ...result,
            Keys.resultType: ResultTypes.inputRequired,
            Keys.inputRequests: {'answer': request},
          },
        );

        final rawError = response![Keys.error];
        expect(rawError, isA<Map<String, Object?>>(), reason: '$request');
        final error = rawError as Map<String, Object?>;
        expect(error[Keys.code], error_code.INTERNAL_ERROR, reason: '$request');
        for (final method in [
          ElicitRequest.methodName,
          CreateMessageRequest.methodName,
          ListRootsRequest.methodName,
        ]) {
          expect(error[Keys.message], contains(method), reason: '$request');
        }
      }
    });

    test('rejects malformed input request params', () async {
      for (final (method, params) in [
        (ElicitRequest.methodName, null),
        (ElicitRequest.methodName, <Object?>[]),
        (CreateMessageRequest.methodName, null),
        (CreateMessageRequest.methodName, <Object?>[]),
        (ListRootsRequest.methodName, 'not a map'),
      ]) {
        final response = await _dispatchShapedRead(
          (result) => {
            ...result,
            Keys.resultType: ResultTypes.inputRequired,
            Keys.inputRequests: {
              'answer': {
                Keys.method: method,
                if (params != null) Keys.params: params,
              },
            },
          },
        );

        final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
        final rawError = wire['error'];
        expect(
          rawError,
          isA<Map<String, Object?>>(),
          reason: '$method: $params',
        );
        final error = rawError as Map<String, Object?>;
        expect(error['code'], -32603, reason: '$method: $params');
      }
    });

    test('rejects an input_required result with no work or state', () async {
      for (final shape in [
        <String, Object?>{},
        <String, Object?>{Keys.requestState: 7},
      ]) {
        final response = await _dispatchShapedRead(
          (result) => {
            ...result,
            Keys.resultType: ResultTypes.inputRequired,
            ...shape,
          },
        );

        final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
        final rawError = wire['error'];
        expect(rawError, isA<Map<String, Object?>>(), reason: '$shape');
        final error = rawError as Map<String, Object?>;
        expect(error['code'], -32603, reason: '$shape');
      }
    });

    test('serves empty inputRequests and string requestState', () async {
      for (final shape in [
        <String, Object?>{Keys.inputRequests: <String, Object?>{}},
        <String, Object?>{Keys.requestState: 'waiting'},
      ]) {
        final response = await _dispatchShapedRead(
          (result) => {
            ...result,
            Keys.resultType: ResultTypes.inputRequired,
            ...shape,
          },
        );

        final wire = jsonDecode(jsonEncode(response)) as Map<String, Object?>;
        expect(wire['error'], isNull, reason: '$shape');
      }
    });

    test('leaves input_required alone on an earlier revision', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('asks_to_elicit'),
        _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
      );

      expect(response![Keys.error], isNull);
      expect(_result(response)[Keys.inputRequests], isNotEmpty);
    });

    test('shuts the server down after a dispatch', () async {
      final harness = _DispatcherHarness();
      await harness.dispatch(_callTool('probe'), _initialization());

      final server = harness.servers.single;
      await server.done;
      expect(server.isActive, isFalse);
    });

    test('returns an internal error when the server closes early', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(
        _callTool('shutdown'),
        _initialization(),
      );

      final error = response![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.INTERNAL_ERROR);
      expect(error[Keys.message], contains('closed before responding'));
    });

    test('surfaces initialization failures without unhandled errors', () async {
      final servers = <_FailingInitServer>[];
      await expectLater(
        handleRequestScopedMessage(_callTool('probe'), _initialization(), (
          channel,
        ) {
          final server = _FailingInitServer(channel);
          servers.add(server);
          return server;
        }),
        throwsStateError,
      );
      await servers.single.done;
    });

    test('responds with method not found for unknown methods', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch({
        Keys.jsonrpc: '2.0',
        Keys.id: 1,
        Keys.method: 'no/such_method',
      }, _initialization());

      final error = response![Keys.error] as Map<String, Object?>;
      expect(error[Keys.code], error_code.METHOD_NOT_FOUND);
      expect(
        response.containsKey(Keys.result),
        isFalse,
        reason: 'error responses get no result and no server info',
      );
    });

    test('throws for messages without a string method', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({Keys.jsonrpc: '2.0', Keys.id: 1}, _initialization()),
        throwsArgumentError,
      );
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: 42,
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test('throws for response-shaped messages', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: ListToolsRequest.methodName,
          Keys.result: <String, Object?>{},
        }, _initialization()),
        throwsArgumentError,
      );
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: ListToolsRequest.methodName,
          Keys.error: <String, Object?>{Keys.code: 0, Keys.message: 'x'},
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test('throws for legacy lifecycle messages', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: 1,
          Keys.method: InitializeRequest.methodName,
        }, _initialization()),
        throwsArgumentError,
      );
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.method: InitializedNotification.methodName,
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test('returns null for notifications', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch({
        Keys.jsonrpc: '2.0',
        Keys.method: _DispatcherTestServer.testNotification,
      }, _initialization());

      expect(response, isNull);
      expect(harness.servers.single.testNotifications, 1);
    });

    test('throws for a message with a null id', () async {
      final harness = _DispatcherHarness();
      await expectLater(
        harness.dispatch({
          Keys.jsonrpc: '2.0',
          Keys.id: null,
          Keys.method: ListToolsRequest.methodName,
        }, _initialization()),
        throwsArgumentError,
      );
      expect(harness.servers, isEmpty);
    });

    test(
      'reports a throwing onNotification without failing the request',
      () async {
        final harness = _DispatcherHarness();
        final callbackErrors = <Object>[];
        Map<String, Object?>? response;
        await runZonedGuarded(() async {
          response = await harness.dispatch(
            _callTool('notify'),
            _initialization(),
            onNotification: (_) => throw StateError('bad callback'),
          );
        }, (error, _) => callbackErrors.add(error));

        expect(_result(response), isNotEmpty);
        expect(callbackErrors, isNotEmpty);
      },
    );

    test('isolates concurrent dispatches', () async {
      final harness = _DispatcherHarness();
      final responses = await Future.wait([
        harness.dispatch(
          _callTool('slow_echo', arguments: {'message': 'first'}),
          _initialization(
            capabilities: ClientCapabilities(roots: RootsCapabilities()),
          ),
        ),
        harness.dispatch(
          _callTool('slow_echo', arguments: {'message': 'second'}),
          _initialization(),
        ),
      ]);

      final texts = [
        for (final response in responses)
          (CallToolResult.fromMap(_result(response)).content.single
                  as TextContent)
              .text,
      ];
      expect(texts, ['first', 'second']);
      expect(harness.servers, hasLength(2));
      expect(harness.servers[0].clientCapabilities.roots, isNotNull);
      expect(harness.servers[1].clientCapabilities.roots, isNull);
    });

    test('degrades gracefully with roots tracking mixed in', () async {
      final servers = <_RootsTrackingDispatcherServer>[];
      final response = await handleRequestScopedMessage(
        _listTools(),
        _initialization(
          capabilities: ClientCapabilities(roots: RootsCapabilities()),
        ),
        (channel) {
          final server = _RootsTrackingDispatcherServer(channel);
          servers.add(server);
          return server;
        },
      );

      final tools = ListToolsResult.fromMap(_result(response));
      expect(tools.tools, isEmpty);
      await servers.single.done;
    });

    test(
      'survives a notification which triggers a server to client request',
      () async {
        // The immediate teardown after a notification races the listRoots
        // request that roots tracking issues on initialization.
        final response = await handleRequestScopedMessage(
          {
            Keys.jsonrpc: '2.0',
            Keys.method: _DispatcherTestServer.testNotification,
          },
          _initialization(
            capabilities: ClientCapabilities(roots: RootsCapabilities()),
          ),
          _RootsTrackingDispatcherServer.new,
        );

        expect(response, isNull);
      },
    );
  });

  group('server/discover', () {
    test('answers with the fields the schema requires', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_discover(), _initialization());

      final result = _result(response);
      // The schema makes all five of these required on a `DiscoverResult`.
      // The handler answers the first two and the dispatcher stamps the rest.
      expect(result, contains(Keys.supportedVersions));
      expect(result, contains(Keys.capabilities));
      expect(result, containsPair(Keys.resultType, ResultTypes.complete));
      expect(result, containsPair(Keys.ttlMs, 0));
      expect(result, containsPair(Keys.cacheScope, 'private'));
    });

    test('advertises only the request-scoped revisions', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_discover(), _initialization());

      expect(DiscoverResult.fromMap(_result(response)).supportedVersions, [
        ProtocolVersion.v2026_07_28.versionString,
      ], reason: 'earlier revisions negotiate with the initialize handshake');
    });

    test('advertises the capabilities initialization registered', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_discover(), _initialization());

      final capabilities =
          DiscoverResult.fromMap(_result(response)).capabilities;
      expect(capabilities.tools, isNotNull);
      expect(
        capabilities.tools?.listChanged,
        isNull,
        reason:
            'list changes reach a client on a `subscriptions/listen` '
            'stream, which this package does not serve yet',
      );
      expect(capabilities.resources?.listChanged, isNull);
      expect(
        capabilities.resources?.subscribe,
        isNull,
        reason:
            'resource updates reach a client through the '
            '`resourceSubscriptions` filter on the same stream',
      );
      expect(capabilities.logging, isNotNull);
      expect(capabilities.completions, isNotNull);
      expect(
        capabilities.extensions,
        isNotNull,
        reason:
            'capabilities are an open set, so anything the server put on '
            'the field has to survive the trip',
      );
      expect(
        capabilities.prompts,
        isNull,
        reason: 'this server registers no prompts, so it must not claim them',
      );
    });

    test('keeps the capability fields it was not asked to drop', () async {
      final response = await handleRequestScopedMessage(
        _discover(),
        _initialization(),
        _ExtraResourceFieldServer.new,
      );

      final resources =
          DiscoverResult.fromMap(_result(response)).capabilities.resources;
      expect(resources?.listChanged, isNull);
      expect(resources?.subscribe, isNull);
      expect(
        resources! as Map<String, Object?>,
        containsPair(_ExtraResourceFieldServer.unknownField, true),
        reason:
            'only the bits this package cannot honor come off, so a field '
            'a later revision adds still reaches the client',
      );
    });

    test('carries the instructions the server was given', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_discover(), _initialization());

      expect(
        DiscoverResult.fromMap(_result(response)).instructions,
        'A test server',
      );
    });

    test('identifies the server in the result metadata', () async {
      final harness = _DispatcherHarness();
      final response = await harness.dispatch(_discover(), _initialization());

      final meta = _result(response)[Keys.meta] as Map<String, Object?>;
      final serverInfo = Implementation.fromMap(
        meta[Keys.serverInfoMeta] as Map<String, Object?>,
      );
      expect(serverInfo.name, 'test server');
    });

    test(
      'is not served on a revision that negotiates with initialize',
      () async {
        final harness = _DispatcherHarness();
        final response = await harness.dispatch(
          _discover(),
          _initialization(protocolVersion: ProtocolVersion.v2025_11_25),
        );

        final error = response![Keys.error] as Map<String, Object?>;
        expect(
          error[Keys.code],
          error_code.METHOD_NOT_FOUND,
          reason:
              'on an earlier revision the client negotiates with the '
              'initialize handshake instead',
        );
      },
    );
  });

  group('legacy lifecycle', () {
    test('handshake still provides client info', () async {
      final environment = TestEnvironment(
        TestMCPClient(),
        _DispatcherTestServer.new,
      );
      await environment.initializeServer();

      expect(
        environment.server.clientInfo?.name,
        environment.client.implementation.name,
      );
    });

    test('does not answer a discovery probe', () async {
      final environment = TestEnvironment(
        TestMCPClient(),
        _DispatcherTestServer.new,
      );
      await environment.initializeServer();

      // A client that speaks both eras probes with `server/discover` first,
      // and an answer would tell it this connection is modern.
      await expectLater(
        environment.serverConnection.sendRequest(
          DiscoverRequest.methodName,
          DiscoverRequest(),
        ),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            error_code.METHOD_NOT_FOUND,
          ),
        ),
      );
    });
  });
}

/// Dispatches messages over [_DispatcherTestServer]s and records the servers
/// it creates.
final class _DispatcherHarness {
  _DispatcherHarness({this.pickedLogLevel});

  /// A level the server sets on itself before `initialize` runs, the way a
  /// server that wants its own default does.
  final LoggingLevel? pickedLogLevel;

  final servers = <_DispatcherTestServer>[];

  Future<Map<String, Object?>?> dispatch(
    Map<String, Object?> message,
    MCPServerInitialization initialization, {
    void Function(Map<String, Object?> notification)? onNotification,
  }) => handleRequestScopedMessage(message, initialization, (channel) {
    final server = _DispatcherTestServer(channel);
    if (pickedLogLevel != null) server.loggingLevel = pickedLogLevel;
    servers.add(server);
    return server;
  }, onNotification: onNotification);
}

/// A server with tools which observe the request-scoped lifecycle.
final class _DispatcherTestServer extends TestMCPServer
    with CompletionsSupport, LoggingSupport, ResourcesSupport, ToolsSupport {
  static const testNotification = 'notifications/test';

  _DispatcherTestServer(super.channel);

  @override
  CompleteResult handleComplete(CompleteRequest request) =>
      request.argument.name == 'input_required'
          ? CompleteResult.fromMap({
            Keys.completion: Completion(values: const []),
            Keys.resultType: ResultTypes.inputRequired,
          })
          : CompleteResult(completion: Completion(values: const []));

  /// How many [testNotification] notifications this server received.
  int testNotifications = 0;

  /// The result map the `retained` tool returned, to assert that server info
  /// stamping does not write into it.
  Map<String, Object?>? retainedResult;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    capabilities.extensions = const {'io.example/dispatcher': true};
    registerNotificationHandler(testNotification, (Notification? _) {
      testNotifications++;
    });
    registerTool(
      Tool(name: 'probe', inputSchema: ObjectSchema()),
      (_) => CallToolResult(content: [TextContent(text: 'ready: $ready')]),
    );
    registerTool(
      Tool(name: 'custom_info', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'custom')],
        Keys.meta: {
          Keys.serverInfoMeta: Implementation(
            name: 'already there',
            version: '1.0.0',
          ),
        },
      }),
    );
    addResource(
      Resource(uri: 'file:///probe', name: 'probe'),
      (_) async => ReadResourceResult(
        contents: [TextResourceContents(uri: 'file:///probe', text: 'probe')],
      ),
    );
    registerTool(
      Tool(name: 'interim', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'waiting')],
        Keys.resultType: ResultTypes.inputRequired,
        Keys.requestState: 'waiting',
      }),
    );
    for (final entry
        in {
          'asks_to_elicit': InputRequest.elicit(
            ElicitRequest.form(
              message: 'What is your name?',
              requestedSchema: ObjectSchema(
                properties: {'name': StringSchema()},
              ),
            ),
          ),
          'asks_to_sample': InputRequest.sample(
            CreateMessageRequest(messages: [], maxTokens: 1),
          ),
          'asks_for_roots': InputRequest.listRoots(ListRootsRequest()),
        }.entries) {
      registerTool(
        Tool(name: entry.key, inputSchema: ObjectSchema()),
        (_) => CallToolResult.fromMap({
          Keys.content: [TextContent(text: 'waiting')],
          Keys.resultType: ResultTypes.inputRequired,
          Keys.inputRequests: {'answer': entry.value},
        }),
      );
    }
    registerTool(
      Tool(name: 'asks_to_elicit_by_url', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'waiting')],
        Keys.resultType: ResultTypes.inputRequired,
        Keys.inputRequests: {
          'answer': InputRequest.elicit(
            ElicitRequest.url(
              message: 'Sign in',
              url: 'https://example.com/sign-in',
              elicitationId: 'e1',
            ),
          ),
        },
      }),
    );
    // Registered directly instead of mixing in `PromptsSupport`: the guard
    // dispatches on the method, and the mixin would also change what this
    // server advertises, which other tests here assert on.
    registerRequestHandler<GetPromptRequest, GetPromptResult>(
      GetPromptRequest.methodName,
      (_) => GetPromptResult.fromMap({
        Keys.messages: <Object?>[],
        Keys.resultType: ResultTypes.inputRequired,
        Keys.requestState: 'waiting',
      }),
    );
    registerTool(
      Tool(name: 'bad_meta', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'bad')],
        Keys.meta: 'not a map',
      }),
    );
    registerTool(
      Tool(name: 'bad_meta_keys', inputSchema: ObjectSchema()),
      (_) => CallToolResult.fromMap({
        Keys.content: [TextContent(text: 'bad')],
        Keys.meta: {1: 'kept'},
      }),
    );
    registerTool(Tool(name: 'retained', inputSchema: ObjectSchema()), (_) {
      retainedResult = {
        Keys.content: [TextContent(text: 'kept')],
      };
      return CallToolResult.fromMap(retainedResult!);
    });
    registerTool(Tool(name: 'notify', inputSchema: ObjectSchema()), (_) {
      notifyProgress(
        ProgressNotification(progressToken: ProgressToken(1), progress: 50),
      );
      log(LoggingLevel.error, 'from the handler');
      return CallToolResult(content: [TextContent(text: 'notified')]);
    });
    registerTool(Tool(name: 'roots', inputSchema: ObjectSchema()), (_) async {
      final roots = await listRoots(ListRootsRequest());
      return CallToolResult(content: [TextContent(text: '$roots')]);
    });
    registerTool(Tool(name: 'shutdown', inputSchema: ObjectSchema()), (
      _,
    ) async {
      await shutdown();
      return CallToolResult(content: [TextContent(text: 'unreachable')]);
    });
    registerTool(Tool(name: 'slow_echo', inputSchema: ObjectSchema()), (
      request,
    ) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return CallToolResult(
        content: [TextContent(text: request.arguments!['message'] as String)],
      );
    });
    return super.initialize(initialization);
  }
}

/// A server which tracks roots, to exercise a server to client request made
/// during initialization rather than from a handler.
final class _RootsTrackingDispatcherServer extends TestMCPServer
    with LoggingSupport, RootsTrackingSupport, ToolsSupport {
  _RootsTrackingDispatcherServer(super.channel);
}

/// A server carrying a `resources` capability field this package does not
/// know, standing in for one a later revision adds.
final class _ExtraResourceFieldServer extends TestMCPServer
    with ResourcesSupport {
  static const unknownField = 'io.example/unknownResourceField';

  _ExtraResourceFieldServer(super.channel);

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) async {
    await super.initialize(initialization);
    (capabilities.resources! as Map<String, Object?>)[unknownField] = true;
  }
}

/// A server whose initialization always fails.
final class _FailingInitServer extends TestMCPServer {
  _FailingInitServer(super.channel);

  @override
  // A server which fails to initialize cannot call super first.
  // ignore: must_call_super
  FutureOr<void> initialize(MCPServerInitialization initialization) =>
      throw StateError('initialization failed');
}

/// A server whose `resources/read` answers with whatever [shape] returns.
final class _ShapedReadServer extends TestMCPServer with ResourcesSupport {
  _ShapedReadServer(super.channel, this.shape);

  final Map<String, Object?> Function(Map<String, Object?> result) shape;

  @override
  FutureOr<void> initialize(MCPServerInitialization initialization) {
    addResource(
      Resource(uri: 'file:///probe', name: 'probe'),
      (_) async => ReadResourceResult(contents: []),
    );
    return super.initialize(initialization);
  }

  @override
  Future<ReadResourceResult> readResource(ReadResourceRequest request) async =>
      ReadResourceResult.fromMap(
        shape(await super.readResource(request) as Map<String, Object?>),
      );
}

/// A server whose `tools/list` answers with whatever [shape] returns.
final class _ShapedListServer extends TestMCPServer with ToolsSupport {
  _ShapedListServer(super.channel, this.shape);

  final Map<String, Object?> Function(Map<String, Object?> result) shape;

  @override
  Future<ListToolsResult> listTools([ListToolsRequest? request]) async =>
      ListToolsResult.fromMap(
        shape(await super.listTools(request) as Map<String, Object?>),
      );
}

Map<String, Object?> _complete(String argumentName) => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: CompleteRequest.methodName,
  Keys.params: CompleteRequest(
    ref: ResourceTemplateReference(uri: 'file:///{name}'),
    argument: CompletionArgument(name: argumentName, value: ''),
  ),
};

Map<String, Object?> _getPrompt(String name) => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: GetPromptRequest.methodName,
  Keys.params: {Keys.name: name},
};

Map<String, Object?> _callTool(
  String name, {
  Map<String, Object?> arguments = const {},
}) => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: CallToolRequest.methodName,
  Keys.params: {Keys.name: name, Keys.arguments: arguments},
};

Map<String, Object?> _readResource() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: ReadResourceRequest.methodName,
  Keys.params: {Keys.uri: 'file:///probe'},
};

Map<String, Object?> _listTools() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: ListToolsRequest.methodName,
};

Map<String, Object?> _ping() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: PingRequest.methodName,
};

Map<String, Object?> _setLevel() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: SetLevelRequest.methodName,
  Keys.params: {Keys.level: LoggingLevel.debug.name},
};

Map<String, Object?> _discover() => {
  Keys.jsonrpc: '2.0',
  Keys.id: 1,
  Keys.method: DiscoverRequest.methodName,
};

/// The request-scoped lifecycle arrived with 2026-07-28, so that is the
/// revision these dispatch, unless a test says otherwise.
MCPServerInitialization _initialization({
  ClientCapabilities? capabilities,
  ProtocolVersion protocolVersion = ProtocolVersion.v2026_07_28,
  LoggingLevel? logLevel,
}) => MCPServerInitialization(
  protocolVersion: protocolVersion,
  clientCapabilities: capabilities ?? ClientCapabilities(),
  logLevel: logLevel,
);

Map<String, Object?> _result(Map<String, Object?>? response) =>
    response![Keys.result] as Map<String, Object?>;

/// Dispatches a `resources/read` to a server whose result is passed through
/// [shape] first, so a test can say what the handler itself already set.
Future<Map<String, Object?>?> _dispatchShapedRead(
  Map<String, Object?> Function(Map<String, Object?> result) shape, {
  ClientCapabilities? capabilities,
}) => handleRequestScopedMessage(
  _readResource(),
  _initialization(capabilities: capabilities),
  (channel) => _ShapedReadServer(channel, shape),
);

/// Dispatches a `tools/list` to a server whose result is passed through
/// [shape] first, so a test can say what the handler itself already set.
Future<Map<String, Object?>?> _dispatchShapedList(
  Map<String, Object?> Function(Map<String, Object?> result) shape,
) => handleRequestScopedMessage(
  _listTools(),
  _initialization(),
  (channel) => _ShapedListServer(channel, shape),
);
