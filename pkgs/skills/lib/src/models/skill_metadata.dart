import 'dart:io';

import 'package:yaml/yaml.dart';

/// Parsed representation of a SKILL.md file's frontmatter and body.
class SkillMetadata {
  final String name;
  final String description;
  final String body;
  final Map<String, dynamic> extraFields;

  const SkillMetadata({
    required this.name,
    required this.description,
    required this.body,
    this.extraFields = const {},
  });

  /// Parses a SKILL.md file from the given [file].
  static Future<SkillMetadata> parse(File file) async {
    final content = await file.readAsString();
    return parseContent(content);
  }

  /// Parses a SKILL.md from raw string [content].
  static SkillMetadata parseContent(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) {
      throw FormatException('SKILL.md must start with YAML frontmatter (---)');
    }

    final endIndex = trimmed.indexOf('---', 3);
    if (endIndex == -1) {
      throw FormatException('SKILL.md frontmatter is missing closing ---');
    }

    final frontmatterStr = trimmed.substring(3, endIndex).trim();
    final body = trimmed.substring(endIndex + 3).trim();

    final yaml = loadYaml(frontmatterStr);
    if (yaml is! YamlMap) {
      throw FormatException('SKILL.md frontmatter must be a YAML map');
    }

    final name = yaml['name'];
    final description = yaml['description'];

    if (name is! String || name.isEmpty) {
      throw FormatException(
        'SKILL.md frontmatter must contain a non-empty "name" field',
      );
    }
    if (description is! String || description.isEmpty) {
      throw FormatException(
        'SKILL.md frontmatter must contain a non-empty "description" field',
      );
    }

    final extra = <String, dynamic>{};
    for (final key in yaml.keys) {
      if (key != 'name' && key != 'description') {
        extra[key as String] = yaml[key];
      }
    }

    return SkillMetadata(
      name: name,
      description: description,
      body: body,
      extraFields: extra,
    );
  }

  /// Serializes this metadata back to SKILL.md format.
  String toSkillMd() {
    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('name: $name');
    buffer.writeln('description: $description');
    for (final entry in extraFields.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln('---');
    if (body.isNotEmpty) {
      buffer.writeln();
      buffer.write(body);
      if (!body.endsWith('\n')) {
        buffer.writeln();
      }
    }
    return buffer.toString();
  }
}
