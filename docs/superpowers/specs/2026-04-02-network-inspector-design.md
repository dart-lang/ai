# Network Inspector Tools for dart_mcp_server

**Date:** 2026-04-02
**Related issue:** dart-lang/ai#269

## Overview

Add HTTP network inspection tools to `dart_mcp_server` so an AI agent can observe live HTTP traffic from a running Flutter/Dart app without modifying app source code. Tracking is enabled automatically on DTD connect so no requests are missed.

## Architecture

### Auto-enable on DTD connect

`DartToolingDaemonSupport.updateActiveVmServices()` is called whenever DTD connects or app VM services change. We extend this method to call `httpEnableTimelineLogging(isolateId, true)` on every isolate of every newly connected `VmService`. This ensures HTTP profiling is active from the first moment the app is reachable — no tool call needed by the agent.

If `ext.dart.io.httpEnableTimelineLogging` is not present in `isolate.extensionRPCs` (e.g. web apps, or apps not using `dart:io`), the call is silently skipped.

### New mixin: `NetworkInspectorSupport`

New file: `lib/src/mixins/network_inspector.dart`

Mixin declaration:
```dart
base mixin NetworkInspectorSupport on MCPServer
    implements DartToolingDaemonSupport, SdkSupport { ... }
```

Registered on `DartMCPServer` alongside existing mixins.

### Tools

#### `get_network_logs`

Fetches all recorded HTTP requests for a running app.

Input schema:
- `app_id` (string, required) — the app URI, same as other DTD tools
- `updated_since` (string, optional) — ISO 8601 timestamp; if provided, only requests started or updated after this time are returned

Implementation: calls `vmService.getHttpProfile(isolateId, updatedSince: ...)` via `_callOnVmService`. Returns an array of request summaries:
- `id`, `method`, `uri`, `status_code`, `start_time`, `end_time`, `request_size`, `response_size`, `error` (if failed)

Feature category: `networkInspector`. Enabled by default: `false`.

#### `clear_network_logs`

Clears the HTTP profile buffer for a running app.

Input schema:
- `app_id` (string, required)

Implementation: calls `vmService.clearHttpProfile(isolateId)` via `_callOnVmService`.

Feature category: `networkInspector`. Enabled by default: `false`.

#### `get_network_request`

Fetches full detail for a single HTTP request by ID, including headers and body.

Input schema:
- `app_id` (string, required)
- `request_id` (string, required) — the `id` field from `get_network_logs`

Implementation: calls `vmService.getHttpProfileRequest(isolateId, id)` via `_callOnVmService`. Returns full detail:
- All summary fields from `get_network_logs`
- `request_headers`, `response_headers`
- `request_body` (base64-encoded bytes, nullable)
- `response_body` (base64-encoded bytes, nullable)
- `proxy` info if present

Feature category: `networkInspector`. Enabled by default: `false`.

### Tool names

Three entries added to `ToolNames` enum in `lib/src/utils/names.dart`:
- `getNetworkLogs`
- `clearNetworkLogs`
- `getNetworkRequest`

### Feature category

New value `networkInspector` added to `FeatureCategory` enum in `lib/src/features_configuration.dart`. Enabled via `--enable=networkInspector` CLI flag or MCP config.

## Data Flow

```
MCP Client
  → calls get_network_logs(app_id)
  → NetworkInspectorSupport._getNetworkLogs(request)
  → _callOnVmService(appUri, (vmService) async {
       final isolateId = await _getMainIsolateId(vmService);
       return vmService.getHttpProfile(isolateId, updatedSince: ...);
    })
  → returns CallToolResult with structured HTTP profile data
```

## Error Handling

- App not connected to DTD: return `isError: true` with "No app connected" message (same pattern as existing tools).
- `ext.dart.io.getHttpProfile` not present on isolate (web app or dart:io not used): return `isError: true` with "HTTP profiling not available for this app".
- Empty profile (no requests yet): return success with empty array — not an error.

## Testing

Follow the existing pattern in `test/tools/`:
- Unit test: `test/tools/network_inspector_test.dart`
- Uses the existing `counter_app` test fixture (it makes no HTTP calls, so `get_network_logs` returns empty — sufficient to verify the plumbing)
- Mock `VmService` to return a canned `HttpProfile` for the happy path
- Test error cases: not connected, extension not available

## Out of Scope

- Web app support (Chrome DevTools Protocol transport) — noted in issue #269 as a separate concern
- Socket profiling (`ext.dart.io.socketProfilingEnabled`) — can be a follow-up
- HAR export (`dump_har`) — can be a follow-up
