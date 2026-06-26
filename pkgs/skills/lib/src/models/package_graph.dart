import 'dart:convert';
import 'dart:io';

/// Typed wrapper for package_graph.json files.
///
/// Supports version 1 only.
extension type PackageGraph(Map<String, Object?> source) {
  /// Reads a [PackageGraph] from a [file].
  static Future<PackageGraph> fromFile(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content);
    if (json is Map<String, Object?>) {
      return PackageGraph(json);
    } else {
      throw FormatException(
        'Error parsing ${file.uri}: Expected a Map but got '
        '${json.runtimeType}',
      );
    }
  }

  /// All the packages that appear in this package graph.
  List<PackageInfo> get packages {
    final packages = source['packages'];
    if (packages is! List) {
      throw FormatException(
        'Expected `packages` key to be a List but got a '
        '${packages.runtimeType}',
      );
    }
    return packages.cast();
  }

  /// Names of all the root packages in the workspace.
  List<String> get roots {
    final roots = source['roots'];
    if (roots is! List) {
      throw FormatException(
        'Expected `roots` key to be a List but got a '
        '${roots.runtimeType}',
      );
    }
    return roots.cast();
  }

  /// The version of the package graph file.
  int get version {
    final version = source['version'];
    if (version is! int) {
      throw FormatException(
        'Expected `version` key to be an int but got a '
        '${version.runtimeType}',
      );
    }
    return version;
  }
}

/// Information about a package contained in the package_graph.json.
extension type PackageInfo(Map<String, Object?> source) {
  /// The name of the package.
  String get name {
    final name = source['name'];
    if (name is! String) {
      throw FormatException(
        'Expected `name` key to be a String but got a '
        '${name.runtimeType}',
      );
    }
    return name;
  }

  /// The version of the package.
  String? get version {
    final version = source['version'];
    if (version is! String?) {
      throw FormatException(
        'Expected `version` key to be a String? but got a '
        '${version.runtimeType}',
      );
    }
    return version;
  }

  /// The regular `dependencies` of this package.
  List<String> get dependencies {
    final deps = source['dependencies'];
    if (deps is! List) {
      throw FormatException(
        'Expected `dependencies` key to be a List but got a '
        '${deps.runtimeType}',
      );
    }
    return deps.cast();
  }

  /// The `dev_dependencies` of this package.
  List<String> get devDependencies {
    final devDeps = source['devDependencies'];
    if (devDeps is! List) {
      throw FormatException(
        'Expected `devDependencies` key to be a List but got a '
        '${devDeps.runtimeType}',
      );
    }
    return devDeps.cast();
  }
}
