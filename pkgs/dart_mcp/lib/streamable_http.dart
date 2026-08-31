// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The Streamable HTTP transport described by the 2026-07-28 revision of the
/// Model Context Protocol specification,
/// https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http.
///
/// Every POST carries a single JSON-RPC request or notification along with
/// its own client context. There is no session state between requests. A
/// request is answered on an SSE response stream if its handler emits related
/// notifications, and with a JSON body otherwise. The list and resource change
/// notifications reach `onNotification` alone.
///
/// A client posts with `streamableHttpClientChannel`. JSON replies use
/// `jsonDecode` and SSE replies use `sseMessageStream`.
library;

export 'src/client/streamable_http.dart' show streamableHttpClientChannel;
export 'src/server/streamable_http.dart' show handleStreamableHttpRequest;
export 'src/utils/sse.dart' show sseMessageStream;
