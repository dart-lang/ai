// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

/// An optionally-sized icon that can be displayed in a user interface.
extension type Icon.fromMap(Map<String, Object?> _value) {
  factory Icon({
    required String src,
    String? mimeType,
    List<String>? sizes,
    IconTheme? theme,
  }) {
    return Icon.fromMap({
      'src': src,
      if (mimeType != null) 'mimeType': mimeType,
      if (sizes != null) 'sizes': sizes,
      if (theme != null) 'theme': theme.name,
    });
  }

  /// A standard URI pointing to an icon resource.
  String get src {
    final src = _value['src'] as String?;
    if (src == null) {
      throw ArgumentError('Missing required src field in $Icon');
    }
    return src;
  }

  /// Optional MIME type override if the source MIME type is missing or generic.
  String? get mimeType => _value['mimeType'] as String?;

  /// Optional array of strings that specify sizes at which the icon can be
  /// used.
  List<String>? get sizes => (_value['sizes'] as List?)?.cast<String>();

  /// Optional specifier for the theme this icon is designed for.
  IconTheme? get theme {
    final theme = _value['theme'] as String?;
    if (theme == null) return null;
    return IconTheme.values.firstWhere((value) => value.name == theme);
  }
}

/// The theme that an icon is designed for.
enum IconTheme { light, dark }
