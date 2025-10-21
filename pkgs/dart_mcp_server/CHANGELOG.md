# 0.1.1 (Dart SDK 3.10.0) - WIP

- Change tools that accept multiple roots to not return immediately on the first
  failure.
- Add failure reason field to analytics events so we can know why tool calls are
  failing.
- Add a flutter_driver command for executing flutter driver commands on a device.
- Allow for multiple package arguments to `pub add` and `pub remove`.
- Require dart_mcp version 0.3.1.
- Add support for the flutter_driver screenshot command.
- Change the widget tree to the full version instead of the summary. The summary
  tends to hide nested text widgets which makes it difficult to find widgets
  based on their text values.
- Add an `--exclude-tool` command line flag to exclude tools by name.
- Add the abillity to limit the output of `analyze_files` to a set of paths.
- Stop reporting non-zero exit codes from command line tools as tool errors.
- Add descriptions for pub tools, add support for `pub deps` and `pub outdated`.
- Fix a bug in hot_reload ([#290](https://github.com/dart-lang/ai/issues/290)).
- Add the `list_devices`, `launch_app`, `get_app_logs`, and `list_running_apps`
  tools for running Flutter apps.
- Add the `hot_restart` tool for restarting running Flutter apps.
- Add extra log output to failed launches, and allow AI to specify the maxLines
  of log output.
- Convert `launch_app` to use `--machine` output to capture the DTD URI.

# 0.1.0 (Dart SDK 3.9.0)

- Add documentation/homepage/repository links to pub results.
- Handle relative paths under roots without trailing slashes.
- Fix executable paths for dart/flutter on windows.
- Pass the provided root instead of the resolved root for project type detection.
- Be more flexible about roots by comparing canonicalized paths.
- Create the working dir if it doesn't exist.
- Add the --platform and --empty arguments to the flutter create tool.
- Invoke dart/flutter in a more robust way.
- Remove qualifiedNames from the pub dev api search.
- Flutter/Dart create tool.
- Limit the tokens returned by the runtime errors tool/resource.
- Add RootsFallbackSupport mixin.
- Fix error handling around stream listeners.
- Add a 'pub-dev-search' mcp tool.
- Drop pubspec-parse, use yaml instead.
- Handle failing to listen to vm service streams during startup.
- Add tool for enabling/disabling the widget selector.
- Add a tool to get the active cursor location.
- Add hover tool support.
- Add a test command and project detection.
- Add signature_help tool.
- Add runtime errors resource and tool to clear errors.
- Require roots for all CLI tools.
- Require roots to be set for analyzer tools.
- Add debug logs for when DTD sees Editor.getDebugSessions get registered.
- Add tool annotations to tools.
- Implement a tool to resolve workspace symbols based on a query.
- Add a dart pub tool.
- Update analyze tool to use LSP, simplify tool.
- Add tool for getting the selected widget.
- Handle missing roots capability better.
- Add `get_widget_tree` tool.
- Add a tool for getting runtime errors.
- Add Dart CLI tool support.
- Add a hot reload tool.
- Add basic analysis support.
- Add the beginnings of a Dart tooling MCP server.
- Instruct clients to prefer MCP tools over running tools in the shell.
- Reduce output size of `run_tests` tool to save on input tokens.
- Add `--log-file` argument to log all protocol traffic to a file.
- Improve error text for failed DTD connections as well as the tool description.
- Add support for injecting an `Analytics` instance to track usage.
- Listen to the new DTD `ConnectedApp` service instead of the `Editor.DebugSessions`
  service, when available.
- Screenshot tool disabled until
  https://github.com/flutter/flutter/issues/170357 is resolved.
- Add `arg_parser.dart` public library with minimal deps to be used by the dart tool.
