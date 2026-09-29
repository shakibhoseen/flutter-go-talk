/// How a cached endpoint behaves.
///
/// Both modes run through the same code path in `BaseCachedRepository`, so
/// there is one implementation to reason about — the strategy only decides how
/// many times it emits and whether an expired copy may be shown.
enum CacheStrategy {
  /// One emission. A cached entry is used only while it is still valid;
  /// otherwise the API is called. Validity is what matters, staleness is never
  /// tolerated. This is how `cachedGet` has always behaved.
  validityFirst,

  /// Up to two emissions: whatever is already cached — even past its expiry,
  /// as long as it is within the stale limit — and then the fresh response,
  /// but only if it actually differs from what was shown.
  staleWhileRevalidate,
}

/// The single switch for cache-first behaviour.
///
/// Set [defaultStrategy] to [CacheStrategy.validityFirst] and every migrated
/// screen reverts to "valid cache or API, one answer" without touching a
/// single call site. Individual calls can still pin a strategy explicitly.
class CacheConfig {
  CacheConfig._();

  static CacheStrategy defaultStrategy = CacheStrategy.staleWhileRevalidate;

  /// Data older than this is never shown, whatever the strategy says.
  ///
  /// This is the guard against `maxAge: Duration.zero` — an entry that is
  /// technically "always expired" would otherwise be served forever.
  static Duration maxStale = const Duration(hours: 6);

  /// Restores the shipped defaults. For tests.
  static void reset() {
    defaultStrategy = CacheStrategy.staleWhileRevalidate;
    maxStale = const Duration(hours: 6);
  }
}
