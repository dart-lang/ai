// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

/// A wrapper class around [Process] that allows CLI commands ran by MCP server
/// tools to be easily tested.
class ProcessManager {
  const ProcessManager();

  /// Starts a process and runs it non-interactively to completion.
  ///
  /// This is a wrapper around the [Process.run] method.
  Future<ProcessResult> run(CliCommand command) {
    return Process.run(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: command.environment,
      includeParentEnvironment: command.includeParentEnvironment,
      runInShell: command.runInShell,
      stdoutEncoding: command.stdoutEncoding,
      stderrEncoding: command.stderrEncoding,
    );
  }
}

/// A data class representing a command to be run in a [Process].
class CliCommand {
  CliCommand({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.runInShell = false,
    this.stdoutEncoding = systemEncoding,
    this.stderrEncoding = systemEncoding,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;
  final Encoding? stdoutEncoding;
  final Encoding? stderrEncoding;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CliCommand &&
        other.executable == executable &&
        other.arguments == arguments &&
        other.workingDirectory == workingDirectory &&
        other.environment == environment &&
        other.includeParentEnvironment == includeParentEnvironment &&
        other.runInShell == runInShell &&
        other.stdoutEncoding == stdoutEncoding &&
        other.stderrEncoding == stderrEncoding;
  }

  @override
  int get hashCode {
    return executable.hashCode ^
        arguments.hashCode ^
        workingDirectory.hashCode ^
        environment.hashCode ^
        includeParentEnvironment.hashCode ^
        runInShell.hashCode ^
        stdoutEncoding.hashCode ^
        stderrEncoding.hashCode;
  }
}
