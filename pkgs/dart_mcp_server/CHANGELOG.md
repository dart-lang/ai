# Dart SDK 3.8.0 - WP

* Handle relative paths under roots without trailing slashes.
* Fix executable paths for dart/flutter on windows.
* Pass the provided root instead of the resolved root for project type detection.
* Be more flexible about roots by comparing canonicalized paths.
* Create the working dir if it doesn't exist.
* Add the --platform and --empty arguments to the flutter create tool.
* Invoke dart/flutter in a more robust way.
* Remove qualifiedNames from the pub dev api search.
* Flutter/Dart create tool.
* Limit the tokens returned by the runtime errors tool/resource.
* Add RootsFallbackSupport mixin.
* Fix error handling around stream listeners.
* Add a 'pub-dev-search' mcp tool.
* Drop pubspec-parse, use yaml instead.
* Handle failing to listen to vm service streams during startup.
* Add tool for enabling/disabling the widget selector.
* Add a tool to get the active cursor location.
* Add hover tool support.
* Add a test command and project detection.
* Add signature_help tool.
* Add runtime errors resource and tool to clear errors.
* Require roots for all CLI tools.
* Require roots to be set for analyzer tools.
* Add debug logs for when DTD sees Editor.getDebugSessions get registered.
* Add tool annotations to tools.
* Implement a tool to resolve workspace symbols based on a query.
* Add a dart pub tool.
* Update analyze tool to use LSP, simplify tool.
* Add tool for getting the selected widget.
* Handle missing roots capability better.
* Add `get_widget_tree` tool.
* Add a tool for getting runtime errors.
* Add Dart CLI tool support.
* Add a hot reload tool.
* Add basic analysis support.
* Add the beginnings of a Dart tooling MCP server.
* Instruct clients to prefer MCP tools over running tools in the shell.
* Reduce output size of `run_tests` tool to save on input tokens.
