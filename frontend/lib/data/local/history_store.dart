import 'package:sqflite/sqflite.dart';

import '../dto/api_models.dart';

/// Local-first generation history (sqflite).
///
/// Survives app restarts and works with the backend completely down —
/// this is the source of truth for the History tab.
class HistoryStore {
  HistoryStore._(this._db);

  final Database _db;

  static const _table = 'history';

  static Future<HistoryStore> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      '$dir/dreamlab_history.db',
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            prompt TEXT NOT NULL,
            style TEXT NOT NULL,
            aspect_ratio TEXT NOT NULL,
            quality TEXT NOT NULL,
            status TEXT NOT NULL,
            local_image_name TEXT,
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            finished_at TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 stored an absolute path. The app container UUID changes on every
        // reinstall, so those paths go stale and every thumbnail breaks.
        // Keep only the file name and resolve it against the live container.
        await db.execute('ALTER TABLE $_table ADD COLUMN local_image_name TEXT');
        final rows = await db.query(
          _table,
          columns: ['id', 'local_image_path'],
        );
        for (final row in rows) {
          final old = row['local_image_path'] as String?;
          if (old == null || old.isEmpty) continue;
          final name = old.split('/').last;
          await db.update(
            _table,
            {'local_image_name': name},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      },
    );
    return HistoryStore._(db);
  }

  Future<void> upsert(HistoryEntry entry) => _db.insert(
    _table,
    entry.toDb(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<List<HistoryEntry>> all({int limit = 200}) async {
    final rows = await _db.query(
      _table,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(HistoryEntry.fromDb).toList();
  }

  Future<HistoryEntry?> byId(String id) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HistoryEntry.fromDb(rows.first);
  }

  Future<int> count() async =>
      (await _db.rawQuery('SELECT COUNT(*) AS c FROM $_table')).first['c']
          as int;

  Future<void> clear() => _db.delete(_table);

  Future<void> close() => _db.close();
}
