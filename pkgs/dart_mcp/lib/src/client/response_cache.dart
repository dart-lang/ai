// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'client.dart';

final class _CacheKey {
  const _CacheKey(this.methodName, this.parameter, this.context);

  final String methodName;
  final Object? parameter;
  final Map<String, Object?>? context;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.methodName == methodName &&
      other.parameter == parameter &&
      const DeepCollectionEquality().equals(other.context, context);

  @override
  int get hashCode => Object.hash(
    methodName,
    parameter,
    const DeepCollectionEquality().hash(context),
  );
}

final class _CacheEntry {
  const _CacheEntry(this.result, this.expiresAt);

  final Map<String, Object?> result;
  final Duration expiresAt;
}

/// The `_meta` fields which change the answer to a cacheable request.
///
/// A request carrying any other field is sent to the server, since this
/// package cannot tell whether that field changes the answer.
const _contextKeys = {
  Keys.protocolVersionMeta,
  Keys.clientCapabilitiesMeta,
  Keys.clientInfoMeta,
  Keys.logLevelMeta,
};

/// The cache behind [ServerConnection.sendRequest].
///
/// Holds the results of the six operations the 2026-07-28 caching rules name,
/// keyed by the request method, the parameters which change the answer, and
/// the per-request context the caller sent. A result is stored only while it
/// is complete, carries a positive `ttlMs` and carries a scope the schema
/// allows, and the answers to an [InputRequiredResult] stay out entirely. A
/// `ttlMs` past a day is clamped to a day. Without that a server could pin an
/// answer for the life of the process, and a value large enough to overflow a
/// [Duration] would write an entry that is already stale.
///
/// https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching
final class _ClientResponseCache {
  static const _maxEntries = 512;
  static const _maxTtl = Duration(hours: 24);

  final _entries = <_CacheKey, _CacheEntry>{};
  final _pending = <_CacheKey, Object>{};
  final _clock = Stopwatch()..start();
  Duration _elapsedOffset = Duration.zero;

  Duration get _elapsed => _clock.elapsed + _elapsedOffset;

  Future<T> sendRequest<T extends Result?>(
    String methodName,
    Request? request,
    Future<T> Function() send,
  ) async {
    final requestMap = request as Map<String, Object?>?;
    final meta = requestMap?[Keys.meta];
    final metaMap = meta is Map<String, Object?> ? meta : null;
    final cacheRequest =
        requestMap == null || metaMap == null
            ? requestMap
            : ({...requestMap}..remove(Keys.meta));
    final key =
        metaMap != null && !metaMap.keys.every(_contextKeys.contains)
            ? null
            : _keyFor(methodName, cacheRequest, _contextOf(metaMap));

    try {
      return await (key == null ? send() : _sendAndStore<T>(key, send));
    } on RpcException catch (error) {
      if (error.code == error_code.INVALID_PARAMS &&
          cacheRequest?.containsKey(Keys.cursor) == true) {
        invalidateMethod(methodName);
      }
      rethrow;
    }
  }

  Future<T> _sendAndStore<T extends Result?>(
    _CacheKey key,
    Future<T> Function() send,
  ) async {
    final entry = _entries[key];
    if (entry != null) {
      if (entry.expiresAt.compareTo(_elapsed) > 0) {
        return _copyMap(entry.result) as T;
      }
      _entries.remove(key);
    }

    final token = Object();
    _pending[key] = token;
    try {
      final result = await send();
      final receivedAt = _elapsed;
      if (result == null || _pending[key] != token) return result;

      final resultMap = result as Map<String, Object?>;
      final resultType = resultMap[Keys.resultType];
      final ttlMs = resultMap[Keys.ttlMs];
      final cacheScope = resultMap[Keys.cacheScope];
      // A server on an earlier revision leaves `resultType` out, and the
      // schema requires reading that as complete, which is what
      // `Result.resultType` reports. An [InputRequiredResult] carries the
      // fields the client retries with, so a result carrying them is interim
      // whatever it labels itself. A hint outside what the schema allows is
      // read as no hint at all, the way `CacheableResult` reads it.
      if ((resultType != null && resultType != ResultTypes.complete) ||
          resultMap.containsKey(Keys.inputRequests) ||
          resultMap.containsKey(Keys.requestState) ||
          ttlMs is! int ||
          ttlMs <= 0 ||
          !CacheScope.values.any((scope) => scope.name == cacheScope)) {
        return result;
      }

      final ttl =
          ttlMs > _maxTtl.inMilliseconds
              ? _maxTtl
              : Duration(milliseconds: ttlMs);
      if (!_entries.containsKey(key) && _entries.length >= _maxEntries) {
        _entries.remove(_entries.keys.first);
      }
      _entries[key] = _CacheEntry(_copyMap(resultMap), receivedAt + ttl);
      return result;
    } finally {
      if (_pending[key] == token) _pending.remove(key);
    }
  }

