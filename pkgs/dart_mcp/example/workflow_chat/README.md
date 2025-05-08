# Dash Chat

An example MCP client flutter chat app. 

## Getting Started

To run this app you will need a gemini API key, which should be provided using
the `--dart-define=GEMINI_API_KEY=<your_api_key>` flag to `flutter run`.

This can be done using a vscode launch config, reading from system environment
variables, something like this:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "workflow_chat",
            "cwd": "pkgs/dart_mcp/example/workflow_chat",
            "request": "launch",
            "type": "dart",
            "program": "lib/main.dart",
            "args": [
                "--dart-define=GEMINI_API_KEY=${env:GEMINI_API_KEY}"
            ]
        }
    ]
}
```
