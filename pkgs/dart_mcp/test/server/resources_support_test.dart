// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:async/async.dart';
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
    expect(resourceListChangedQueue.hasNext, completion(false));
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
      expect(
        await resourceChangedQueue.next,
        isA<ResourceUpdatedNotification>().having(
          (n) => n.uri,
          'uri',
          resource.uri,
        ),
      );
    }
    expect(resourceChangedQueue.hasNext, completion(false));
    await pumpEventQueue();

    await environment.shutdown();
  });

  test('Resource templates can be listed and queried', () async {
    final environment = TestEnvironment(
      TestMCPClient(),
      TestMCPServerWithResources.new,
    );
    await environment.initializeServer();

    final serverConnection = environment.serverConnection;

    final templatesResponse = await serverConnection.listResourceTemplates(
      ListResourceTemplatesRequest(),
    );

    expect(
      templatesResponse.resourceTemplates.single,
      TestMCPServerWithResources.packageUriTemplate,
    );

    final readResourceResponse = await serverConnection.readResource(
      ReadResourceRequest(uri: 'package:test/test.dart'),
    );
    expect(
      (readResourceResponse.contents.single as TextResourceContents).text,
      await File.fromUri(
        (await Isolate.resolvePackageUri(Uri.parse('package:test/test.dart')))!,
      ).readAsString(),
    );
  });
}

final class TestMCPServerWithResources extends TestMCPServer
    with ResourcesSupport {
  @override
  /// Shorten this delay for the test so they run quickly.
  Duration get resourceUpdateThrottleDelay => Duration.zero;

  TestMCPServerWithResources(super.channel);

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
    final resolvedUri =
        (await Isolate.resolvePackageUri(Uri.parse(request.uri)))!;

    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: request.uri,
          text: await File.fromUri(resolvedUri).readAsString(),
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
