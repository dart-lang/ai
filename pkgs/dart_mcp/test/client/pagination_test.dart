// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  late _PagingServer server;
  late ServerConnection connection;

  setUp(() async {
    final environment = TestEnvironment(
      TestMCPClient(),
      (channel) => server = _PagingServer(channel),
    );
    connection = environment.serverConnection;
    await environment.initializeServer();
  });

  test('listAllTools walks two pages then ends', () async {
    server.pages = [
      ['a', 'b'],
      ['c'],
    ];

    expect(await connection.listAllTools().map((tool) => tool.name).toList(), [
      'a',
      'b',
      'c',
    ]);
    expect(server.cursors, [null, _PagingServer.cursorFor(1)]);
  });

  test('listAllPrompts walks two pages then ends', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];

    expect(
      await connection.listAllPrompts().map((prompt) => prompt.name).toList(),
      ['a', 'b'],
    );
    expect(server.cursors, [null, _PagingServer.cursorFor(1)]);
  });

  test('listAllResources walks two pages then ends', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];

    expect(
      await connection
          .listAllResources()
          .map((resource) => resource.name)
          .toList(),
      ['a', 'b'],
    );
    expect(server.cursors, [null, _PagingServer.cursorFor(1)]);
  });

  test('listAllResourceTemplates walks two pages then ends', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];

    expect(
      await connection
          .listAllResourceTemplates()
          .map((template) => template.name)
          .toList(),
      ['a', 'b'],
    );
    expect(server.cursors, [null, _PagingServer.cursorFor(1)]);
  });

  test('an empty first page ends the walk', () async {
    server.pages = [[]];

    expect(await connection.listAllTools().toList(), isEmpty);
    expect(server.cursors, [null]);
  });

  test('an empty page in the middle does not end the walk', () async {
    server.pages = [
      ['a'],
      [],
      ['b'],
    ];

    expect(await connection.listAllTools().map((tool) => tool.name).toList(), [
      'a',
      'b',
    ]);
    expect(server.cursors, [
      null,
      _PagingServer.cursorFor(1),
      _PagingServer.cursorFor(2),
    ]);
  });

  test('an empty string nextCursor is a cursor, not the end', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];
    server.emptyCursor = true;

    expect(await connection.listAllTools().map((tool) => tool.name).toList(), [
      'a',
      'b',
    ]);
    expect(server.cursors, [null, Cursor('')]);
  });

  test('an invalid cursor on a later page propagates', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];
    server.invalidCursor = _PagingServer.cursorFor(1);

    await expectLater(
      connection.listAllTools().toList(),
      throwsA(
        isA<RpcException>().having(
          (error) => error.code,
          'code',
          error_code.INVALID_PARAMS,
        ),
      ),
    );
    expect(server.cursors, [null, _PagingServer.cursorFor(1)]);
  });

  test('the first page yields before the second page is requested', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];

    final first = await connection.listAllTools().first;

    expect(first.name, 'a');
    expect(server.cursors, [null]);
  });

  test('a request cursor starts the walk at that page', () async {
    server.pages = [
      ['a'],
      ['b'],
      ['c'],
    ];

    expect(
      await connection
          .listAllTools(
            request: ListToolsRequest(cursor: _PagingServer.cursorFor(1)),
          )
          .map((tool) => tool.name)
          .toList(),
      ['b', 'c'],
    );
    expect(server.cursors, [
      _PagingServer.cursorFor(1),
      _PagingServer.cursorFor(2),
    ]);
  });

  test('maxPageCount stops a walk the server never ends', () async {
    server.pages = [
      ['a'],
    ];
    server.repeatCursor = true;

    await expectLater(
      connection.listAllTools(maxPageCount: 3).toList(),
      throwsA(isA<StateError>()),
    );
    expect(server.cursors, [
      null,
      _PagingServer.cursorFor(0),
      _PagingServer.cursorFor(0),
    ]);
  });

  test('maxPageCount stops a server that alternates two cursors', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];
    server.alternateCursors = true;

    await expectLater(
      connection.listAllTools(maxPageCount: 4).toList(),
      throwsA(isA<StateError>()),
    );
    expect(server.cursors, [
      null,
      _PagingServer.cursorFor(1),
      _PagingServer.cursorFor(0),
      _PagingServer.cursorFor(1),
    ]);
  });

  test('a maxPageCount under one is rejected before any request', () {
    server.pages = [
      ['a'],
    ];

    expect(() => connection.listAllTools(maxPageCount: 0), throwsArgumentError);
    expect(
      () => connection.listAllTools(maxPageCount: -5),
      throwsArgumentError,
    );
    expect(server.cursors, isEmpty);
  });

  test('maxPageCount equal to the page count completes', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];

    expect(
      await connection
          .listAllTools(maxPageCount: 2)
          .map((tool) => tool.name)
          .toList(),
      ['a', 'b'],
    );
    expect(server.cursors, [null, _PagingServer.cursorFor(1)]);
  });

  test('maxPageCount stops listAllPrompts too', () async {
    server.pages = [
      ['a'],
    ];
    server.repeatCursor = true;

    await expectLater(
      connection.listAllPrompts(maxPageCount: 2).toList(),
      throwsA(isA<StateError>()),
    );
    expect(server.cursors, [null, _PagingServer.cursorFor(0)]);
  });

  test('the default bound stops a walk the server never ends', () async {
    server.pages = [
      ['a'],
    ];
    server.repeatCursor = true;

    await expectLater(
      connection.listAllTools().toList(),
      throwsA(isA<StateError>()),
    );
    expect(server.cursors, hasLength(64));
  });

  test('every page carries the progress token and it closes once', () async {
    server.pages = [
      ['a'],
      ['b'],
    ];
    server.sendProgress = true;
    final request = ListToolsRequest(
      meta: MetaWithProgressToken(progressToken: ProgressToken('token')),
    );
    final progress = <num>[];
    var streamClosed = false;
    connection
        .onProgress(request)
        .listen(
          (notification) => progress.add(notification.progress),
          onDone: () => streamClosed = true,
        );

    expect(
      await connection
          .listAllTools(request: request)
          .map((tool) => tool.name)
          .toList(),
      ['a', 'b'],
    );
    await pumpEventQueue();

    expect(progress, [1, 2]);
    expect(streamClosed, isTrue);
  });
}

