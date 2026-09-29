import 'dart:collection';
import 'dart:convert';
import 'dart:developer';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../network/network_base_url_resolver.dart';
import '../network/network_service_type.dart';
import 'hive_initializer.dart';

class CacheManager {
  static final CacheManager _instance = CacheManager._internal();

  factory CacheManager() => _instance;

  CacheManager._internal();

  /// Every key is namespaced by the environment the data came from, so a
  /// response cached against staging can never be served to a build pointing
  /// at production — or at a backend developer's machine. Switching the base
  /// url simply misses the cache instead of showing another server's data.
  ///
  /// Overridable for tests, which have no resolved base url.
  @visibleForTesting
  static String Function() cacheScopeResolver =
      () => NetworkBaseUrlResolver.resolve(NetworkServiceType.chat);

  // Memory cache with LRU eviction
  final _memoryCache = <String, CacheEntry>{};
  static const _maxMemoryItems = 100; // Prevent memory overuse

  // Hive box for persistent storage
  Box<String>? _cacheBox;
  Box<Map>? _metadataBox;
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    if (_cacheBox != null && _metadataBox != null) return Future.value();
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      await HiveInitializer.ensureInitialized();
      _cacheBox = await Hive.openBox<String>('api_cache');
      _metadataBox = await Hive.openBox<Map>('cache_metadata');
    } catch (_) {
      _initFuture = null; // allow retry on failure
      rethrow;
    }
  }

  Box<String> get _cache => _cacheBox!;
  Box<Map> get _metadata => _metadataBox!;

  // ======================
  // CORE CACHE OPERATIONS
  // ======================

  Future<void> cacheResponse({
    required String endpoint,
    required Map<String, dynamic> data,
    Map<String, dynamic>? params,
    Duration? maxAge,
  }) async {
    await _ensureInitialized();
    final combinedKey = _generateKey(endpoint, params); // cacheKey, originalKey
    final expiresAt = maxAge != null
        ? DateTime.now().add(maxAge).millisecondsSinceEpoch
        : null;

    // final entry = {
    //   //'data': data,
    //   'timestamp': DateTime.now().millisecondsSinceEpoch,
    //   'originalKey': combinedKey.$2, // saved originalKey
    //   if (expiresAt != null) 'expiresAt': expiresAt,
    // };
    final entry = CacheEntry(
      data: data,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      originalKey: combinedKey.$2,
      expiresAt: expiresAt,
    );

    // Update memory cache
    _updateMemoryCache(combinedKey.$1, entry);

    final metadata = Map.fromEntries(entry.toJson().entries);
    metadata.remove('data');
    await _metadata.put(combinedKey.$1, metadata);
    await _cache.put(combinedKey.$1, jsonEncode(data));
  }

  /// Reads a cached response.
  ///
  /// Set [allowExpired] to serve an entry past its expiry instead of dropping
  /// it — what stale-while-revalidate needs: show what we have, then refresh.
  /// With the default `false` an expired entry is deleted, as before.
  Future<Map<String, dynamic>?> getResponse({
    required String endpoint,
    Map<String, dynamic>? params,
    bool allowExpired = false,
  }) async {
    await _ensureInitialized();
    final combinedKey = _generateKey(endpoint, params);
    final cacheKey = combinedKey.$1;

    if (_memoryCache.containsKey(cacheKey)) {
      final entry = _memoryCache[cacheKey]!;
      if (allowExpired || !_isExpired(entry.toJson())) {
        log('$cacheKey...getting data from memory............');
        return entry.data;
      }
      _memoryCache.remove(cacheKey);
    }

    final dynamic rawEntry = _cache.get(cacheKey);
    final Map<String, dynamic>? hiveEntry = rawEntry != null
        ? Map<String, dynamic>.from(jsonDecode(rawEntry))
        : null; // only data

    final dynamic rawMetadata = _metadata.get(cacheKey);
    final Map<String, dynamic>? metadata = rawMetadata is Map
        ? Map<String, dynamic>.from(rawMetadata)
        : null;

    if (hiveEntry != null &&
        metadata != null &&
        (allowExpired || !_isExpired(metadata))) {
      // Promote to memory cache
      _updateMemoryCache(
        cacheKey,
        CacheEntry(
          data: hiveEntry,
          timestamp: metadata['timestamp'] as int,
          expiresAt: metadata['expiresAt'] as int?,
          originalKey: metadata["originalKey"] as String,
        ),
      );
      log('$cacheKey...getting data from hive local storage..........');
      return hiveEntry;
    }

    // 3. If expired or not found, remove from Hive — but never evict an entry
    // the caller was willing to serve stale.
    if (!allowExpired) {
      if (metadata != null) {
        await _metadata.delete(cacheKey);
      }
      if (hiveEntry != null) {
        await _cache.delete(cacheKey);
      }
    }
    log('$cacheKey...should getting data from api.........');
    return null;
  }

  /// The stored body exactly as it was written, without decoding it.
  ///
  /// This is what answers "did anything actually change?" — comparing the
  /// stored string against the next response costs a byte comparison, and lets
  /// callers skip decoding, model building and a rebuild when it matches.
  ///
  /// Expiry is deliberately ignored: the body is still the body. [maxStale] is
  /// the separate, harder limit — how old data may be before it is not worth
  /// showing at all. Without it, a store written with `maxAge: Duration.zero`
  /// would happily hand back a response from weeks ago.
  Future<String?> getRawResponse({
    required String endpoint,
    Map<String, dynamic>? params,
    Duration? maxStale,
  }) async {
    await _ensureInitialized();
    final cacheKey = _generateKey(endpoint, params).$1;
    final raw = _cache.get(cacheKey);
    if (raw == null || maxStale == null) {
      return raw;
    }

    final dynamic rawMetadata = _metadata.get(cacheKey);
    final timestamp = rawMetadata is Map ? rawMetadata['timestamp'] : null;
    if (timestamp is! int) {
      // No age on record — treat it as too old to trust.
      return null;
    }

    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (age > maxStale.inMilliseconds) {
      log('$cacheKey...cached copy is ${age}ms old, past the stale limit');
      return null;
    }
    return raw;
  }

  /// Extends the lifetime of an entry whose body is still current.
  ///
  /// An unchanged response then costs one small metadata write instead of
  /// rewriting the whole payload.
  Future<void> touch({
    required String endpoint,
    Map<String, dynamic>? params,
    Duration? maxAge,
  }) async {
    await _ensureInitialized();
    final cacheKey = _generateKey(endpoint, params).$1;

    final dynamic rawMetadata = _metadata.get(cacheKey);
    if (rawMetadata is! Map) {
      return;
    }

    final now = DateTime.now();
    final expiresAt = maxAge != null
        ? now.add(maxAge).millisecondsSinceEpoch
        : null;

    final metadata = Map<String, dynamic>.from(rawMetadata);
    metadata['timestamp'] = now.millisecondsSinceEpoch;
    metadata['expiresAt'] = expiresAt;
    await _metadata.put(cacheKey, metadata);

    final cached = _memoryCache[cacheKey];
    if (cached != null) {
      _memoryCache[cacheKey] = CacheEntry(
        data: cached.data,
        timestamp: now.millisecondsSinceEpoch,
        expiresAt: expiresAt,
        originalKey: cached.originalKey,
      );
    }
  }

  // ======================
  // CACHE INVALIDATION
  // ======================

  Future<void> invalidateEndpoint(String endpoint) async {
    await _ensureInitialized();
    final keysToDelete = <String>[];

    for (final hashKey in _metadata.keys) {
      final dynamic rawMetadata = _metadata.get(hashKey);
      if(rawMetadata == null) continue;
      final metadata = Map<String, dynamic>.from(rawMetadata);

      final originalKey = metadata['originalKey'] as String?;
      if (originalKey != null && Uri.parse(originalKey).path == endpoint) {
        keysToDelete.add(hashKey);
        _memoryCache.remove(hashKey);
      }
    }

    if (keysToDelete.isNotEmpty) {
      await _cache.deleteAll(keysToDelete);
      await _metadata.deleteAll(keysToDelete);
    }
  }

  Future<void> invalidateMatching(RegExp pattern) async {
    await _ensureInitialized();
    final keysToDelete = <String>[];

    for (final hashKey in _metadata.keys) {
      final metadata = _metadata.get(hashKey);
      if (metadata == null) continue;

      final originalKey = metadata['originalKey'] as String?;
      if (originalKey != null && pattern.hasMatch(originalKey)) {
        keysToDelete.add(hashKey);
        _memoryCache.remove(hashKey);
      }
    }

    await _cache.deleteAll(keysToDelete);
    // Metadata was being left behind here, unlike invalidateEndpoint.
    await _metadata.deleteAll(keysToDelete);
  }

  Future<void> clearAllCache() async {
    await _ensureInitialized();
    _memoryCache.clear();
    await _cache.clear();
    await _metadata.clear();
  }

  // ======================
  // UTILITY METHODS
  // ======================

  (String, String) _generateKey(String endpoint, Map<String, dynamic>? params) {
    // cacheKey, originalKey

    final url = _generateOriginalKey(endpoint, params);

    // The scope is hashed into the key but deliberately kept out of
    // `originalKey`, so endpoint-based invalidation keeps matching no matter
    // which environment an entry belongs to.
    var bytes = utf8.encode('${_resolveScope()}|$url');
    var digest = sha256.convert(bytes); // SHA-256 hash
    return (digest.toString(), url); // hex string, length 64
  }

  String _resolveScope() {
    try {
      return cacheScopeResolver();
    } catch (_) {
      // Base url not resolvable yet (no dotenv / DI). An unscoped key is
      // better than throwing from a cache lookup.
      return '';
    }
  }

  String _generateOriginalKey(String endpoint, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return endpoint;

    // Sort params for consistent key generation
    final Map<String, dynamic> filteredParams = Map.fromEntries(
      params.entries.where((entry) => entry.value != null),
    );

    final sortedParams = SplayTreeMap<String, String>.from(
      filteredParams.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );

    return Uri(
      path: endpoint,
      queryParameters: sortedParams.isEmpty ? null : sortedParams,
    ).toString();
  }

  bool _isExpired(Map<String, dynamic> entry) {
    final expiresAt = entry['expiresAt'];
    return expiresAt != null &&
        expiresAt < DateTime.now().millisecondsSinceEpoch;
  }

  void _updateMemoryCache(String key, CacheEntry entry) {
    // Remove oldest item if we've reached capacity
    if (_memoryCache.length >= _maxMemoryItems) {
      final oldestKey = _memoryCache.keys.reduce(
            (a, b) =>
        _memoryCache[a]!.timestamp < _memoryCache[b]!.timestamp ? a : b,
      );
      _memoryCache.remove(oldestKey);
    }

    _memoryCache[key] = entry;
  }
}

class CacheEntry {
  final Map<String, dynamic> data;
  final int timestamp;
  final int? expiresAt;
  final String originalKey;

  CacheEntry({
    required this.data,
    required this.timestamp,
    this.expiresAt,
    required this.originalKey,
  });

  //bool get isExpired => expiresAt != null && expiresAt! < DateTime.now().millisecondsSinceEpoch;

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      data: json['data'],
      timestamp: json['timestamp'],
      expiresAt: json['expiresAt'],
      originalKey: json['originalKey'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'timestamp': timestamp,
      'expiresAt': expiresAt,
      'originalKey': originalKey,
    };
  }
}
