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
/// If `key` in a `(String k, String v)` the next json structure must be a List
/// of maps, one of them having the property `k` with value `v`, recurse into
/// that map.
///
/// If at some point the types don't match throw a [FormatException].
///
/// Returns the result as a [T].
T dig<T>(dynamic json, List<dynamic> path) {
  var i = 0;
  String currentPath() => path.take(i).map((i) => '[$i]').join('');
  for (; i < path.length; i++) {
    outer:
    switch (path[i]) {
      case final String key:
        if (json is! Map) {
          throw FormatException('Expected a map at ${currentPath()}');
        }
        json = json[key];
      case final int key:
        if (json is! List) {
          throw FormatException('Expected a map at ${currentPath()}');
        }
        json = json[key];
      case (final String key, final String value):
        if (json is! List) {
          throw FormatException('Expected a map at ${currentPath()}');
        }
        final t = json;
        for (var j = 0; j < t.length; j++) {
          final element = t[j];
          if (element is! Map) {
            throw FormatException('Expected a map at ${currentPath()}[$j]');
          }
          if (element[key] == value) {
            json = element;
            break outer;
          }
        }
      case final key:
        throw ArgumentError('Bad key $key in', 'path');
    }
  }

  if (json is! T) throw FormatException('Unexpected value at $currentPath()');
  return json;
}
