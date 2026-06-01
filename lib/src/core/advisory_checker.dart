import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package_resolver.dart';

/// Checks for security advisories for packages using the OSV.dev API.
class AdvisoryChecker {
  final http.Client? _httpClient;

  AdvisoryChecker({http.Client? httpClient}) : _httpClient = httpClient;

  /// Checks for vulnerabilities for the given [packages] and
  /// [registryRepoCommits].
  ///
  /// Returns a map from package name to a list of vulnerability summaries.
  ///
  /// For each package, we check the lockfile to see if it was installed
  /// via git, and if so we will check based on that hash. Otherwise, we
  /// check using the pub ecosystem queries by name and version.
  Future<Map<String, List<String>>> checkAdvisories(
    List<ResolvedPackage> packages,
    String rootPath,
    Logger logger, {
    Map<String, String>? registryRepoCommits,
  }) async {
    final results = <String, List<String>>{};
    final queries = <Map<String, dynamic>>[];
    // Package names or git URIs that were queried.
    final queriedSources = <String>[];

    /// Queries for all the registry repositories.
    if (registryRepoCommits != null) {
      for (final entry in registryRepoCommits.entries) {
        queriedSources.add(entry.key);
        queries.add({'commit': entry.value});
      }
    }

    // Queries for all the git and hosted packages.
    final packagesInfo = await _readPubspecLockInfo(rootPath, logger);
    for (final package in packages) {
      final (:commit, :version) =
          packagesInfo[package.name] ?? (commit: null, version: null);
      final query = commit != null
          ? {'commit': commit}
          : version != null
              ? {
                  'package': {'name': package.name, 'ecosystem': 'Pub'},
                  'version': version
                }
              : null;

      if (query != null) {
        queries.add(query);
        queriedSources.add('package:${package.name}');
      }
    }

    if (queries.isEmpty) return results;

    try {
      final response = await (_httpClient?.post ?? http.post)(
          Uri.parse('https://api.osv.dev/v1/querybatch'),
          headers: {
            HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
          },
          body: jsonEncode({'queries': queries}));
      if (response.statusCode != 200) {
        logger.warning('''
Error checking for security advisories:
StatusCode: ${response.statusCode} (${response.reasonPhrase})
Content:
${response.body}
''');
        return results;
      }
      final data = jsonDecode(response.body) as Map<String, Object?>;
      final resultsList = data['results'] as List<Object?>?;

      if (resultsList == null) return results;

      for (var i = 0; i < resultsList.length; i++) {
        final result = resultsList[i] as Map<String, Object?>;
        final vulns = result['vulns'] as List<Object?>?;
        if (vulns != null && vulns.isNotEmpty) {
          final source = queriedSources[i];
          final summaries = <String>[];
          for (final vuln in vulns) {
            final vulnMap = vuln as Map<String, Object?>;
            final id = vulnMap['id'] as String;
            summaries.add('https://osv.dev/vulnerability/$id');
          }
          results[source] = summaries;
        }
      }
    } catch (e) {
      // Handle exception, maybe log it
      // For now, return empty results to not block installation on network error
    }

    return results;
  }

  /// Reads the pubspec.lock in [rootPath], extracting useful information.
  ///
  /// Returns a map from package name to a record of info.
  Future<Map<String, ({String? commit, String? version})>> _readPubspecLockInfo(
      String rootPath, Logger logger) async {
    final result = <String, ({String? commit, String? version})>{};
    final lockFile = File(p.join(rootPath, 'pubspec.lock'));
    if (!await lockFile.exists()) {
      logger.warning(
          'No pubspec.lock found, cannot check for security advisories '
          'in $rootPath. See https://github.com/dart-lang/ai/issues/487.');
      return result;
    }

    try {
      final content = await lockFile.readAsString();
      final yaml = loadYaml(content);
      if (yaml is! YamlMap) return result;

      final packages = yaml['packages'];
      if (packages is! YamlMap) return result;

      for (final entry in packages.entries) {
        final packageName = entry.key as String;
        final packageInfo = entry.value;
        if (packageInfo is! YamlMap) continue;
        final version = packageInfo['version'] as String?;
        String? commit;

        final source = packageInfo['source'] as String?;
        if (source == 'git') {
          final description = packageInfo['description'];
          if (description is YamlMap) {
            final resolvedRef = description['resolved-ref'] as String?;
            if (resolvedRef != null) {
              commit = resolvedRef;
            }
          }
        }
        result[packageName] = (commit: commit, version: version);
      }
    } catch (e) {
      // Ignore errors parsing lockfile
    }

    return result;
  }
}
