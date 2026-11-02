/// App-wide configuration constants and preference keys.
library;

abstract final class AppConfig {
  static const appName = 'DreamLab';

  /// iOS simulator reaches the host machine via 127.0.0.1 directly.
  static const defaultServerUrl = 'http://127.0.0.1:8000';

  // SharedPreferences keys.
  static const kUserId = 'user_id';
  static const kServerUrl = 'server_url';
  static const kSubTier = 'sub_tier';
  static const kSubUpgradedAt = 'sub_upgraded_at';
  static const kOptionsCache = 'options_cache';
  static const kLastTab = 'last_tab';

  // Networking.
  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 15);

  /// Polling: starts fast, backs off to [pollMaxDelay]; hard client-side cap.
  static const pollInitialDelay = Duration(milliseconds: 500);
  static const pollMaxDelay = Duration(seconds: 2);
  static const pollOverallTimeout = Duration(seconds: 60);

  static const apiPrefix = '/v1';
}
