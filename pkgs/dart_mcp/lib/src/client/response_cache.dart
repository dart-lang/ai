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

  /// Elapsed stopwatch time when this entry expires.
  ///
  /// A [Duration] keeps expiry monotonic and is compared with the cache
  /// stopwatch, not the wall clock.
  final Duration expiresAt;
}

/// The `_meta` fields that change the answer to a cacheable request.
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
/// keyed by the request method, the parameters that change the answer, and
/// the per-request context the caller sent. A result is stored only while it
/// is complete, carries a positive `ttlMs` and carries a scope the schema
/// allows, and the answers to an [InputRequiredResult] stay out entirely. A
/// `ttlMs` past the configured maximum is clamped to that limit, since without
/// a bound a server could pin an answer for the life of the process.
///
/// https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching
final class _ClientResponseCache {
  int maxEntries = 512;
  Duration maxTtl = const Duration(hours: 24);

  final _entries = <_CacheKey, _CacheEntry>{};
  final _pending = <_CacheKey, Future<Result?>>{};

  /// The resource URIs updated while a `resources/read` was in flight, under
  /// the token of that read.
  final _updatedWhilePending = <Future<Result?>, Set<String>>{};
  final _clock = Stopwatch()..start();
  Duration _elapsedOffset = Duration.zero;

  /// Cache time is the live stopwatch reading plus this test-only offset.
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
    final cached = _cachedEntry(key);
    if (cached != null) return _copyMap(cached.result) as T;

    final pending = _pending[key];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The caller that started the request receives its error. This caller
        // still gets a chance to make a fresh request.
      }
      final cached = _cachedEntry(key);
      if (cached != null) return _copyMap(cached.result) as T;
    }

    late final Future<T> current;
    current = _requestAndStore<T>(key, send, () => current);
    _pending[key] = current;
    try {
      return await current;
    } finally {
      if (identical(_pending[key], current)) unawaited(_pending.remove(key));
      _updatedWhilePending.remove(current);
    }
  }

  _CacheEntry? _cachedEntry(_CacheKey key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.expiresAt.compareTo(_elapsed) > 0) return entry;
    _entries.remove(key);
    return null;
  }

  Future<T> _requestAndStore<T extends Result?>(
    _CacheKey key,
    Future<T> Function() send,
    Future<T> Function() current,
  ) async {
    final result = await send();
    final receivedAt = _elapsed;
    final pending = current();
    if (result == null || !identical(_pending[key], pending)) return result;

    final resultMap = result as Map<String, Object?>;
    final resultType = resultMap[Keys.resultType];
    final ttlMs = resultMap[Keys.ttlMs];
    final cacheScope = resultMap[Keys.cacheScope];
    // A server on an earlier revision leaves `resultType` out, and the
    // schema requires reading that as complete. `Result.resultType` reports
    // the same value. An [InputRequiredResult] carries the
    // fields the client retries with, so a result carrying them is interim
    // whatever it labels itself. A hint outside what the schema allows is
    // read as no hint at all, matching `CacheableResult`.
    if ((resultType != null && resultType != ResultTypes.complete) ||
        resultMap.containsKey(Keys.inputRequests) ||
        resultMap.containsKey(Keys.requestState) ||
        ttlMs is! int ||
        ttlMs <= 0 ||
        !CacheScope.values.any((scope) => scope.name == cacheScope)) {
      return result;
    }

    final ttl =
        ttlMs > maxTtl.inMilliseconds ? maxTtl : Duration(milliseconds: ttlMs);
    if (ttl <= Duration.zero || maxEntries == 0) return result;
    if (!_entries.containsKey(key) && _entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    // An answer that arrives after one of its own contents changed is already
    // out of date, and a read only learns its contents once it gets here.
    final updated = _updatedWhilePending[pending];
    if (updated != null && _carriesAny(resultMap, updated)) return result;
    // The TTL is added to the stopwatch reading captured when the response
    // arrived. Saturation keeps the monotonic deadline in range.
    final expiresAt = receivedAt + ttl;
    _entries[key] = _CacheEntry(_copyMap(resultMap), expiresAt);
    return result;
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
    // The notification can name a sub-resource of the one that was read, so a
    // result carrying that URI in its contents is stale as well.
    bool matches(_CacheKey key, _CacheEntry? entry) {
      if (key.methodName != ReadResourceRequest.methodName) return false;
      if (key.parameter == uri) return true;
      final contents = entry?.result[Keys.contents];
      return contents is List &&
          contents.any((content) => content is Map && content[Keys.uri] == uri);
    }

    _entries.removeWhere(matches);
    _pending.removeWhere((key, _) => matches(key, null));
    for (final MapEntry(key: pending, :value) in _pending.entries) {
      if (pending.methodName == ReadResourceRequest.methodName) {
        (_updatedWhilePending[value] ??= <String>{}).add(uri);
      }
    }
  }

  /// Whether [result] carries content for any URI in [uris].
  static bool _carriesAny(Map<String, Object?> result, Set<String> uris) {
    if (uris.isEmpty) return false;
    final contents = result[Keys.contents];
    return contents is List &&
        contents.any(
          (content) => content is Map && uris.contains(content[Keys.uri]),
        );
  }

  void clear() {
    _entries.clear();
    _pending.clear();
    _updatedWhilePending.clear();
  }

  /// The key [request] is cached under, or `null` when it is not cacheable.
  ///
  /// Each cacheable method names the parameters that change its answer, and
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
