// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:checks/checks.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('client can read resources from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithResources.new,
    );
    final initializeResult = await environment.initializeServer();

    check(
      initializeResult.capabilities.resources as Map<String, Object?>,
    ).deepEquals(
      Resources(listChanged: true, subscribe: true) as Map<String, Object?>,
    );

    final serverConnection = environment.serverConnection;

    final resourcesResult = await serverConnection.listResources();
    check(resourcesResult.resources).has((r) => r.length, 'length').equals(1);

    final resource = resourcesResult.resources.single;

    final result = await serverConnection.readResource(
      ReadResourceRequest(uri: resource.uri),
    );
    final contents = result.contents.single;
    check(contents.isText).isTrue();
    check((contents as TextResourceContents).text).equals('hello world!');
  });

  test('client can subscribe to resource updates from the server', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithResources.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    final resourceListChangedQueue = StreamQueue(
      serverConnection.resourceListChanged,
    );

    final fooResource = Resource(name: 'foo', uri: 'foo://bar');
    var fooContents = 'bar';
    server.addResource(
      fooResource,
      (_) => ReadResourceResult(
        contents: [
          TextResourceContents(uri: fooResource.uri, text: fooContents),
        ],
      ),
    );

    await resourceListChangedQueue.next;
    final resources = await serverConnection.listResources(
      ListResourcesRequest(),
    );
    check(resources.resources as List<Object?>).unorderedMatches([
      (it) => it.isA<Map<String, Object?>>().deepEquals(
        fooResource as Map<String, Object?>,
      ),
      (it) => it.isA<Map<String, Object?>>().deepEquals(
        TestMCPServerWithResources.helloWorld as Map<String, Object?>,
      ),
    ]);

    final resourceChangedQueue = StreamQueue(serverConnection.resourceUpdated);
    await serverConnection.subscribeResource(
      SubscribeRequest(uri: fooResource.uri),
    );

    fooContents = 'baz';
    server.updateResource(fooResource);

    check(await resourceChangedQueue.next)
        .isA<ResourceUpdatedNotification>()
        .has((n) => n.uri, 'uri')
        .equals(fooResource.uri);

    final readResult = await serverConnection.readResource(
      ReadResourceRequest(uri: fooResource.uri),
    );
    check(readResult.contents.single).isA<TextResourceContents>()
      ..has((c) => c.text, 'text').equals('baz')
      ..has((c) => c.uri, 'uri').equals(fooResource.uri);

    await serverConnection.unsubscribeResource(
      UnsubscribeRequest(uri: fooResource.uri),
    );

    fooContents = 'zap';
    server.updateResource(fooResource);

    final resourceChangedHasNext = check(
      resourceChangedQueue.hasNext,
    ).completes((it) => it.isFalse());

    server.removeResource(fooResource.uri);

    check(
      await resourceListChangedQueue.next as Map<String, Object?>,
    ).deepEquals(ResourceListChangedNotification() as Map<String, Object?>);

    server.sendNotification(ResourceListChangedNotification.methodName);
    check(await resourceListChangedQueue.next).isNull();

    final resourceListChangedHasNext = check(
      resourceListChangedQueue.hasNext,
    ).completes((it) => it.isFalse());

    /// We need to manually shut down to so that the `hasNext` futures can
    /// complete.
    await environment.shutdown();

    await resourceChangedHasNext;
    await resourceListChangedHasNext;
  });

  test('resource change notifications are throttled', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithResources.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;
    final server = environment.server;

    final resourceListChangedQueue = StreamQueue(
      serverConnection.resourceListChanged,
    );

    final resources = [
      for (var i = 0; i < 5; i++) Resource(name: '$i', uri: 'foo://$i'),
    ];
    for (var resource in resources) {
      server.addResource(
        resource,
        (_) => ReadResourceResult(
          contents: [
            TextResourceContents(uri: resource.uri, text: resource.name),
          ],
        ),
      );
    }

    // Should get exactly two notifications even though we have more resources,
    // one initial notification and one after the throttle delay.
    await resourceListChangedQueue.take(2);
    final resourceListChangedHasNext = check(
      resourceListChangedQueue.hasNext,
    ).completes((it) => it.isFalse());
    await pumpEventQueue();

    final resourceChangedQueue = StreamQueue(serverConnection.resourceUpdated);
    final resource = resources.first;
    await serverConnection.subscribeResource(
      SubscribeRequest(uri: resource.uri),
    );
    // Allow the subscription to propagate.
    await pumpEventQueue();

    // Send 5 notifications back to back.
    for (var i = 0; i < 5; i++) {
      server.updateResource(resource);
    }

    // Only two should make it through, one at the start and one after the
    // timeout.
    for (var i = 0; i < 2; i++) {
      check(await resourceChangedQueue.next)
          .isA<ResourceUpdatedNotification>()
          .has((n) => n.uri, 'uri')
          .equals(resource.uri);
    }
    final resourceChangedHasNext = check(
      resourceChangedQueue.hasNext,
    ).completes((it) => it.isFalse());
    await pumpEventQueue();

    await environment.shutdown();

    await resourceListChangedHasNext;
    await resourceChangedHasNext;
  });

  test(
    'Resource templates can be listed, queried, and subscribed to',
    () async {
      final environment = TestEnvironment(
        TestMCPClient(),
        (channel) => TestMCPServerWithResources(
          channel,
          fileContents: {'package:foo/foo.dart': 'hello world!'},
        ),
      );
      await environment.initializeServer();

      final serverConnection = environment.serverConnection;

      final templatesResponse = await serverConnection.listResourceTemplates();

      check(
        templatesResponse.resourceTemplates.single as Map<String, Object?>,
      ).deepEquals(
        TestMCPServerWithResources.packageUriTemplate as Map<String, Object?>,
      );

      final readResourceResponse = await serverConnection.readResource(
        ReadResourceRequest(uri: 'package:foo/foo.dart'),
      );
      check(
        (readResourceResponse.contents.single as TextResourceContents).text,
      ).equals('hello world!');
    },
  );
}

final class TestMCPServerWithResources extends TestMCPServer
    with ResourcesSupport {
  final Map<String, String> fileContents;

  @override
  /// Shorten this delay for the test so they run quickly.
  Duration get resourceUpdateThrottleDelay => Duration.zero;

  TestMCPServerWithResources(super.channel, {this.fileContents = const {}});

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    addResource(
      helloWorld,
      (_) => ReadResourceResult(
        contents: [
          TextResourceContents(text: 'hello world!', uri: helloWorld.uri),
        ],
      ),
    );
    addResourceTemplate(packageUriTemplate, _readPackageResource);
    return super.initialize(request);
  }

  Future<ReadResourceResult?> _readPackageResource(
    ReadResourceRequest request,
  ) async {
    if (!request.uri.startsWith('package:')) return null;
    if (!request.uri.endsWith('.dart')) {
      throw UnsupportedError('Only dart files can be read');
    }

    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: request.uri,
          text: fileContents[request.uri]!,
        ),
      ],
    );
  }

  static final helloWorld = Resource(name: 'hello world', uri: 'hello://world');

  static final packageUriTemplate = ResourceTemplate(
    uriTemplate: 'package:{package}/{library}',
    name: 'Dart package resource',
  );
}
