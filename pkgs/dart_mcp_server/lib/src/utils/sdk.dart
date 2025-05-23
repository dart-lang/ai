// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  Sdk({required this.dartSdkPath, required this.flutterSdkPath});

  /// The path to the `dart` executable.
  String? get dartExecutablePath => dartSdkPath?.child('bin').child('dart');

  /// The path to the `flutter` executable.
  String? get flutterExecutablePath =>
      flutterSdkPath?.child('bin').child('flutter');
}

extension on String {
  String child(String path) => p.join(this, path);
}
