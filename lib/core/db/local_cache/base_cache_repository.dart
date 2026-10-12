import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../../state/global_data_api.dart';
import 'cache_manager.dart';
import 'cache_strategy.dart';

abstract class BaseCachedRepository {
  final CacheManager? _cacheManager;
  final GlobalDataApi? _globalDataApi;

  const BaseCachedRepository({
    CacheManager? cache,
    GlobalDataApi? dataApi,
  })  : _cacheManager = cache,
        _globalDataApi = dataApi;

  CacheManager get cache => _cacheManager ?? CacheManager();
  GlobalDataApi get dataApi => _globalDataApi ?? GlobalDataApi.instance;

  /// The single place this class reaches the network. Overriding it is how a
  /// subclass (or a test) changes where the data comes from without touching
  /// the caching logic.
  @protected
  Future<dynamic> fetch(String endpoint, Map<String, dynamic>? query) {
    return dataApi.getResponse(url: endpoint, query: query);
  }

  /// Reads an endpoint through the cache.
  ///
  /// [CacheStrategy.validityFirst] emits once — a valid cached copy, or the
  /// API. [CacheStrategy.staleWhileRevalidate] emits what is already cached
  /// first, then refreshes; the second emission happens **only if the response
  /// actually changed**, so an unchanged refresh costs no decode, no model
  /// building and no rebuild.
  ///
  /// Leave [strategy] null to follow [CacheConfig.defaultStrategy] — the one
  /// switch that turns cache-first off everywhere.
  Stream<T> cachedStream<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic>? query,
    Duration maxAge = Duration.zero,
    bool? invalidCache,
    CacheStrategy? strategy,
    Duration? maxStale,
  }) async* {
    final capturedUserScope = cache.resolveCurrentUserScope();
    final capturedEpoch = cache.sessionEpoch;

    // if invalid Cache, then cache will be removed
    if (invalidCache ?? false) {
      await cache.invalidateEndpoint(endpoint);
    }

    final resolved = strategy ?? CacheConfig.defaultStrategy;

    if (resolved == CacheStrategy.validityFirst) {
      final cached = await cache.getResponse(
        endpoint: endpoint,
        params: query,
        targetUserScope: capturedUserScope,
      );
      if (cached != null) {
        yield fromJson(cached);
        return;
      }

      final response = await fetch(endpoint, query);
      if (cache.sessionEpoch != capturedEpoch ||
          cache.resolveCurrentUserScope() != capturedUserScope) {
        log('Session changed during fetch for $endpoint; aborting emission and cache write',
            name: 'CachedRepository');
        return;
      }

      final mapResponse = response is Map<String, dynamic>
          ? response
          : (response is Map
              ? Map<String, dynamic>.from(response)
              : <String, dynamic>{});
      await cache.cacheResponse(
        endpoint: endpoint,
        params: query,
        data: mapResponse,
        maxAge: maxAge,
        targetUserScope: capturedUserScope,
        sessionEpoch: capturedEpoch,
      );
      yield fromJson(mapResponse);
      return;
    }

    // --- stale-while-revalidate ---

    final cachedRaw = await cache.getRawResponse(
      endpoint: endpoint,
      params: query,
      maxStale: maxStale ?? CacheConfig.maxStale,
      targetUserScope: capturedUserScope,
    );

    var servedFromCache = false;
    if (cachedRaw != null) {
      try {
        final decoded = jsonDecode(cachedRaw);
        final map = decoded is Map<String, dynamic>
            ? decoded
            : Map<String, dynamic>.from(decoded as Map);
        yield fromJson(map);
        servedFromCache = true;
      } catch (e) {
        // A corrupt or outdated-shape cache entry must never break a screen;
        // fall through and let the network answer.
        log('cache decode failed for $endpoint: $e', name: 'CachedRepository');
      }
    }

    try {
      final response = await fetch(endpoint, query);
      if (cache.sessionEpoch != capturedEpoch ||
          cache.resolveCurrentUserScope() != capturedUserScope) {
        log('Session changed during fetch for $endpoint; aborting emission and cache write',
            name: 'CachedRepository');
        return;
      }

      final mapResponse = response is Map<String, dynamic>
          ? response
          : (response is Map
              ? Map<String, dynamic>.from(response)
              : <String, dynamic>{});

      if (servedFromCache && jsonEncode(mapResponse) == cachedRaw) {
        // Identical bytes: extend the entry's life and stop. No second
        // emission, so nothing rebuilds and nothing blinks.
        await cache.touch(
          endpoint: endpoint,
          params: query,
          maxAge: maxAge,
          targetUserScope: capturedUserScope,
          sessionEpoch: capturedEpoch,
        );
        return;
      }

      await cache.cacheResponse(
        endpoint: endpoint,
        params: query,
        data: mapResponse,
        maxAge: maxAge,
        targetUserScope: capturedUserScope,
        sessionEpoch: capturedEpoch,
      );
      yield fromJson(mapResponse);
    } catch (e) {
      // With data already on screen a failed refresh is not the user's
      // problem. With nothing on screen, it is the only answer we have.
      if (!servedFromCache) {
        rethrow;
      }
      log(
        'refresh failed for $endpoint, keeping the cached copy: $e',
        name: 'CachedRepository',
      );
    }
  }

  /// Single-answer read. Unchanged behaviour: a valid cached copy, otherwise
  /// the API. Shares its implementation with [cachedStream] so the two can
  /// never drift apart.
  Future<T> cachedGet<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic>? query,
    Duration maxAge = Duration.zero,
    bool? invalidCache,
  }) {
    return cachedStream<T>(
      endpoint: endpoint,
      fromJson: fromJson,
      query: query,
      maxAge: maxAge,
      invalidCache: invalidCache,
      strategy: CacheStrategy.validityFirst,
    ).last;
  }
}
