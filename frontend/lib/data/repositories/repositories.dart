import 'dart:convert';

import '../../core/api/api_client.dart';
import '../../core/errors/failures.dart';
import '../dto/api_models.dart';
import '../local/history_store.dart';
import '../local/image_store.dart';
import '../local/prefs.dart';

/// Server-side subscription: source of truth is the server; Prefs cache only
/// paints the first frame while the real status is being fetched.
class SubscriptionRepository {
  SubscriptionRepository(this._api, this._prefs);

  final ApiClient _api;
  final Prefs _prefs;

  String get userId => _prefs.userId;

  /// Last known tier — used for instant UI, revalidated by [refresh].
  SubscriptionTier get cachedTier {
    final raw = _prefs.cachedTier;
    return SubscriptionTier.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => SubscriptionTier.free,
    );
  }

  String? get cachedUpgradedAt => _prefs.cachedUpgradedAt;

  /// Fetch fresh status from the server and update the cache.
  Future<SubscriptionInfo> refresh() async {
    final info = await _api.getSubscription();
    _prefs.cacheSubscription(tier: info.tier.name, upgradedAt: info.upgradedAt);
    return info;
  }

  /// Mock "purchase" — one POST, no billing.
  Future<SubscriptionInfo> upgrade() async {
    final info = await _api.upgradeSubscription();
    _prefs.cacheSubscription(tier: info.tier.name, upgradedAt: info.upgradedAt);
    return info;
  }
}

/// Generation flow + local history persistence.
class GenerationRepository {
  GenerationRepository(this._api, this._history, this._prefs, this._images);

  final ApiClient _api;
  final HistoryStore _history;
  final Prefs _prefs;
  final ImageStore _images;

  // -- catalog ---------------------------------------------------------------

  /// Server catalog is the source of truth; cache keeps pickers usable
  /// offline; fallback keeps the screen usable on a cold offline start.
  Future<OptionsCatalog> loadOptions() async {
    try {
      final fresh = await _api.getOptions();
      _prefs.cachedOptionsJson = jsonEncode(fresh.toJson());
      return fresh;
    } on AppFailure {
      final cached = _prefs.cachedOptionsJson;
      if (cached != null) {
        try {
          return OptionsCatalog.fromJson(
            jsonDecode(cached) as Map<String, dynamic>,
          );
        } on FormatException {
          // fall through to hardcoded fallback
        }
      }
      return OptionsCatalog.fallback;
    }
  }

  // -- generation ------------------------------------------------------------

  Future<GenerateAccepted> startGeneration({
    required String prompt,
    required String style,
    required String aspectRatio,
    required String quality,
  }) => _api.createGeneration(
    prompt: prompt,
    style: style,
    aspectRatio: aspectRatio,
    quality: quality,
  );

  Future<GenerationJob> getStatus(String jobId) => _api.getGeneration(jobId);

  /// Downloads the image into the local image store and records the job in
  /// history. Returns the entry (the file *name* is stored, not a path).
  Future<HistoryEntry> persistResult(GenerationJob job) async {
    String? imageName;
    if (job.imageUrl != null) {
      try {
        final bytes = await _api.downloadImage(job.imageUrl!);
        imageName = await _images.save(job.id, bytes);
      } catch (_) {
        // Offline/history must not break because a download failed.
        imageName = null;
      }
    }
    final entry = HistoryEntry.fromJob(job, localImageName: imageName);
    await _history.upsert(entry);
    return entry;
  }

  // -- history ---------------------------------------------------------------

  Future<List<HistoryEntry>> localHistory() => _history.all();

  Future<HistoryEntry?> historyById(String id) => _history.byId(id);

  Future<void> clearHistory() async {
    final entries = await _history.all();
    for (final e in entries) {
      final name = e.localImageName;
      if (name != null) await _images.delete(name);
    }
    await _history.clear();
  }

  /// Merges server-side history into the local store.
  /// Throws [AppFailure] if the server is unreachable — callers decide how to
  /// degrade (HistoryBloc falls back to local data + offline banner).
  Future<List<HistoryEntry>> syncWithServer() async {
    final remote = await _api.listGenerations();
    for (final job in remote) {
      if (job.status == JobStatus.succeeded) {
        final existing = await _history.byId(job.id);
        final name = existing?.localImageName;
        // Re-download when the file is missing on disk (e.g. the app was
        // reinstalled and the container was wiped) — not only when the DB
        // row has no name yet.
        final needsImage = name == null || !_images.exists(name);
        if (needsImage) {
          await persistResult(job);
        }
      } else {
        await _history.upsert(HistoryEntry.fromJob(job));
      }
    }
    return _history.all();
  }
}