/// A server whose four list methods answer from [pages], one page per entry.
final class _PagingServer extends TestMCPServer {
  _PagingServer(super.channel) {
    registerRequestHandler<ListToolsRequest?, ListToolsResult>(
      ListToolsRequest.methodName,
      (request) => ListToolsResult(
        tools: [
          for (final name in _page(request))
            Tool(name: name, inputSchema: ObjectSchema()),
        ],
        nextCursor: _nextCursor(request?.cursor),
      ),
    );
    registerRequestHandler<ListPromptsRequest?, ListPromptsResult>(
      ListPromptsRequest.methodName,
      (request) => ListPromptsResult(
        prompts: [for (final name in _page(request)) Prompt(name: name)],
        nextCursor: _nextCursor(request?.cursor),
      ),
    );
    registerRequestHandler<ListResourcesRequest?, ListResourcesResult>(
      ListResourcesRequest.methodName,
      (request) => ListResourcesResult(
        resources: [
          for (final name in _page(request))
            Resource(uri: 'test://$name', name: name),
        ],
        nextCursor: _nextCursor(request?.cursor),
      ),
    );
    registerRequestHandler<
      ListResourceTemplatesRequest?,
      ListResourceTemplatesResult
    >(
      ListResourceTemplatesRequest.methodName,
      (request) => ListResourceTemplatesResult(
        resourceTemplates: [
          for (final name in _page(request))
            ResourceTemplate(uriTemplate: 'test://$name/{id}', name: name),
        ],
        nextCursor: _nextCursor(request?.cursor),
      ),
    );
  }

  /// The prefix of every [Cursor] this server hands out.
  static const cursorPrefix = 'page-';

  /// The [Cursor] naming the page at [index].
  static Cursor cursorFor(int index) => Cursor('$cursorPrefix$index');

  /// The item names of each page, in order.
  List<List<String>> pages = const [];

  /// The cursor of every list request this server answered, in order.
  final cursors = <Cursor?>[];

  /// A cursor this server rejects as no longer valid.
  Cursor? invalidCursor;

  /// Whether every page reports the cursor it was given as its next one.
  bool repeatCursor = false;

  /// Whether pages alternate between the first two cursors and never end.
  bool alternateCursors = false;

  /// Whether the first page reports an empty string as its next cursor.
  bool emptyCursor = false;

  /// Whether every page sends a progress notification for the request's token.
  bool sendProgress = false;

  /// The names on the page [request] asks for, recording its cursor.
  List<String> _page(PaginatedRequest? request) {
    final cursor = request?.cursor;
    cursors.add(cursor);
    if (invalidCursor != null && cursor == invalidCursor) {
      throw RpcException(
        error_code.INVALID_PARAMS,
        'The cursor "$cursor" is no longer valid.',
      );
    }
    if (sendProgress) {
      final token = request?.meta?.progressToken;
      if (token != null) {
        notifyProgress(
          ProgressNotification(progressToken: token, progress: cursors.length),
        );
      }
    }
    return pages[_indexOf(cursor)];
  }

  /// The cursor of the page after the one [cursor] names, if there is one.
  Cursor? _nextCursor(Cursor? cursor) {
    if (repeatCursor) return cursor ?? cursorFor(0);
    if (alternateCursors) {
      return _indexOf(cursor) == 0 ? cursorFor(1) : cursorFor(0);
    }
    final next = _indexOf(cursor) + 1;
    if (emptyCursor && next == 1) return Cursor('');
    return next < pages.length ? cursorFor(next) : null;
  }

  /// The index into [pages] that [cursor] names, where the empty cursor
  /// [emptyCursor] hands out names the second page.
  int _indexOf(Cursor? cursor) {
    if (cursor == null) return 0;
    final value = cursor as String;
    if (value.isEmpty) return 1;
    return int.parse(value.substring(cursorPrefix.length));
  }
}
