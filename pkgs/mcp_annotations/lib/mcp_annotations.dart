// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mcp_annotations;

/// Marks a top-level function or static method as an MCP tool.
///
/// The generator uses the annotation data to create a [Tool] description
/// and the corresponding handler code.
class MCPTool {
  const MCPTool({
    this.name,
    this.description,
    this.destructiveHint,
    this.idempotentHint,
    this.openWorldHint,
    this.readOnlyHint,
    this.title,
    this.parameters,
  });

  /// Override the default tool name (defaults to the Dart identifier).
  final String? name;

  /// Human-readable description shown to the LLM.
  final String? description;

  /// Optional hint fields forwarded to [ToolAnnotations].
  final bool? destructiveHint;
  final bool? idempotentHint;
  final bool? openWorldHint;
  final bool? readOnlyHint;
  final String? title;

  /// Optional rich metadata about individual parameters.
  ///
  /// When provided, the generator uses this to populate `title` and
  /// `description` on the generated JSON-Schema for the corresponding input
  /// field.  It is perfectly safe to omit or partially fill this list — any
  /// parameter without a matching entry just falls back to the simple schema
  /// based on its Dart type.
  final List<MCPParameter>? parameters;
}

/// Additional metadata for an individual parameter in an [MCPTool].
///
/// Only [name] is required; everything else is optional.
class MCPParameter {
  const MCPParameter({
    required this.name,
    this.title,
    this.description,
  });

  /// The Dart parameter identifier this metadata applies to.
  final String name;

  /// A short human-readable label to show in UIs.
  final String? title;

  /// Longer explanation of the parameter.
  final String? description;
}

/// Marks a class as an MCP server application. The generator will emit a concrete
/// [MCPServer] subclass and bootstrap code in a companion file.
class MCPServerApp {
  const MCPServerApp({
    required this.name,
    required this.version,
    this.instructions,
  });

  /// Name reported to the client.
  final String name;

  /// Version reported to the client.
  final String version;

  /// Optional usage instructions forwarded to the client.
  final String? instructions;
}
