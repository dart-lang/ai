import 'package:test_descriptor/test_descriptor.dart' as d;

class Dependency {
  final String name;
  final String? path;
  const Dependency(this.name, {this.path});
}

d.FileDescriptor pubspec(
  String name, {
  String version = '1.0.0',
  List<Dependency> dependencies = const [],
  List<Dependency> devDependencies = const [],
  List<String>? workspace,
  String? resolution,
  String? publishTo,
  String? extra, // For melos blocks or other raw YAML
}) {
  final buffer = StringBuffer('''
name: $name
environment:
  sdk: ^3.10.0
version: $version
''');
  if (publishTo != null) {
    buffer.writeln('publish_to: $publishTo');
  }
  if (resolution != null) {
    buffer.writeln('resolution: $resolution');
  }
  if (workspace != null && workspace.isNotEmpty) {
    buffer.writeln('workspace:');
    for (final member in workspace) {
      buffer.writeln('  - $member');
    }
  }
  if (extra != null) {
    buffer.writeln(extra);
  }
  if (dependencies.isNotEmpty) {
    buffer.writeln('dependencies:');
    for (final dependency in dependencies) {
      final path = dependency.path ?? '../${dependency.name}';
      buffer.writeln('''
  ${dependency.name}:
    path: $path
''');
    }
  }
  if (devDependencies.isNotEmpty) {
    buffer.writeln('dev_dependencies:');
    for (final dependency in devDependencies) {
      final path = dependency.path ?? '../${dependency.name}';
      buffer.writeln('''
  ${dependency.name}:
    path: $path
''');
    }
  }
  return d.file('pubspec.yaml', buffer.toString());
}
