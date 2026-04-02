# Network Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add HTTP network inspection tools to `dart_mcp_server` so an AI agent can observe live HTTP traffic from a running Flutter/Dart app with zero app-side code changes.

**Architecture:** Three new tools (`get_network_logs`, `clear_network_logs`, `get_network_request`) are added directly to `DartToolingDaemonSupport` in `dtd.dart` (where all VM-service-touching tools live, since `_callOnVmService` is private to that mixin). HTTP profiling is auto-enabled per-isolate inside `updateActiveVmServices`, so capture starts the moment a VM service connects.

**Tech Stack:** Dart, `package:vm_service` (`DartIOExtension`), `package:dart_mcp/server.dart`

---

## File Map

| File | Action | What changes |
|---|---|---|
| `lib/src/features_configuration.dart` | Modify | Add `networkInspector` to `FeatureCategory` enum |
| `lib/src/utils/names.dart` | Modify | Add `getNetworkLogs`, `clearNetworkLogs`, `getNetworkRequest` to `ToolNames` |
| `lib/src/mixins/dtd.dart` | Modify | Auto-enable HTTP profiling in `updateActiveVmServices`; add 3 tool handlers + static `Tool` declarations + registration in `initialize` |
| `test/tools/network_inspector_test.dart` | Create | Integration tests for the 3 tools using the existing `TestHarness` + counter app |

> **Note on mixin placement:** All tools that use `_callOnVmService` live in `dtd.dart` because `_callOnVmService` is a private method of `DartToolingDaemonSupport`. A separate mixin file cannot access it. The spec described `NetworkInspectorSupport` as a separate mixin but the code organisation requires it to live in `dtd.dart`. The tools are logically grouped under the same `dartToolingDaemon` feature infrastructure.

---

## Task 1: Add `networkInspector` feature category

**Files:**
- Modify: `pkgs/dart_mcp_server/lib/src/features_configuration.dart`

- [ ] **Step 1: Add the enum value**

In `features_configuration.dart`, add `networkInspector` after `packageDeps`:

```dart
  /// Features for inspecting HTTP network traffic via the VM service.
  networkInspector(dartToolingDaemon, 'network_inspector');
```

Full updated enum tail (replace `packageDeps` definition and add below it):

```dart
  /// Features for interacting with package dependencies, pub and/or pub.dev
  packageDeps(all, 'package_deps'),

  /// Features for inspecting HTTP network traffic via the VM service.
  networkInspector(dartToolingDaemon, 'network_inspector');
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
dart analyze lib/src/features_configuration.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
git add lib/src/features_configuration.dart
git commit -m "feat: add networkInspector feature category"
```

---

## Task 2: Add tool names

**Files:**
- Modify: `pkgs/dart_mcp_server/lib/src/utils/names.dart`

- [ ] **Step 1: Add three tool names to `ToolNames` enum**

Add after `getRuntimeErrors`:

```dart
  getNetworkLogs('get_network_logs'),
  clearNetworkLogs('clear_network_logs'),
  getNetworkRequest('get_network_request'),
```

Also add the `updatedSince` and `requestId` parameter name constants to `ParameterNames`:

```dart
  static const requestId = 'requestId';
  static const updatedSince = 'updatedSince';
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
dart analyze lib/src/utils/names.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/src/utils/names.dart
git commit -m "feat: add network inspector tool names and parameter names"
```

---

## Task 3: Write failing tests

**Files:**
- Create: `pkgs/dart_mcp_server/test/tools/network_inspector_test.dart`

- [ ] **Step 1: Create the test file**

