// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

/// A kind of source that `metadata.install-from` can name.
enum InstallSource { git, package }

/// Parsed frontmatter from a skill file.
class SkillFrontmatter {
  /// The parsed metadata.internal field, defaults to false.
  final bool isInternal;

  /// The sources that may install this skill, from the space separated
  /// metadata.install-from field.
  ///
  /// Holds every [InstallSource] when the field is absent. Unknown values are
  /// ignored.
  final Set<InstallSource> installFrom;

  /// The parsed name.
  final String name;

  SkillFrontmatter(
    this.name, {
    required this.isInternal,
    required this.installFrom,
  });

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

    final installFrom = switch (metadata?['install-from']) {
      null => InstallSource.values.toSet(),
      String sources => _parseInstallSources(sources),
      _ => throw FormatException(
        'Expected a String install-from metadata property',
        mapContent,
      ),
    };

    return SkillFrontmatter(
      name,
      isInternal: isInternal,
      installFrom: installFrom,
    );
  }

  static Set<InstallSource> _parseInstallSources(String sources) {
    final sourcesByName = InstallSource.values.asNameMap();
    return {for (final word in sources.split(' ')) ?sourcesByName[word]};
  }

  /// Matches a `---` line, allowing trailing whitespace.
  static final _closingDelimiter = RegExp(r'^---[ \t]*$', multiLine: true);

  /// Parses the [SkillFrontmatter] from the full skill file content.
  factory SkillFrontmatter.fromSkillContent(String content, {Uri? sourceUri}) {
    if (!content.startsWith('---')) {
      throw FormatException('Skill must start with `---` frontmatter', content);
    }
    // The closing delimiter is a line of its own, so a `---` inside a value
    // (for example in the description) does not end the front matter.
    final frontMatterEnd = _closingDelimiter.firstMatch(content.substring(3));
    if (frontMatterEnd == null) {
      throw FormatException(
        'Skill must have front matter ending delimiter ---',
        content,
      );
    }
    final yamlContent = content.substring(3, 3 + frontMatterEnd.start);
    return SkillFrontmatter.fromYaml(
      loadYamlDocument(yamlContent, sourceUrl: sourceUri),
    );
  }
}