  /// The values from [meta] which change the answer to a cacheable request.
  Map<String, Object?>? _contextOf(Map<String, Object?>? meta) {
    if (meta == null) return null;
    final context = <String, Object?>{
      for (final key in _contextKeys)
        if (meta.containsKey(key)) key: _copyValue(meta[key]),
    };
    return context.isEmpty ? null : context;
  }

  void invalidateMethod(String methodName) {
    _entries.removeWhere((key, _) => key.methodName == methodName);
    _pending.removeWhere((key, _) => key.methodName == methodName);
  }

  void invalidateResource(String uri) {
    bool matches(_CacheKey key) =>
        key.methodName == ReadResourceRequest.methodName &&
        key.parameter == uri;
    _entries.removeWhere((key, _) => matches(key));
    _pending.removeWhere((key, _) => matches(key));
  }

  void clear() {
    _entries.clear();
    _pending.clear();
  }

  /// The key [request] is cached under, or `null` when it is not cacheable.
  ///
  /// Each cacheable method names the parameters which change its answer, and
  /// a request carrying anything else gets no key. That is what keeps the
  /// retry of an [InputRequiredResult] out: the schema says a request carrying
  /// `inputResponses` or `requestState` must not be cached, since it depends
  /// on inputs no key covers, and such a request never matches one of these
  /// shapes.
  _CacheKey? _keyFor(
    String methodName,
    Map<String, Object?>? request,
    Map<String, Object?>? context,
  ) => switch (methodName) {
    DiscoverRequest.methodName =>
      request == null || request.isEmpty
          ? _CacheKey(methodName, null, context)
          : null,
    ListPromptsRequest.methodName ||
    ListResourcesRequest.methodName ||
    ListResourceTemplatesRequest.methodName ||
    ListToolsRequest.methodName => _listKey(methodName, request, context),
    ReadResourceRequest.methodName => _readResourceKey(
      methodName,
      request,
      context,
    ),
    _ => null,
  };

  _CacheKey? _listKey(
    String methodName,
    Map<String, Object?>? request,
    Map<String, Object?>? context,
  ) {
    if (request == null || request.isEmpty) {
      return _CacheKey(methodName, null, context);
    }
    final cursor = request[Keys.cursor];
    if (request.length != 1 || cursor is! String) return null;
    return _CacheKey(methodName, cursor, context);
  }

  _CacheKey? _readResourceKey(
    String methodName,
    Map<String, Object?>? request,
    Map<String, Object?>? context,
  ) {
    if (request == null) return null;
    final uri = request[Keys.uri];
    if (request.length != 1 || uri is! String) return null;
    return _CacheKey(methodName, uri, context);
  }
}

Map<String, Object?> _copyMap(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _copyValue(entry.value),
};

Object? _copyValue(Object? value) {
  if (value is Map<String, Object?>) return _copyMap(value);
  if (value is Map<Object?, Object?>) {
    return <Object?, Object?>{
      for (final entry in value.entries) entry.key: _copyValue(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _copyValue(item)];
  }
  return value;
}