```dart
// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp_server/src/features_configuration.dart';
import 'package:dart_mcp_server/src/mixins/dtd.dart';
import 'package:dart_mcp_server/src/utils/names.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;

  group('network inspector tools', () {
    group('[compiled server]', () {
      setUp(() async {
        testHarness = await TestHarness.start(
          featuresConfig: FeaturesConfiguration(
            enabledNames: {FeatureCategory.networkInspector.name},
          ),
          inProcess: false,
          processManager: const LocalProcessManager(),
        );
        await testHarness.connectToDtd();
      });

      tearDown(() async {
        await testHarness.tearDown();
      });

      group('flutter app tests', () {
        test('get_network_logs returns empty list when no requests made',
            () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );

          final result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: ToolNames.getNetworkLogs.name,
              arguments: {},
            ),
          );

          expect(result.isError, isNot(true));
          final text = (result.content.first as TextContent).text;
          final decoded = jsonDecode(text) as List;
          expect(decoded, isEmpty);
        });

        test('clear_network_logs succeeds', () async {
          await testHarness.startDebugSession(
            counterAppPath,
            'lib/main.dart',
            isFlutter: true,
          );

          final result = await testHarness.callToolWithRetry(
            CallToolRequest(
              name: ToolNames.clearNetworkLogs.name,
              arguments: {},
            ),
          );

          expect(result.isError, isNot(true));
        });

        test('get_network_logs tools are registered', () async {
          final tools =
              (await testHarness.mcpServerConnection.listTools()).tools;
          final toolNames = tools.map((t) => t.name).toSet();

          expect(toolNames, contains(ToolNames.getNetworkLogs.name));
          expect(toolNames, contains(ToolNames.clearNetworkLogs.name));
          expect(toolNames, contains(ToolNames.getNetworkRequest.name));
        });

        test('get_network_logs returns error when DTD not connected', () async {
          // Don't call connectToDtd - just check the error path.
          final freshHarness = await TestHarness.start(
            featuresConfig: FeaturesConfiguration(
              enabledNames: {FeatureCategory.networkInspector.name},
            ),
            inProcess: true,
          );
          addTearDown(freshHarness.tearDown);

          final result = await freshHarness.mcpServerConnection.callTool(
            CallToolRequest(
              name: ToolNames.getNetworkLogs.name,
              arguments: {},
            ),
          );

          expect(result.isError, true);
        });
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail (tools not yet implemented)**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
dart test test/tools/network_inspector_test.dart --name "are registered"
```
Expected: FAIL — tool not found / not registered.

- [ ] **Step 3: Commit the failing tests**

```bash
git add test/tools/network_inspector_test.dart
git commit -m "test: add failing network inspector tests"
```

---

## Task 4: Implement auto-enable HTTP profiling on VM service connect

**Files:**
- Modify: `pkgs/dart_mcp_server/lib/src/mixins/dtd.dart`

- [ ] **Step 1: Add `_enableHttpProfiling` helper after `updateActiveVmServices`**

In `dtd.dart`, after the closing `}` of `updateActiveVmServices` (around line 196), add:

```dart
  /// Enables HTTP profiling on all isolates of [vmService].
  ///
  /// Silently skips isolates that do not support the dart:io HTTP profiling
  /// extension (e.g. web apps or isolates not using dart:io).
  Future<void> _enableHttpProfiling(VmService vmService) async {
    try {
      final vm = await vmService.getVM();
      for (final isolateRef in vm.isolates ?? <IsolateRef>[]) {
        final id = isolateRef.id;
        if (id == null) continue;
        try {
          final isolate = await vmService.getIsolate(id);
          final hasExtension = isolate.extensionRPCs?.contains(
                'ext.dart.io.httpEnableTimelineLogging',
              ) ??
              false;
          if (!hasExtension) continue;
          await vmService.httpEnableTimelineLogging(id, enabled: true);
        } catch (_) {
          // Silently skip isolates that fail — they may be in a bad state.
        }
      }
    } catch (_) {
      // If we can't even get the VM, skip entirely.
    }
  }
```

- [ ] **Step 2: Call `_enableHttpProfiling` after connecting each new VM service in `updateActiveVmServices`**

Find the line inside `updateActiveVmServices` where `vmService` is obtained:

```dart
      final vmService = await vmServiceFuture;
      // Start listening for and collecting errors immediately.
      final errorService = await _AppListener.forVmService(vmService, this);
```

Add the call right after `final vmService = await vmServiceFuture;`:

```dart
      final vmService = await vmServiceFuture;
      // Enable HTTP profiling so network logs are captured from app start.
      await _enableHttpProfiling(vmService);
      // Start listening for and collecting errors immediately.
      final errorService = await _AppListener.forVmService(vmService, this);
```

- [ ] **Step 3: Verify it compiles**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
dart analyze lib/src/mixins/dtd.dart
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/src/mixins/dtd.dart
git commit -m "feat: auto-enable HTTP profiling when VM service connects"
```

---

## Task 5: Implement the three network inspector tools

**Files:**
- Modify: `pkgs/dart_mcp_server/lib/src/mixins/dtd.dart`

- [ ] **Step 1: Register tools in `initialize`**

Find the `initialize` method in `dtd.dart` (around line 199). Add three registrations:

```dart
    registerTool(getNetworkLogsTool, _getNetworkLogs);
    registerTool(clearNetworkLogsTool, _clearNetworkLogs);
    registerTool(getNetworkRequestTool, _getNetworkRequest);
```

Place them after `registerTool(flutterDriverTool, _callFlutterDriver);` and before `return super.initialize(request);`.

Also add the three tools to `allTools`:

```dart
  @visibleForTesting
  static final List<Tool> allTools = [
    dtdTool,
    getRuntimeErrorsTool,
    getActiveLocationTool,
    hotRestartTool,
    hotReloadTool,
    widgetInspectorTool,
    flutterDriverTool,
    getNetworkLogsTool,
    clearNetworkLogsTool,
    getNetworkRequestTool,
  ];
