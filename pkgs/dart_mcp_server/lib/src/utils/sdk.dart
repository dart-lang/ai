// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// An interface class that provides a single getter of type [Sdk].
///
/// This provides information about the Dart and Flutter sdks, if available.
abstract interface class SdkSupport {
  Sdk get sdk;
}

/// Information about the Dart and Flutter SDKs, if available.
class Sdk {
  /// The path to the root of the Dart SDK.
  final String? dartSdkPath;

  /// The path to the root of the Flutter SDK.
  final String? flutterSdkPath;

  Sdk({this.dartSdkPath, this.flutterSdkPath});

  /// Creates an [Sdk] from the path to the Dart SDK.
  ///
  /// If no [dartSdkPath] is given, this will attempt to find one using
  /// [Platform.resolvedExecutable], assuming that is the `dart` binary
  /// under the `bin` dir of a Dart SDK.
  ///
  /// Validates that the path is valid by checking for the `version` file.
  ///
  /// If no [flutterSdkPath] is given, this will search up from the resolved
  /// Dart SDK path to see if it is nested inside a Flutter SDK.
  factory Sdk.find({String? dartSdkPath, String? flutterSdkPath}) {
    // Assume that we are running from the Dart SDK bin dir if not given any
    // other configuration.
    dartSdkPath ??= p.dirname(p.dirname(Platform.resolvedExecutable));

    final versionFile = dartSdkPath.child('version');
    if (!File(versionFile).existsSync()) {
      throw ArgumentError('Invalid Dart SDK path: $dartSdkPath');
    }

    // Check if this is nested inside a Flutter SDK.
    if (dartSdkPath.parent case final cacheDir
        when cacheDir.basename == 'cache' && flutterSdkPath == null) {
      if (cacheDir.parent case final binDir when binDir.basename == 'bin') {
        final flutterExecutable = binDir.child(
          'flutter${Platform.isWindows ? '.bat' : ''}',
        );
        if (File(flutterExecutable).existsSync()) {
          flutterSdkPath = binDir.parent;
        }
      }
    }

    return Sdk(dartSdkPath: dartSdkPath, flutterSdkPath: flutterSdkPath);
  }

  /// The path to the `dart` executable.
  ///
  /// Throws an [ArgumentError] if [dartSdkPath] is `null`.
  String get dartExecutablePath =>
      dartSdkPath
          ?.child('bin')
          .child('dart${Platform.isWindows ? '.exe' : ''}') ??
      (throw ArgumentError(
        'Dart SDK location unknown, try setting the DART_SDK environment '
        'variable.',
      ));

  /// The path to the `flutter` executable.
  ///
  /// Throws an [ArgumentError] if [flutterSdkPath] is `null`.
  String get flutterExecutablePath =>
      flutterSdkPath
          ?.child('bin')
          .child('flutter${Platform.isWindows ? '.bat' : ''}') ??
      (throw ArgumentError(
        'Flutter SDK location unknown. To work on flutter projects, you must '
        'spawn the server using `dart` from the flutter SDK and not a Dart '
        'SDK, or set a FLUTTER_SDK environment variable.',
      ));
}

extension on String {
  String get basename => p.basename(this);
  String child(String path) => p.join(this, path);
  String get parent => p.dirname(this);
}
