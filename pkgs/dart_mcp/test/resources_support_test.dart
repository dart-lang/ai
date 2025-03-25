// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('client and server can communicate', () async {
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
}

class TestMCPServerWithResources extends TestMCPServer with ResourcesSupport {
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