```

- [ ] **Step 2: Add `_getNetworkLogs` handler**

Add after the `_callFlutterDriver` method:

```dart
  /// Fetches recorded HTTP requests for the running app.
  Future<CallToolResult> _getNetworkLogs(CallToolRequest request) async {
    final appUri = request.arguments?[ParameterNames.appUri] as String?;
    final updatedSinceStr =
        request.arguments?[ParameterNames.updatedSince] as String?;
    final updatedSince = updatedSinceStr != null
        ? DateTime.tryParse(updatedSinceStr)
        : null;

    return _callOnVmService(
      appUri: appUri,
      callback: (vmService) async {
        try {
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final profile = await vmService.getHttpProfile(
            isolateId,
            updatedSince: updatedSince,
          );
          final requests = profile.requests
              .map(
                (r) => {
                  'id': r.id,
                  'method': r.method,
                  'uri': r.uri,
                  'status_code': r.response?.statusCode,
                  'start_time': r.startTime.toIso8601String(),
                  'end_time': r.endTime?.toIso8601String(),
                  'request_size': r.requestBody?.bodySizeBytes,
                  'response_size': r.response?.bodySizeBytes,
                  'error': r.response == null && r.endTime != null
                      ? 'request failed'
                      : null,
                },
              )
              .toList();
          return CallToolResult(
            content: [TextContent(text: jsonEncode(requests))],
            structuredContent: {'requests': requests},
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Failed to get network logs: $e'),
            ],
          )..failureReason = CallToolFailureReason.unhandledError;
        }
      },
    );
  }
```

- [ ] **Step 3: Add `_clearNetworkLogs` handler**

```dart
  /// Clears the HTTP profile buffer for the running app.
  Future<CallToolResult> _clearNetworkLogs(CallToolRequest request) async {
    final appUri = request.arguments?[ParameterNames.appUri] as String?;
    return _callOnVmService(
      appUri: appUri,
      callback: (vmService) async {
        try {
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          await vmService.clearHttpProfile(isolateId);
          return CallToolResult(
            content: [TextContent(text: 'Network logs cleared.')],
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Failed to clear network logs: $e')],
          )..failureReason = CallToolFailureReason.unhandledError;
        }
      },
    );
  }
```

- [ ] **Step 4: Add `_getNetworkRequest` handler**

```dart
  /// Fetches full detail for a single HTTP request by ID.
  Future<CallToolResult> _getNetworkRequest(CallToolRequest request) async {
    final appUri = request.arguments?[ParameterNames.appUri] as String?;
    final requestId = request.arguments?[ParameterNames.requestId] as String?;
    if (requestId == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'Missing required parameter: ${ParameterNames.requestId}'),
        ],
      )..failureReason = CallToolFailureReason.argumentError;
    }

    return _callOnVmService(
      appUri: appUri,
      callback: (vmService) async {
        try {
          final vm = await vmService.getVM();
          final isolateId = vm.isolates!.first.id!;
          final r = await vmService.getHttpProfileRequest(isolateId, requestId);
          final detail = {
            'id': r.id,
            'method': r.method,
            'uri': r.uri,
            'status_code': r.response?.statusCode,
            'start_time': r.startTime.toIso8601String(),
            'end_time': r.endTime?.toIso8601String(),
            'request_headers': r.requestBody?.headers,
            'response_headers': r.response?.headers,
            'request_body': r.requestBody?.body != null
                ? base64Encode(r.requestBody!.body!)
                : null,
            'response_body': r.response?.body != null
                ? base64Encode(r.response!.body!)
                : null,
          };
          return CallToolResult(
            content: [TextContent(text: jsonEncode(detail))],
            structuredContent: detail,
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Failed to get network request: $e'),
            ],
          )..failureReason = CallToolFailureReason.unhandledError;
        }
      },
    );
  }
