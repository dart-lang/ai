// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A server that implements the resources API using the [ResourcesSupport]
/// mixin.
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

void main() {
  // Create the server and connect it to stdio.
  MCPServerWithResources(stdioChannel(input: io.stdin, output: io.stdout));
}

/// An MCP server with resource and resource template support.
///
/// This server uses the [ResourcesSupport] mixin to provide resources to the
/// client.
base class MCPServerWithResources extends MCPServer with ResourcesSupport {
  MCPServerWithResources(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'An example dart server with resources support',
          version: '0.1.0',
        ),
        instructions: 'Just list and read the resources :D',
      ) {
    // Add a standard resource with a fixed URI.
    addResource(
      Resource(uri: 'example://resource.txt', name: 'An example resource'),
      (request) => ReadResourceResult(
        contents: [TextResourceContents(text: 'Example!', uri: request.uri)],
      ),
    );

    // A resource template which always just returns the path portion of the
    // requested URI as the content of the resource.
    addResourceTemplate(
      ResourceTemplate(
        uriTemplate: 'example_template://{path}',
        name: 'Example resource template',
      ),
      (request) {
        // This template only handles resource URIs with this exact prefix,
        // returning null defers to the next resource template handler.
        if (!request.uri.startsWith('example_template://')) {
          return null;
        }
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              text: request.uri.substring('example_template://'.length),
              uri: request.uri,
            ),
          ],
        );
      },
    );
  }
}
