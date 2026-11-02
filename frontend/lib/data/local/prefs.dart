import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// Local persistence for identity, server URL and the subscription cache.
///
/// `userId` is generated once on first launch — anonymous identification,
/// not authorization (no login anywhere).
class Prefs {
  Prefs(this._sp);

  final SharedPreferences _sp;

  static Future<Prefs> open() async =>
      Prefs(await SharedPreferences.getInstance());

  String get userId {
    final existing = _sp.getString(AppConfig.kUserId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _generateUuid();
    _sp.setString(AppConfig.kUserId, generated);
    return generated;
  }

  /// Rotates the anonymous identity (Settings action).
  void resetUserId() => _sp.setString(AppConfig.kUserId, _generateUuid());

  String get serverUrl {
    final stored = _sp.getString(AppConfig.kServerUrl);
    if (stored == null || stored.trim().isEmpty) {
      return AppConfig.defaultServerUrl;
    }
    return _normalizeUrl(stored);
  }

  set serverUrl(String value) =>
      _sp.setString(AppConfig.kServerUrl, _normalizeUrl(value));

  // Subscription cache — the UI paints instantly from here, server wins later.
  String? get cachedTier => _sp.getString(AppConfig.kSubTier);
  String? get cachedUpgradedAt => _sp.getString(AppConfig.kSubUpgradedAt);

  void cacheSubscription({required String tier, String? upgradedAt}) {
    _sp.setString(AppConfig.kSubTier, tier);
    if (upgradedAt != null) {
      _sp.setString(AppConfig.kSubUpgradedAt, upgradedAt);
    } else {
      _sp.remove(AppConfig.kSubUpgradedAt);
    }
  }

  void clearSubscriptionCache() {
    _sp.remove(AppConfig.kSubTier);
    _sp.remove(AppConfig.kSubUpgradedAt);
  }

  /// Index of the bottom tab the user was on last — the app reopens there.
  int get lastTab => _sp.getInt(AppConfig.kLastTab) ?? 0;
  set lastTab(int value) => _sp.setInt(AppConfig.kLastTab, value);

  String? get cachedOptionsJson => _sp.getString(AppConfig.kOptionsCache);
  set cachedOptionsJson(String? value) => value == null
      ? _sp.remove(AppConfig.kOptionsCache)
      : _sp.setString(AppConfig.kOptionsCache, value);

  static String _normalizeUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static String _generateUuid() {
    final rand = List<int>.generate(16, (i) => i);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 16; i++) {
      rand[i] =
          (timestamp >> (i % 8 * 8)) ^
          (DateTime.now().hashCode + i * 31) & 0xFF;
    }
    rand[6] = (rand[6] & 0x0F) | 0x40; // version 4
    rand[8] = (rand[8] & 0x3F) | 0x80; // variant
    final hex = rand.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
