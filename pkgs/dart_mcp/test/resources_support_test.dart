// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client can read resources from the server', () async {
    var environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithResources.new,
    );
    final initializeResult = await environment.initializeServer();

    expect(
      initializeResult.capabilities.resources,
      equals(Resources(listChanged: true, subscribe: true)),
    );

    final serverConnection = environment.serverConnection;

    final resourcesResult = await serverConnection.listResources(
      ListResourcesRequest(),
    );
    expect(resourcesResult.resources.length, 1);

    final resource = resourcesResult.resources.single;

    final result = await serverConnection.readResource(
      ReadResourceRequest(uri: resource.uri),
    );
    expect(
      result.contents.single,
      isA<ResourceContents>()
          .having((c) => c.isText, 'isText', true)
          .having(
            (c) => (c as TextResourceContents).text,
            'text',
            'hello world!',
          ),
    );
  });

  test('client can subscribe to resource updates from the server', () async {
    var environment = TestEnvironment(
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
    expect(
      resources.resources,
      unorderedEquals([fooResource, TestMCPServerWithResources.helloWorld]),
    );

    final resourceChangedQueue = StreamQueue(serverConnection.resourceUpdated);
    await serverConnection.subscribeResource(
      SubscribeRequest(uri: fooResource.uri),
    );

    fooContents = 'baz';
    server.updateResource(fooResource);

    expect(
      await resourceChangedQueue.next,
      isA<ResourceUpdatedNotification>().having(
        (n) => n.uri,
        'uri',
        fooResource.uri,
      ),
    );

    expect(
      await serverConnection.readResource(
        ReadResourceRequest(uri: fooResource.uri),
      ),
      isA<ReadResourceResult>().having(
        (r) => r.contents.single,
        'contents',
        isA<TextResourceContents>()
            .having((c) => c.text, 'text', 'baz')
            .having((c) => c.uri, 'uri', fooResource.uri),
      ),
    );

    await serverConnection.unsubscribeResource(
      UnsubscribeRequest(uri: fooResource.uri),
    );

    fooContents = 'zap';
    server.updateResource(fooResource);

    expect(resourceChangedQueue.hasNext, completion(false));

    server.removeResource(fooResource.uri);

    expect(
      await resourceListChangedQueue.next,
      ResourceListChangedNotification(),
    );

    expect(resourceListChangedQueue.hasNext, completion(false));

    /// We need to manually shut down to so that the `hasNext` futures can
    /// complete.
    await environment.shutdown();
  });
}

final class TestMCPServerWithResources extends TestMCPServer
    with ResourcesSupport {
  TestMCPServerWithResources(super.channel) : super();

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
    return super.initialize(request);
  }

  static final helloWorld = Resource(name: 'hello world', uri: 'hello://world');
}
