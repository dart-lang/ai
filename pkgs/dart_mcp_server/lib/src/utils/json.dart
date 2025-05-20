// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Utility for indexing json data structures.
///
/// Each element of [path] should be a `String`, `int` or `(String, String)`.
///
/// For each element `key` of [path], recurse into [json].
///
/// If the `key` is a String, the next json structure should be a Map, and have
/// `key` as a property. Recurse into that property.
///
/// If `key` is an `int`, the next json structure must be a List, with that
/// index. Recurse into that index.
///
/// If `key` is a `(String k, String v)` the next json structure must be a List
/// of maps, one of them having the property `k` with value `v`, recurse into
/// that map.
///
/// If at some point the types don't match throw a [FormatException].
///
/// Returns the result as a [T].
T dig<T>(dynamic json, List<Object> path) {
  var i = 0;
  String currentElementType() => switch (json) {
    Null _ => 'null',
    num _ => 'a number',
    String _ => 'a string',
    List _ => 'a list',
    Map _ => 'a map',
    _ => throw ArgumentError('Bad json'),
  };
  String currentPath() =>
      i == 0 ? 'root' : path.sublist(0, i).map((i) => '[$i]').join('');
  for (; i < path.length; i++) {
    outer:
    switch (path[i]) {
      case final String key:
        if (json is! Map) {
          throw FormatException(
            'Expected a map at ${currentPath()}. '
            'Found ${currentElementType()}.',
          );
        }
        json = json[key];
      case final int key:
        if (json is! List) {
          throw FormatException(
            'Expected a list at ${currentPath()}. '
            'Found ${currentElementType()}.',
          );
        }
        if (key >= json.length) {
          throw FormatException(
            'Expected at least ${key + 1} element(s) at ${currentPath()}. '
            'Found only ${json.length} element(s)',
          );
        }
        json = json[key];
      case (final String key, final String value):
        if (json is! List) {
          throw FormatException(
            'Expected a list at ${currentPath()}. '
            'Found ${currentElementType()}.',
          );
        }
        final t = json;
        for (var j = 0; j < t.length; j++) {
          final element = t[j];
          if (element is! Map) {
            json = element;
            throw FormatException(
              'Expected a map at ${currentPath()}[$j]. '
              'Found ${currentElementType()}.',
            );
          }
          if (element[key] == value) {
            json = element;
            break outer;
          }
        }
        throw FormatException(
          'No element with $key=$value at ${currentPath()}',
        );
      case final key:
        throw ArgumentError('Bad key $key in', 'path');
    }
  }

  if (json is! T) {
    final targetTypeName = switch (T) {
      const (int) => 'an int',
      const (double) => 'a number',
      const (num) => 'a number',
      const (String) => 'a string',
      const (List) => 'a list',
      const (Map) => 'a map',
      const (List<Object?>) => 'a list',
      const (Map<String, Object?>) => 'a map',
      const (Map<String, dynamic>) => 'a map',
      const (Null) => 'null',
      _ => throw ArgumentError('$T is not a json type'),
    };
    throw FormatException(
      'Expected $targetTypeName at ${currentPath()}. '
      'Found ${currentElementType()}.',
    );
  }
  return json;
}
