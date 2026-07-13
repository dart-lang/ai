// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

/// Parsed frontmatter from a skill file.
class SkillFrontmatter {
  /// The parsed metadata.internal field, defaults to false.
  final bool isInternal;

  /// The parsed name.
  final String name;

  SkillFrontmatter(this.name, {required this.isInternal});

  /// Extracts values from a parsed skill frontmatter [YamlDocument].
  factory SkillFrontmatter.fromYaml(YamlDocument document) {
    final mapContent = document.contents;
    if (mapContent is! YamlMap) {
      throw FormatException(
        'Expected a yaml map in the skill frontmatter',
        mapContent,
      );
    }
    final String name;
    if (mapContent['name'] case String parsedName) {
      name = parsedName;
    } else {
      throw FormatException('Expected a String name property', mapContent);
    }

    final YamlMap? metadata;
    if (mapContent['metadata'] case YamlMap? parsedMetadata) {
      metadata = parsedMetadata;
    } else {
      throw FormatException(
        'Expected a YamlMap or empty metadata property',
        mapContent,
      );
    }

    final bool isInternal;
    if (metadata?['internal'] case final bool parsedInternal) {
      isInternal = parsedInternal;
    } else {
      isInternal = false;
    }

    return SkillFrontmatter(name, isInternal: isInternal);
  }

  /// Parses the [SkillFrontmatter] from the full skill file content.
  factory SkillFrontmatter.fromSkillContent(String content, {Uri? sourceUri}) {
    if (!content.startsWith('---')) {
      throw FormatException('Skill must start with `---` frontmatter', content);
    }
    final frontMatterEnd = content.indexOf('---', 3);
    if (frontMatterEnd == -1) {
      throw FormatException(
        'Skill must have front matter ending delimiter ---',
        content,
      );
    }
    final yamlContent = content.substring(3, frontMatterEnd);
    return SkillFrontmatter.fromYaml(
      loadYamlDocument(yamlContent, sourceUrl: sourceUri),
    );
  }
}
