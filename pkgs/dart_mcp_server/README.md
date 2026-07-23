The Dart Tooling MCP Server exposes Dart and Flutter development tool actions to compatible AI-assistant clients.

## Status

WIP. This package is still experimental and is likely to evolve quickly.

## Set up your MCP client

> Note: all of the following set up instructions require Dart 3.9.0-163.0.dev or later.

<!-- Note: since many of our tools require access to the Dart Tooling Daemon, we may want
to be cautious about recommending tools where access to the Dart Tooling Daemon does not exist. -->

The Dart MCP server can work with any MCP client that supports standard I/O (stdio) as the
transport medium. To access all the features of the Dart MCP server, an MCP client must support
[Tools](https://modelcontextprotocol.io/docs/concepts/tools) and
[Resources](https://modelcontextprotocol.io/docs/concepts/resources). For the best development
experience with the Dart MCP server, an MCP client should also support
[Roots](https://modelcontextprotocol.io/docs/concepts/roots).

Here are specific instructions for some popular tools:

### Gemini CLI

To configure the [Gemini CLI](https://github.com/google-gemini/gemini-cli) to use the Dart MCP
server, edit the `.gemini/settings.json` file in your local project (configuration will only
apply to this project) or edit the global `~/.gemini/settings.json` file in your home directory
(configuration will apply for all projects).

```json
{
  "mcpServers": {
    "dart": {
      "command": "dart",
      "args": [
        "mcp-server"
      ]
    }
  }
}
```

For more information, see the official Gemini CLI documentation for
[setting up MCP servers](https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md#how-to-set-up-your-mcp-server).

### Gemini Code Assist in VS Code

> Note: this currently requires the "Insiders" channel. Follow
[instructions](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer#before-you-begin)
to enable this build.

[Gemini Code Assist](https://codeassist.google/)'s
[Agent mode](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer) integrates the Gemini CLI to provide a powerful
AI agent directly in your IDE. To configure Gemini Code Assist to use the Dart MCP
server, follow the instructions to [configure the Gemini](#gemini-cli) CLI above.

You can verify the MCP server has been configured properly by typing `/mcp` in the chat window in Agent mode.

![Gemini Code Assist list mcp tools](_docs/gca_mcp_list_tools.png "Gemini Code Assist list MCP tools")

For more information see the official Gemini Code Assist documentation for
[using agent mode](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer#before-you-begin).

<!-- ### Android Studio -->
<!-- TODO(https://github.com/dart-lang/ai/issues/199): once we are confident that the
Dart MCP server will work well with Android Studio's MCP support, add documentation here
for configuring the server in Android Studio. -->

### Cursor

[![Add to Cursor](https://cursor.com/deeplink/mcp-install-dark.svg)](cursor://anysphere.cursor-deeplink/mcp/install?name=dart&config=eyJ0eXBlIjoic3RkaW8iLCJjb21tYW5kIjoiZGFydCBtY3Atc2VydmVyIC0tZXhwZXJpbWVudGFsLW1jcC1zZXJ2ZXIgLS1mb3JjZS1yb290cy1mYWxsYmFjayJ9)

The easiest way to configure the Dart MCP server with Cursor is by clicking the "Add to Cursor"
button above.

Alternatively, you can configure the server manually. Go to **Cursor -> Settings -> Cursor Settings > Tools & Integrations**, and then click **"Add Custom MCP"** or **"New MCP Server"**
depending on whether you already have other MCP servers configured. Edit the `.cursor/mcp.json` file in your local project (configuration will only apply to this project) or
edit the global `~/.cursor/mcp.json` file in your home directory (configuration will apply for
all projects) to configure the Dart MCP server:

```json
{
  "mcpServers": {
    "dart": {
      "command": "dart",
      "args": [
        "mcp-server",
        "--experimental-mcp-server" // Can be removed for Dart 3.9.0 or later
      ]
    }
  }
}
```

For more information, see the official Cursor documentation for
[installing MCP servers](https://docs.cursor.com/context/model-context-protocol#installing-mcp-servers).

### GitHub Copilot in VS Code

<!-- TODO: once the dart.mcpServer setting is not hidden, we may be able
to provide a deep link to the Dart Extension Settings UI for users to
enable the server. See docs: https://code.visualstudio.com/docs/configure/settings#_settings-editor.
This may be preferable to adding the deep link button to VS Code's mcp settings. -->

> Note: requires Dart-Code VS Code extension v3.114 or later.

To configure the Dart MCP server with Copilot or any other AI agent that supports the
[VS Code MCP API](https://code.visualstudio.com/api/extension-guides/mcp), add the following
to your VS Code user settings (Command Palette > **Preferences: Open User Settings (JSON)**):
```json
"dart.mcpServer": true
```

By adding this setting, the Dart VS Code extension will register the Dart MCP Server
configuration with VS Code so that you don't have to manually configure the server.
Copilot will then automatically configure the Dart MCP server on your behalf. This is
a global setting. If you'd like the setting to apply only to a specific workspace, add
the entry to your workspace settings (Command Palette > **Preferences: Open Workspace Settings (JSON)**)
instead.

For more information, see the official VS Code documentation for
[enabling MCP support](https://code.visualstudio.com/docs/copilot/chat/mcp-servers#_enable-mcp-support-in-vs-code).

### Connecting to Applications

Often, connecting to your running application is as simple as asking your agent
to do it, you can say "connect to my flutter web app" or "connect to my web
server".

This works by discovering Dart Tooling Daemon instances on your machine, and
then discovering dart and flutter applications that are registered with those
instances. 

See the sections below for specific hints and details for flutter versus dart
apps, as well as hints about how to make this work better in multi-app
scenarios, or use fewer tokens.

#### Flutter Applications

Flutter applications are automatically registered with the Dart Tooling Daemon
when running in debug/profile mode, unless `--no-dds` is passed (the Dart
Development Service is actually what spawns DTD, so disabling that disables
DTD).

#### Dart Applications

To connect to a pure Dart application, you need to run the application with the
`--observe` flag. This will start the Dart Tooling Daemon (DTD) and register the
application with it.

#### Pass --print-dtd

Both `dart` and `flutter` support the `--print-dtd` flag to get an explicit
reference to the DTD URI for that application. This is especially useful when the
agent is spawning the process, because it can avoid having to list all available
DTD URIs and trying to pick the right one.

It is recommended to put this instruction in a RULES file so that it is always
available to the agent. For example, in a GEMINI.md file in your project:

```md
## Launching Dart and Flutter Applications

- Always pass the `--print-dtd` flag to `dart` or `flutter` when spawning an
  application.
- For `dart` applications, always pass the `--observe` flag to enable the app to
  be connected to.
- Both `--print-dtd` and `--observe` must come before the script name or path
  when spawning `dart` applications: `dart --observe --print-dtd bin/main.dart`.
```

## Tools

<!-- run 'dart tool/update_readme.dart' to update -->

<!-- generated -->

| Tool Name | Title | Description | Categories | Enabled |
| --- | --- | --- | --- | --- |
| `analyze_files` | Analyze projects | Analyzes specific paths, or the entire project, for errors. | analysis | Yes |
| `create_project` | Create project | Creates a new Dart or Flutter project. | cli | No |
| `dart_fix` | Dart fix | Runs `dart fix --apply` for the given project roots. | cli | No |
| `dart_format` | Dart format | Runs `dart format .` for the given project roots. | cli | No |
| `dtd` | Dart Tooling Daemon | Manage live app connections to Dart and Flutter apps using the Dart Tooling Daemon (DTD). Start by using the `listDtdUris` command to find available DTD URIs, followed by the `connect` command with the desired URI to connect to. Apps from a given DTD instance are automatically connected to, and you can use the `listConnectedApps` command to see the list of connected apps. If you see DTD instances with a working dir that looks like a home directory, these are likely connected to an IDE and you should connect to those to find IDE launched apps. | dart_tooling_daemon | Yes |
| `flutter_driver_command` | Flutter Driver | Run a flutter driver command | flutter_driver | Yes |
| `get_active_location` | Get Active Editor Location | Retrieves the current active location (e.g., cursor position) in the connected editor. Requires an active DTD connection. | dart_tooling_daemon | No |
| `get_app_logs` |  | Returns the collected logs for a given flutter run process id. Can only retrieve logs started by the launch_app tool. | flutter, flutter_app_lifecycle | No |
| `get_runtime_errors` | Get runtime errors | Retrieves the most recent runtime errors that have occurred in the active Dart or Flutter application. Requires an active DTD connection. | dart_tooling_daemon | Yes |
| `hot_reload` | Hot reload | Performs a hot reload of the active Flutter application. This will apply the latest code changes to the running application, while maintaining application state.  Reload will not update const definitions of global values. Requires an active DTD connection. | flutter | Yes |
| `hot_restart` | Hot restart | Performs a hot restart of the active Flutter application. This applies the latest code changes to the running application, including changes to global const values, while resetting application state. Requires an active DTD connection. Doesn't work for Non-Flutter Dart CLI programs. | flutter | Yes |
| `launch_app` |  | Launches a Flutter application and returns its DTD URI. | flutter, flutter_app_lifecycle | No |
| `list_devices` |  | Lists available Flutter devices. | flutter, flutter_app_lifecycle, cli | No |
| `list_running_apps` |  | Returns the list of running app process IDs and associated DTD URIs for apps started by the launch_app tool. | flutter, flutter_app_lifecycle | No |
| `lsp` | Language Server Protocol | Interacts with the Dart Language Server Protocol (LSP) to provide code intelligence features like hover, signature help, and symbol resolution.<br>Commands:<br>- hover: Get hover information (docs, types) at a position. Requires: uri, line, column.<br>- signatureHelp: Get signature help at a position. Requires: uri, line, column.<br>- resolveWorkspaceSymbol: Fuzzy search for symbols by name. Requires: query. | analysis | Yes |
| `pub` | pub | Runs a pub command for the given project roots, like `dart pub get` or `flutter pub add`. | cli, package_deps | Yes |
| `pub_dev_search` | pub.dev search | Searches pub.dev for packages relevant to a given search query. The response will describe each result with its download count, package description, topics, license, and publisher. | package_deps | Yes |
| `read_package_uris` |  | Reads "package" and "package-root" scheme URIs which represent paths under Dart package dependencies. "package" URIs are always relative to the "lib" directory and "package-root" URIs are relative to the true root directory of the package. For example, the URI "package:test/test.dart" represents the path "lib/test.dart" under the "test" package. "package-root:test/example/test.dart" represents the path "example/test.dart". This API supports both reading files and listing directories. | package_deps | Yes |
| `rip_grep_packages` |  | Uses ripgrep to find patterns in package dependencies. Note that ripgrep must be installed already, see https://github.com/BurntSushi/ripgrep for instructions. | package_deps | Yes |
| `roots` |  | Manage project roots. | None | Yes |
| `run_tests` | Run tests | Run Dart or Flutter tests with an agent centric UX. ALWAYS use instead of `dart test` or `flutter test` shell commands. | cli | No |
| `stop_app` |  | Kills a running Flutter process started by the launch_app tool. | flutter, flutter_app_lifecycle | No |
| `vm_service` | VM Service | Manage and interact with VM service connections. This tool allows you to connect to an app using its VM service URI, disconnect from it, or invoke VM service methods directly. Connecting allows features like hot reload to work on apps not launched via DTD. | dart_tooling_daemon | Yes |
| `widget_inspector` | Widget Inspector | Interact with the Flutter widget inspector in the active Flutter application. Requires an active DTD connection. | flutter | Yes |

<!-- generated -->

## Connect to a running Flutter app

Recent Flutter versions auto-register a DTD via DDS for every `flutter run`
in debug or profile mode — no extra flag is needed. Discover and connect:

```text
dtd(command: "listDtdUris")
dtd(command: "connect", uri: "ws://127.0.0.1:<port>/<token>=")
dtd(command: "listConnectedApps")
```

`listConnectedApps` returns each app's VM Service URI. When more than one
app is connected, every subsequent tool call must include `appUri` (that
VM Service URI) to disambiguate.

### Mobile (iOS, Android) and desktop — Flutter Driver

To use finder-based UI commands (`tap`, `enter_text`, `screenshot`,
`scroll`, `waitFor`…), your app must call `enableFlutterDriverExtension()`
before `runApp()` (see the [Flutter Driver documentation][] for background).
The `flutter_driver` package does **not** compile under dart2js, so for
projects that also build for web, gate the import via a conditional and
provide a stub for web builds:

```dart
// lib/utils/flutter_driver_setup.dart
import 'package:flutter_driver/driver_extension.dart'
    if (dart.library.html) 'flutter_driver_stub.dart';

void setupFlutterDriver() {
  if (const bool.fromEnvironment('ENABLE_FLUTTER_DRIVER', defaultValue: false)) {
    enableFlutterDriverExtension();
  }
}
```

```dart
// lib/utils/flutter_driver_stub.dart
void enableFlutterDriverExtension() {
  throw UnsupportedError('Flutter Driver is not supported on web.');
}
```

```dart
// main.dart
void main() {
  setupFlutterDriver();
  runApp(const MyApp());
}
```

Launch with the flag (mobile and desktop only — never set this for web):

```bash
flutter run -d <device-id> --dart-define=ENABLE_FLUTTER_DRIVER=true
```

`bool.fromEnvironment` is baked at compile time; toggling it requires a
quit and relaunch, not a hot reload.

#### Driving the UI

```text
flutter_driver_command(command: "screenshot", appUri: "...")
flutter_driver_command(command: "tap", finderType: "ByText", text: "Sign In", appUri: "...")
```

The `enabled` parameter (used by `set_semantics`, `set_frame_sync`,
`set_text_entry_emulation`) is passed as a string — `"true"` or `"false"`,
not an unquoted bool.

A few non-obvious finder rules:

- **TextField hint text** is part of the field decoration, not a `Text`
  widget — `ByText` will not find it. Use `BySemanticsLabel` (or add a
  `ValueKey` and use `ByValueKey`).
- **`BySemanticsLabel` requires semantics enabled.** Call
  `flutter_driver_command(command: "set_semantics", enabled: "true")` once
  per session before relying on it; the semantics tree only builds when
  accessibility is on.
- **Multiple `TextField`s on screen** make `ByType: "TextField"` fail with
  *"ambiguously found multiple matching widgets"*. Add a `ValueKey` or use
  `BySemanticsLabel` with the field's hint or label.
- **Frame sync timeouts** on apps with continuous animations (Rive, Lottie,
  spinners) — call
  `flutter_driver_command(command: "set_frame_sync", enabled: "false")`
  once per session.

#### No pixel-coordinate clicks

Flutter Driver locates widgets only by finders (text, type, key, semantics).
There is no pixel-coordinate click. On Android, `adb shell input tap x y`
fills the gap from a regular terminal but is not exposed through the MCP
server. On iOS there is no known equivalent — every interactive widget the
agent might click on must expose visible text, a tooltip, a `ValueKey`, or
a semantics label.

### Web

The Dart MCP server works on web for everything except finder-based UI
driving: `widget_inspector`, `get_runtime_errors`, `hot_reload`,
`analyze_files`, `lsp` all work normally over DTD. For clicks, screenshots,
and form input, pair the Dart MCP server with a **browser-driving MCP**
(any MCP that controls Chrome or Firefox).

Two launch modes:

`flutter run -d chrome` opens immediately in a clean Chrome window
spawned by Flutter — no extensions, no user profile — and that window is
the one DTD knows about. A browser-driving MCP cannot attach to that
window, and pointing a second browser at the same dev URL is misleading
(see the warning below).

`flutter run -d web-server` doesn't auto-spawn a browser — open the URL
in your MCP-controlled Chrome, and DTD picks the app up once the page
finishes loading. The browser the agent drives *is* the registered
VM Service client. DTD does **not** appear in `listDtdUris` until the
URL actually loads in a browser; that handshake is what registers the
app with DDS. The "Dart Debug Chrome extension" Flutter mentions in its
log is for human DevTools-style breakpoints, not for the MCP — the MCP
toolset works without it.

> ⚠️ **The second-browser trap (`-d chrome` only).** Opening another
> Chrome tab at the same dev URL looks normal — the bundle is served, the
> app renders, the user is logged in. But hot reload, runtime errors, and
> the widget inspector all keep targeting the Chrome Flutter spawned:
> edits don't appear in the second browser, and `listConnectedApps` still
> shows a single entry. The same applies to `print` output and runtime
> errors, which only flow back from the CDP-attached window. An agent
> driving that second browser believes it is reading and patching the
> visible app while every MCP call silently lands on an invisible window.
> Installing the Dart Debug Extension in a regular Chrome does not
> rescue this — in `-d chrome` mode, dwds tracks the window it spawned via
> CDP and ignores other clients. For agent-driven web testing, prefer
> `-d web-server`.

### Identifying instances when several are connected

`listConnectedApps` returns a `name` per app:

| Source | `name` |
|---|---|
| iOS / Android / desktop | `Kind: Flutter - Device: <device> - Package: <bundle>` |
| Web | `Unknown web app` (always — same string for every web instance) |

For web, match the VM Service URI suffix (`<port>/<token>=`) against the
`A Dart VM Service on Web Server is available at: …` line in each
`flutter run` log. Logging each launch to its own file
(`flutter run … 2>&1 | tee /tmp/flutter-<port>.log`) makes the lookup
trivial.

### Notes on a few tools

- **`analyze_files`** runs the analysis server with `custom_lint` plugins
  (e.g. `riverpod_lint`); the bash `dart analyze` CLI does not. If your
  project relies on those plugins, `analyze_files` is the only way an
  agent will see the diagnostics. Each entry in the `roots` argument
  accepts an optional `paths` field — pass `paths: ["lib"]` to scope the
  analysis; without it, an iOS build pulls `build/ios/SourcePackages` into
  the analyzed set.
- **`widget_inspector(get_widget_tree)`** can return very large trees on
  non-trivial apps and overflow to a file. Pass `summaryOnly: true` for a
  much smaller payload that still includes user widgets.

### Troubleshooting

- **`listDtdUris` returns nothing on a freshly launched web app.** The
  app must be loaded in a browser tab before DTD registers. Open the URL,
  wait a few seconds, retry.
- **`Connected to a VM Service but expected to connect to a Dart Tooling
  Daemon service.`** The URI passed to `connect` was the VM Service URI,
  not the DTD URI. Use the `wsUri` from `listDtdUris`; the VM Service URI
  is what you pass later as `appUri`.
- **`The flutter driver extension is not enabled.`** Either you're on web
  (use a browser MCP — Flutter Driver doesn't exist on dart2js), or you
  launched without `--dart-define=ENABLE_FLUTTER_DRIVER=true`. The flag is
  compile-time — quit and relaunch.
- **`BySemanticsLabel` times out.** Call
  `flutter_driver_command(command: "set_semantics", enabled: "true")`
  first.
- **Frame sync timeouts** on animated apps. Call
  `flutter_driver_command(command: "set_frame_sync", enabled: "false")`
  once per session.
- **`hot_reload` (or any tool) returns "must specify app URI".** Multiple
  apps connected — pass `appUri` on every call.
- **Live `flutter run` exits with `The Dart compiler exited unexpectedly`.**
  Something deleted `.dart_tool/` or `build/` while the app was running
  (typically `flutter clean`, `flutter pub get`, or a `build_runner` rerun).
  Quit the app first, clean, relaunch.

[Flutter Driver documentation]: https://docs.flutter.dev/testing/integration-tests