```

- [ ] **Step 5: Add static `Tool` declarations**

Add these near the bottom of `dtd.dart` alongside the other static tool declarations (near the `hotReloadTool`, `widgetInspectorTool` etc. static finals):

```dart
  @visibleForTesting
  static final getNetworkLogsTool = Tool(
    name: ToolNames.getNetworkLogs.name,
    description:
        'Fetches recorded HTTP requests from the running app. '
        'HTTP profiling is enabled automatically when the app connects, so '
        'requests are captured from app start. Use updatedSince to poll only '
        'new entries since a previous call.',
    annotations: ToolAnnotations(title: 'Get Network Logs', readOnlyHint: true),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.appUri: Schema.string(
          description:
              'The app URI to fetch network logs from. Required if '
              'multiple apps are connected.',
        ),
        ParameterNames.updatedSince: Schema.string(
          description:
              'ISO 8601 timestamp. If provided, only requests started or '
              'updated after this time are returned.',
        ),
      },
      additionalProperties: false,
    ),
  )
    ..categories = [FeatureCategory.networkInspector]
    ..enabledByDefault = false;

  @visibleForTesting
  static final clearNetworkLogsTool = Tool(
    name: ToolNames.clearNetworkLogs.name,
    description: 'Clears the HTTP profile buffer for the running app.',
    annotations: ToolAnnotations(title: 'Clear Network Logs'),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.appUri: Schema.string(
          description:
              'The app URI to clear network logs for. Required if '
              'multiple apps are connected.',
        ),
      },
      additionalProperties: false,
    ),
  )
    ..categories = [FeatureCategory.networkInspector]
    ..enabledByDefault = false;

  @visibleForTesting
  static final getNetworkRequestTool = Tool(
    name: ToolNames.getNetworkRequest.name,
    description:
        'Fetches full detail for a single HTTP request by ID, including '
        'headers and body bytes (base64-encoded). Get the request ID from '
        'get_network_logs.',
    annotations: ToolAnnotations(
      title: 'Get Network Request',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        ParameterNames.appUri: Schema.string(
          description:
              'The app URI. Required if multiple apps are connected.',
        ),
        ParameterNames.requestId: Schema.string(
          description: 'The request ID from get_network_logs.',
        ),
      },
      required: [ParameterNames.requestId],
      additionalProperties: false,
    ),
  )
    ..categories = [FeatureCategory.networkInspector]
    ..enabledByDefault = false;
```

- [ ] **Step 6: Add `dart:convert` import if not already present**

Check the imports at the top of `dtd.dart`. It already imports `dart:convert` (line 7). No change needed.

- [ ] **Step 7: Verify it compiles**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
dart analyze lib/src/mixins/dtd.dart
```
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/src/mixins/dtd.dart
git commit -m "feat: implement get_network_logs, clear_network_logs, get_network_request tools"
```

---

## Task 6: Run the tests

- [ ] **Step 1: Run the network inspector tests**

```bash
cd ~/Workspace/ai/pkgs/dart_mcp_server
dart test test/tools/network_inspector_test.dart -r expanded
```
Expected: all tests PASS.

- [ ] **Step 2: Run the full test suite to check for regressions**

```bash
dart test --timeout 120s
```
Expected: all pre-existing tests still pass.

- [ ] **Step 3: Commit if anything needed fixing**

```bash
git add -p
git commit -m "fix: address test failures in network inspector"
```

---

## Task 7: Update Claude Code MCP config to use the local build

- [ ] **Step 1: Find the current dart MCP server config**

```bash
cat ~/.claude/settings.json | grep -A5 '"dart"'
```

- [ ] **Step 2: Update the config**

In `~/.claude/settings.json`, find the `dart` MCP server entry. It currently looks something like:

```json
"dart": {
  "command": "dart_mcp_server",
  ...
}
```

Change it to point to the local fork:

```json
"dart": {
  "type": "stdio",
  "command": "dart",
  "args": [
    "run",
    "/Users/vietthangvunguyen/Workspace/ai/pkgs/dart_mcp_server/bin/main.dart",
    "--enable=networkInspector"
  ]
}
```

- [ ] **Step 3: Restart Claude Code**

Restart the Claude Code session to pick up the new MCP server. On next launch the `get_network_logs`, `clear_network_logs`, and `get_network_request` tools will be available in `mcp__dart__*`.

---

## Task 8: Push and open PR

- [ ] **Step 1: Push branch**

```bash
cd ~/Workspace/ai
git push origin main
```

- [ ] **Step 2: Open PR against dart-lang/ai**

```bash
gh repo set-default ThangVuNguyenViet/ai
gh pr create \
  --repo dart-lang/ai \
  --head ThangVuNguyenViet:main \
  --title "feat(dart_mcp_server): add HTTP network inspection tools" \
  --body "$(cat <<'EOF'
## Summary

Implements the network inspection tools proposed in dart-lang/ai#269.

- Auto-enables HTTP profiling (`ext.dart.io.httpEnableTimelineLogging`) on every isolate when a VM service connects, so requests are captured from app start
- Adds `get_network_logs` — fetch recorded HTTP requests, with optional `updatedSince` polling
- Adds `clear_network_logs` — reset the HTTP profile buffer  
- Adds `get_network_request` — fetch full detail (headers + body) for a single request by ID
- New `networkInspector` feature category (child of `dartToolingDaemon`), disabled by default

No app-side code changes required. Uses `ext.dart.io.*` extensions registered by the Dart runtime for any `dart:io` app in debug mode.

Closes dart-lang/ai#269 (partial — web/CDP transport not included)

## Test plan
- [ ] `dart test test/tools/network_inspector_test.dart` passes
- [ ] Full `dart test` suite passes with no regressions
- [ ] Manually verify with `flutter run` + `--enable=networkInspector` flag
EOF
)"
```
