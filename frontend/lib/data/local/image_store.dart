import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local storage for generated images.
///
/// Only the *file name* is persisted in the database — never an absolute path.
/// The app container's UUID changes on every reinstall (`flutter run` reinstalls
/// the app), so absolute paths stored yesterday point to a container that no
/// longer exists and every thumbnail silently breaks. A relative name survives
/// reinstalls and app restarts.
class ImageStore {
  ImageStore._(this.directory);

  final Directory directory;

  static ImageStore? _instance;

  /// Cached singleton — the directory never changes during the app lifetime.
  static ImageStore get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('ImageStore.open() must be awaited before use');
    }
    return i;
  }

  static Future<ImageStore> open() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/generated');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _instance = ImageStore._(dir);
  }

  /// File name for a job id.
  static String nameFor(String jobId) => '$jobId.png';

  /// Absolute path for a stored file name, resolved against the *current*
  /// container — always valid, never stale.
  String pathOf(String name) => '${directory.path}/$name';

  bool exists(String name) => File(pathOf(name)).existsSync();

  /// Writes the image bytes and returns the stored file name.
  Future<String> save(String jobId, List<int> bytes) async {
    final name = nameFor(jobId);
    await File(pathOf(name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<void> delete(String name) async {
    final file = File(pathOf(name));
    if (await file.exists()) await file.delete();
  }
}
