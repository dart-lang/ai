import 'dart:io';

void main() {
  final skillsDir = Directory('plugins/skills');
  final targetDir = Directory('plugins/power-dart-flutter/steering');

  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }

  final List<String> mappings = [];

  for (final entity in skillsDir.listSync()) {
    if (entity is Directory) {
      final skillName = entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
      final skillFile = File('${entity.path}/SKILL.md');
      if (skillFile.existsSync()) {
        final content = skillFile.readAsStringSync();
        final parts = content.split('---');
        if (parts.length >= 3) {
          final frontmatter = parts[1];
          final body = parts.sublist(2).join('---').trim();
          final targetFile = File('${targetDir.path}/$skillName.md');
          targetFile.writeAsStringSync(body + '\n');
          print('Generated steering file for $skillName');

          final description = parseDescription(frontmatter);
          if (description.isNotEmpty) {
            mappings.add('- $description -> $skillName.md');
          } else {
            mappings.add('- Tasks related to $skillName -> $skillName.md');
          }
        } else {
          print('Warning: No frontmatter found for $skillName');
        }
      }
    }
  }

  mappings.sort();

  final powerFile = File('plugins/power-dart-flutter/POWER.md');
  if (powerFile.existsSync()) {
    final lines = powerFile.readAsLinesSync();
    final headerIndex = lines.indexWhere((l) => l.trim() == '# When to Load Steering Files');
    if (headerIndex != -1) {
      final newLines = lines.sublist(0, headerIndex + 1);
      for (final mapping in mappings) {
        newLines.add(mapping);
      }
      powerFile.writeAsStringSync(newLines.join('\n') + '\n');
      print('Updated POWER.md When to Load Steering Files section.');
    } else {
      print('Warning: "# When to Load Steering Files" section not found in POWER.md');
    }
  }
}

String parseDescription(String frontmatter) {
  final lines = frontmatter.split('\n');
  String? description;
  bool inDescription = false;
  List<String> descLines = [];

  for (var line in lines) {
    if (line.trim().startsWith('description:')) {
      final value = line.substring(line.indexOf(':') + 1).trim();
      if (value == '|-' || value == '|') {
        inDescription = true;
      } else {
        description = value;
        break;
      }
    } else if (inDescription) {
      if (line.startsWith(' ') || line.startsWith('\t') || line.isEmpty) {
        descLines.add(line.trim());
      } else {
        break;
      }
    }
  }

  if (inDescription) {
    description = descLines.join(' ');
  }

  if (description == null) return '';

  if (description.startsWith('"') && description.endsWith('"')) {
    description = description.substring(1, description.length - 1);
  } else if (description.startsWith("'") && description.endsWith("'")) {
    description = description.substring(1, description.length - 1);
  }

  return description.replaceAll(r'\"', '"').replaceAll(r"\'", "'").trim();
}
