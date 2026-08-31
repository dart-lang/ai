// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../api/api.dart';
import 'constants.dart';

// Header field names are case insensitive, so these are used both to look
// headers up and to name them in error messages, in the casing the
// specification writes them in.
const protocolVersionHeader = 'MCP-Protocol-Version';
const mcpMethodHeader = 'Mcp-Method';
const mcpNameHeader = 'Mcp-Name';

/// The media type of the SSE response streams this protocol revision allows a
/// server to answer with.
const eventStreamMimeType = 'text/event-stream';

/// The methods whose `name` or `uri` parameter is mirrored in the `Mcp-Name`
/// header, mapping each method to the parameter that carries it.
const mcpNameParams = {
  CallToolRequest.methodName: Keys.name,
  GetPromptRequest.methodName: Keys.name,
  ReadResourceRequest.methodName: Keys.uri,
};

/// The prefix of the header a property's `x-mcp-header` annotation names, so
/// a property annotated `x-mcp-header: "Region"` is mirrored on
/// `Mcp-Param-Region`.
const mcpParamHeaderPrefix = 'Mcp-Param-';
