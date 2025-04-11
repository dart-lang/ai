# dev_mcp_host

A DevTools extension that acts as an MCP Host & Client for development purposes.

## Using this extension to develop the Dart Tooling MCP Server

### From VS code

These instructions will also apply to VS code based IDEs, like Cursor, where the
Dart-Code extension is installed.

1. Open the `ai/` folder in your IDE.
2. Navigate to the Flutter sidebar to see the `dev_mcp_host` DevTools extension.
3. Open the `dev_mcp_host` extension. The extension will automatically be
connected to the DTD instance managed by the IDE.

### From IntelliJ / Android Studio

1. Open the `ai/` folder in your IDE.
2. Navigate to the DevTools Extensions tool window.
3. Open the `dev_mcp_host` DevTools tab. The extension will automatically be
connected to the DTD instance managed by the IDE.

## Developing the extension

Launch the extension web app in the simulated environment by using the provided
VS Code launch configuration, or run this command from `dev_mcp_host`:

```shell
flutter run -d chrome --dart-define=use_simulated_environment=true
```

## Building the extension

To build your extension so that it can be served from a real instance of
DevTools, run the build command:

```shell
cd dev_mcp_host;
flutter pub get;
dart run devtools_extensions build_and_copy --source=. --dest=./extension/devtools
```
