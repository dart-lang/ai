# Gemini Workspace Context

This is a living document describing the general structure of this repo and best practices, targeted specifically at coding agents. It should be actively kept up to date if any information is discovered to be out of date, or new features are added which would be relevant to have as context in the future.

## Project Overview

This repository contains a set of Dart packages for building AI-powered tools and applications. The core of the repository is the implementation of the Model Context Protocol (MCP), which allows AI models to interact with local development tools.

The two main packages are:

- **`dart_mcp`**: A Dart package for creating MCP (Model Context Protocol) servers and clients. It provides the foundational building blocks for communication between AI models and development tools.
- **`dart_mcp_server`**: An MCP server for Dart projects that exposes a variety of Dart and Flutter development tools to AI-assistant clients. This allows AI models to perform actions like running tests, formatting code, analyzing projects, and more.

The project is experimental and under active development.

## Code Structure

### `dart_mcp` package

This package provides the core infrastructure for MCP communication.

- **`lib/client.dart` & `lib/server.dart`**: These are the main entry points for creating MCP clients and servers. They export the `MCPClient` and `MCPServer` base classes.
- **`lib/stdio.dart`**: Provides a utility for creating a `StreamChannel` over standard I/O, which is the primary transport mechanism used for communication between the client and server.
- **`lib/src/api/api.dart`**: This is a crucial file that defines the entire MCP API as a set of Dart classes. It includes definitions for all requests, responses, and notifications, structured according to the MCP specification. This file is the source of truth for the data structures that are exchanged between the client and server.
- **`lib/src/client/client.dart`**: Contains the implementation of the `MCPClient`. This class is responsible for connecting to a server, sending requests, and handling responses and notifications. It can be extended with mixins to add support for client-side capabilities.
- **`lib/src/server/server.dart`**: Contains the implementation of the `MCPServer`. This is the base class that developers can extend to create their own MCP servers. It handles the initial handshake with the client and provides a framework for adding server-side capabilities through mixins.
- **`lib/src/shared.dart`**: Contains the `MCPBase` class, which encapsulates the common logic for JSON-RPC 2.0 communication, including registering method handlers, sending requests, and handling progress notifications.

#### Core Mixins (`dart_mcp`)

The `dart_mcp` package provides a set of mixins that add specific MCP capabilities to a client or server.

##### Client-Side Mixins (for `MCPClient`)

These are located in `lib/src/client/` and are mixed into an `MCPClient` implementation.

- **`RootsSupport`**: Manages the list of project root directories. It handles `listRoots` requests from the server and notifies the server whenever the list of roots changes. This is crucial for providing context to the server's tools.
- **`SamplingSupport`**: Allows the server to send prompts _to_ the client's LLM. The client is responsible for implementing `handleCreateMessage`, which should typically involve getting user consent before sending the prompt to the LLM and returning the response.
- **`ElicitationSupport`**: Handles requests from the server that require direct user input (e.g., asking a question, requesting a file path). The client must implement the `handleElicitation` method to define how it collects this input from the user.

##### Server-Side Mixins (for `MCPServer`)

These are located in `lib/src/server/` and are mixed into an `MCPServer` implementation.

- **`ToolsSupport`**: The core of most MCP servers. It allows you to `registerTool` and `unregisterTool`, exposing functions that the client's AI can call. It handles listing the available tools and invoking them when requested.
- **`ResourcesSupport`**: Manages exposing data and files to the client as "resources". You can `addResource`, `updateResource`, and `removeResource`. It also supports `ResourceTemplate`s for dynamic resources and handles client subscriptions to be notified of resource changes.
- **`PromptsSupport`**: Allows the server to provide a list of pre-defined prompts to the client. The client can then request a specific prompt by name, and the server will return the fully-formed prompt content.
- **`LoggingSupport`**: Provides a structured way for the server to send log messages to the client. It supports different logging levels, and the client can change the active level.
- **`CompletionsSupport`**: Adds the ability for the server to provide custom code-completion suggestions to the client.
- **`RootsTrackingSupport`**: A utility mixin for servers that works with `RootsSupport` on the client. It automatically tracks the client's project roots, updating its internal list whenever the client sends a notification that the roots have changed.
- **`ElicitationRequestSupport`**: The server-side counterpart to `ElicitationSupport`. It provides an `elicit` method that servers can use to request information from the user via the client.

### `dart_mcp_server` package

This package is a concrete implementation of an MCP server that exposes a rich set of tools for Dart and Flutter development.

- **`bin/main.dart`**: The main entry point for the server executable.
- **`lib/dart_mcp_server.dart`**: Exports the main `DartMCPServer` class.
- **`lib/src/server.dart`**: This is the core of the `dart_mcp_server` package. The `DartMCPServer` class extends `MCPServer` from the `dart_mcp` package and uses a series of mixins to add a wide range of tools. It also handles command-line argument parsing, logging, and analytics.
- **`lib/src/mixins/`**: This directory is where the implementations of the various tools are located. Each file is a mixin that adds a specific set of capabilities to the `DartMCPServer`. This is a great place to look to understand how a specific tool is implemented.
  - **`analyzer.dart`**: Provides tools for static analysis of Dart code.
  - **`dash_cli.dart`**: Provides tools related to the `dash` command-line tool.
  - **`dtd.dart`**: Implements support for the Dart Tooling Daemon (DTD), which allows the server to interact with running Dart and Flutter applications. This is used for features like hot reload and inspecting the widget tree.
  - **`prompts.dart`**: Implements support for prompts.
  - **`pub_dev_search.dart`**: Implements the `pub_dev_search` tool for searching for packages on pub.dev.
  - **`pub.dart`**: Provides tools for interacting with the Dart package manager (`pub`), such as adding and removing dependencies.
  - **`roots_fallback_support.dart`**: Provides a fallback for clients that don't fully support the `roots` capability.

## Building and Running

The packages in this repository are standard Dart packages. To use them, you can add them as dependencies in your `pubspec.yaml` file.

### Running the MCP Server

The `dart_mcp_server` can be run directly from the command line:

```bash
dart run pkgs/dart_mcp_server/bin/main.dart
```

However, it's intended to be run by an MCP client, such as the Gemini CLI.

### Running Tests

Tests can be run using the `dart test` command in each package's directory.

```bash
# To run tests for dart_mcp
(cd pkgs/dart_mcp && dart test)

# To run tests for dart_mcp_server
(cd pkgs/dart_mcp_server && dart test)
```

## Development Conventions

- **Code Style**: The project follows the standard Dart and Flutter team linting rules, enforced by the `dart_flutter_team_lints` package.
- **Testing**: The project has a suite of unit tests that use the `test` package. Tests are located in the `test` directory of each package. The tests for `dart_mcp_server` use a `TestHarness` to start a server and make requests to it.
- **Dependencies**: The project uses standard Dart package management with `pubspec.yaml` files.
- **Contributions**: The `CONTRIBUTING.md` file (which is currently a placeholder) would contain information about contributing to the project.
