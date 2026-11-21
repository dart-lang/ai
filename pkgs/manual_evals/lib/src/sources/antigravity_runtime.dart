// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The conventions of the tools of agents built on the Antigravity runtime,
/// and the text the runtime writes into transcripts.
///
/// Tool results and runtime messages are text written for the model, not
/// structured fields, so this is the part of the transcript format most likely
/// to change. `tool/check_transcript_format.dart` reports some of the changes.
/// Supporting another agent's tools means providing its equivalents of these.
library;

// Tools and their arguments.

/// The names of the arguments that tools take for the command line they run.
const commandArguments = ['CommandLine'];

/// The names of the arguments that tools take for a search query.
const queryArguments = ['Query'];

/// The names of the arguments that tools take for the file or directory they
/// act on, in order of preference.
const pathArguments = [
  'Path',
  'AbsolutePath',
  'TargetFile',
  'SearchPath',
  'DirectoryPath',
];

/// The tools that write or edit the file named by their path argument.
const fileEditingTools = {
  'edit_file',
  'multi_replace_file_content',
  'replace_file_content',
  'write_file',
  'write_to_file',
};

/// The tool that calls lazily loaded MCP tools.
///
/// Its [mcpServerArgument] and [mcpToolArgument] name the MCP tool. Directly
/// called MCP tools are named `mcp_<server>_<tool>`.
const mcpProxyTool = 'call_mcp_tool';

/// The argument of [mcpProxyTool] that names the MCP server.
const mcpServerArgument = 'ServerName';

/// The argument of [mcpProxyTool] that names the MCP tool.
const mcpToolArgument = 'ToolName';

// Tool results.

/// The prefix of the result of a tool call that failed.
const errorResultPrefix = 'Error:';

/// Matches a timestamp line at the start of a tool result, for example
/// `Created At: 2026-10-29T23:48:50Z`.
final timestampLinePattern = RegExp(
  r'^(?:Created|Completed) At: .*$',
  multiLine: true,
);

/// Returns the ID of the background task that a tool call is running in, from
/// the call's [result], or `null` if it isn't running in the background.
///
/// The task reports the call's final result in a later runtime message (see
/// [runtimeMessages] and [taskResult]).
String? backgroundTaskId(String result) =>
    _backgroundTaskPattern.firstMatch(result)?[1];

final _backgroundTaskPattern = RegExp(
  r'^Tool is running as a background task with task id: (\S+)[ \t]*$',
  multiLine: true,
);

/// Returns the exit code that the header of a command's [result] reports, if
/// any.
///
/// Only the header is searched, so that output that happens to contain the
/// same text isn't mistaken for it.
int? reportedExitCode(String result) {
  final headerEnd = _outputHeaderPattern.firstMatch(result)?.start;
  final header = headerEnd == null ? result : result.substring(0, headerEnd);
  return int.tryParse(_exitCodePattern.firstMatch(header)?[1] ?? '');
}

/// Returns the output in a tool [result], without the header that precedes a
/// command's output, trimmed.
String toolOutput(String result) {
  final outputStart = _outputHeaderPattern.firstMatch(result)?.end;
  final output = outputStart == null
      ? result.replaceAll(_headerLinePattern, '')
      : result.substring(outputStart);
  return output.trim();
}

/// Matches the line reporting a command's exit code, for example
/// `Command exited with code 1.`
final _exitCodePattern = RegExp(
  r'^(?:The c|C)ommand exited with code (-?\d+)',
  multiLine: true,
);

/// Matches the line that ends the header of a command's result.
final _outputHeaderPattern = RegExp(
  r'^(?:Command )?[Oo]utput:',
  multiLine: true,
);

/// Matches a line of the header of a command's result.
final _headerLinePattern = RegExp(
  r'^(?:(?:Created|Completed) At: .*|(?:The c|C)ommand exited with code .*)'
  r'(?:\r?\n|$)',
  multiLine: true,
);

// Runtime messages.

/// A message delivered to a conversation by the runtime, for example from a
/// background task or another agent.
typedef RuntimeMessage = ({String sender, String text});

/// Returns the runtime messages in the [content] of a system message step.
///
/// Each message's text runs to the start of the next one.
Iterable<RuntimeMessage> runtimeMessages(String content) sync* {
  for (final text in content.split(_messagePrefix).skip(1)) {
    if (_messageSenderPattern.firstMatch(text)?[1] case final sender?) {
      yield (sender: sender, text: text);
    }
  }
}

/// The prefix of each runtime message.
const _messagePrefix = '[Message] ';

/// Matches the sender at the start of a message, after its [_messagePrefix].
final _messageSenderPattern = RegExp(r'^timestamp=\S+ sender=(\S+)');

/// Returns the content of a runtime message's [text], or `null` if it has
/// none.
String? messageContent(String text) {
  final start = text.indexOf(_contentMarker);
  return start == -1
      ? null
      : _stripMessageTrailer(text.substring(start + _contentMarker.length));
}

const _contentMarker = 'content=';

/// How a background task ended.
enum TaskEnd { finished, failed, canceled }

/// The final result of a background task.
typedef TaskResult = ({TaskEnd end, String result});

/// Returns the final result that a background task reports in a runtime
/// message's [text], or `null` if the message doesn't report one.
TaskResult? taskResult(String text) {
  final match = _taskResultPattern.firstMatch(text);
  if (match == null) return null;
  return (
    end: switch (match[1]) {
      'failed' => TaskEnd.failed,
      'was canceled' => TaskEnd.canceled,
      _ => TaskEnd.finished,
    },
    result: _stripMessageTrailer(match[2]!),
  );
}

/// Matches a background task message that reports the task's result, for
/// example `content=Task id "<id>" finished with result:`.
final _taskResultPattern = RegExp(
  r'content=Task id "[^"\n]*" (finished|failed|was canceled) with result:'
  r'(.*)',
  dotAll: true,
);

/// Returns [text] without the link to the task log and the closing tag that
/// end a message, trimmed.
String _stripMessageTrailer(String text) =>
    text.replaceFirst(_messageTrailerPattern, '').trim();

final _messageTrailerPattern = RegExp(
  r'(?:\s*\nLog: [^\n]*)?(?:\s*</SYSTEM_MESSAGE>)?\s*$',
);
