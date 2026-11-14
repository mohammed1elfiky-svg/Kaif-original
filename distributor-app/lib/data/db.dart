import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local database: the last downloaded server data and the documents created on the device.
/// Everything the distributor does is stored here first, so the app works without a network.
class LocalDb {
  final Database db;
  LocalDb(this.db);

  static Future<LocalDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'kaif_distributor.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
            await db.execute('''CREATE TABLE docs (
                id TEXT PRIMARY KEY, kind TEXT NOT NULL, number TEXT NOT NULL, date TEXT NOT NULL,
                json TEXT NOT NULL, status TEXT NOT NULL, error TEXT NOT NULL DEFAULT '',
                in_snapshot INTEGER NOT NULL DEFAULT 0)''');
          },
        ));
    return LocalDb(db);
  }

  Future<String?> get(String key, [DatabaseExecutor? ex]) async {
    final r = await (ex ?? db).query('kv', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> put(String key, String? value, [DatabaseExecutor? ex]) async {
    if (value == null) {
      await (ex ?? db).delete('kv', where: 'key = ?', whereArgs: [key]);
    } else {
      await (ex ?? db).insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Saves a new document and takes the next number of the device series in one transaction,
  /// so a number is never used twice (ZATCA requires unique sequential invoice numbers).
  Future<Doc> insertDoc(Doc Function(String number) build, String prefix, DocKind kind) async {
    return db.transaction((tx) async {
      final key = 'counter.${kind.name}';
      final next = int.parse(await get(key, tx) ?? '0') + 1;
      await put(key, '$next', tx);
      final series = kind == DocKind.invoice ? prefix : '$prefix-R';
      final doc = build('$series-${next.toString().padLeft(6, '0')}');
      await tx.insert('docs', {
        'id': doc.id,
        'kind': doc.kind.name,
        'number': doc.number,
        'date': doc.date.toUtc().toIso8601String(),
        'json': jsonEncode(doc.toJson()),
        'status': doc.status.name,
        'error': doc.error,
        'in_snapshot': 0,
      });
      return doc;
    });
  }

  Future<List<Doc>> docs() async {
    final rows = await db.query('docs', orderBy: 'date DESC');
    return rows
        .map((r) => Doc.fromJson(jsonDecode(r['json'] as String),
            status: DocStatus.values.byName(r['status'] as String),
            error: r['error'] as String,
            inSnapshot: r['in_snapshot'] == 1))
        .toList();
  }

  Future<void> setStatus(String id, DocStatus status, String error) =>
      db.update('docs', {'status': status.name, 'error': error}, where: 'id = ?', whereArgs: [id]);

  /// After a download, the documents already received by the server are part of the server data.
  Future<void> markSentInSnapshot() =>
      db.update('docs', {'in_snapshot': 1}, where: 'status = ?', whereArgs: [DocStatus.sent.name]);
}
