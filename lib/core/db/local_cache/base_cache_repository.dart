import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../../state/global_data_api.dart';
import 'cache_manager.dart';
import 'cache_strategy.dart';

abstract class BaseCachedRepository {
  final CacheManager _cache = CacheManager();
  final GlobalDataApi dataApi = GlobalDataApi.instance;

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
    // if invalid Cache, then cache will be removed
    if (invalidCache ?? false) {
      await _cache.invalidateEndpoint(endpoint);
    }

    final resolved = strategy ?? CacheConfig.defaultStrategy;

    if (resolved == CacheStrategy.validityFirst) {
      final cached = await _cache.getResponse(
        endpoint: endpoint,
        params: query,
      );
      if (cached != null) {
        yield fromJson(cached);
        return;
      }

      final response = await fetch(endpoint, query);
      await _cache.cacheResponse(
        endpoint: endpoint,
        params: query,
        data: response,
        maxAge: maxAge,
      );
      yield fromJson(response);
      return;
    }

    // --- stale-while-revalidate ---

    final cachedRaw = await _cache.getRawResponse(
      endpoint: endpoint,
      params: query,
      maxStale: maxStale ?? CacheConfig.maxStale,
    );

    var servedFromCache = false;
    if (cachedRaw != null) {
      try {
        yield fromJson(jsonDecode(cachedRaw) as Map<String, dynamic>);
        servedFromCache = true;
      } catch (e) {
        // A corrupt or outdated-shape cache entry must never break a screen;
        // fall through and let the network answer.
        log('cache decode failed for $endpoint: $e', name: 'CachedRepository');
      }
    }

    try {
      final response = await fetch(endpoint, query);

      if (servedFromCache && jsonEncode(response) == cachedRaw) {
        // Identical bytes: extend the entry's life and stop. No second
        // emission, so nothing rebuilds and nothing blinks.
        await _cache.touch(
          endpoint: endpoint,
          params: query,
          maxAge: maxAge,
        );
        return;
      }

      await _cache.cacheResponse(
        endpoint: endpoint,
        params: query,
        data: response,
        maxAge: maxAge,
      );
      yield fromJson(response);
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
