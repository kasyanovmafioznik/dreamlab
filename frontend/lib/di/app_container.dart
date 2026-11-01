import '../../core/api/api_client.dart';
import '../../data/local/history_store.dart';
import '../../data/local/image_store.dart';
import '../../data/local/prefs.dart';
import '../../data/repositories/repositories.dart';

/// Manual DI: one container built at startup, passed down the widget tree.
/// Deliberately not get_it/injectable — the graph is tiny and explicit.
class AppContainer {
  AppContainer._({
    required this.prefs,
    required this.api,
    required this.historyStore,
    required this.imageStore,
    required this.subscriptionRepository,
    required this.generationRepository,
  });

  final Prefs prefs;
  final ApiClient api;
  final HistoryStore historyStore;
  final ImageStore imageStore;
  final SubscriptionRepository subscriptionRepository;
  final GenerationRepository generationRepository;

  static Future<AppContainer> create() async {
    final prefs = await Prefs.open();
    final api = ApiClient(prefs);
    final historyStore = await HistoryStore.open();
    // Opened before the first frame: the image directory must be known when
    // history rows are resolved to file paths.
    final imageStore = await ImageStore.open();
    return AppContainer._(
      prefs: prefs,
      api: api,
      historyStore: historyStore,
      imageStore: imageStore,
      subscriptionRepository: SubscriptionRepository(api, prefs),
      generationRepository: GenerationRepository(
        api,
        historyStore,
        prefs,
        imageStore,
      ),
    );
  }

  Future<void> dispose() => historyStore.close();
}
