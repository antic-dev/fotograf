import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

typedef Row = Map<String, Object?>;

/// Tanka sinhrona obloga oko SQLite baze. Server radi u jednom izolatu,
/// pa su sve operacije serijalizovane i transakcije su jednostavne.
class Db {
  Db._(this._db);

  final Database _db;

  static Db open(String dataDir) {
    Directory(dataDir).createSync(recursive: true);
    final db = sqlite3.open(p.join(dataDir, 'fotograf.db'));
    final wrapper = Db._(db);
    wrapper._configure();
    wrapper._migrate();
    return wrapper;
  }

  static Db memory() {
    final wrapper = Db._(sqlite3.openInMemory());
    wrapper._configure();
    wrapper._migrate();
    return wrapper;
  }

  void _configure() {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA synchronous = NORMAL');
    _db.execute('PRAGMA busy_timeout = 5000');
  }

  void _migrate() {
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    final migrations = <String>[_v1];
    for (var i = version; i < migrations.length; i++) {
      tx(() {
        _db.execute(migrations[i]);
        _db.execute('PRAGMA user_version = ${i + 1}');
      });
    }
  }

  List<Row> query(String sql, [List<Object?> params = const []]) =>
      _db.select(sql, params).map((r) => Map<String, Object?>.from(r)).toList();

  Row? one(String sql, [List<Object?> params = const []]) {
    final rows = _db.select(sql, params);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Object? scalar(String sql, [List<Object?> params = const []]) {
    final rows = _db.select(sql, params);
    return rows.isEmpty ? null : rows.first.values.first;
  }

  /// Izvršava naredbu i vraća broj izmenjenih redova.
  int exec(String sql, [List<Object?> params = const []]) {
    _db.execute(sql, params);
    return _db.updatedRows;
  }

  int get lastInsertId => _db.lastInsertRowId;

  T tx<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final r = body();
      _db.execute('COMMIT');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  String? setting(String key) => scalar('SELECT value FROM settings WHERE key = ?', [key]) as String?;

  void setSetting(String key, String? value) {
    if (value == null) {
      exec('DELETE FROM settings WHERE key = ?', [key]);
    } else {
      exec(
        'INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );
    }
  }

  void audit(String action, {String detail = '', String ip = ''}) {
    exec(
      'INSERT INTO audit(ts, action, detail, ip) VALUES(?, ?, ?, ?)',
      [DateTime.now().millisecondsSinceEpoch, action, detail, ip],
    );
  }

  void close() => _db.close();
}

const _v1 = '''
CREATE TABLE settings(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE admin_sessions(
  token_hash TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  ip TEXT NOT NULL DEFAULT '',
  user_agent TEXT NOT NULL DEFAULT ''
);

CREATE TABLE visitors(
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);

CREATE TABLE projects(
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  client_name TEXT NOT NULL DEFAULT '',
  event_date TEXT,
  message TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'closed', 'hidden')),
  share_token_hash TEXT NOT NULL UNIQUE,
  share_token_enc TEXT NOT NULL,
  max_photos INTEGER,
  deadline INTEGER,
  watermark INTEGER NOT NULL DEFAULT 1,
  cover_photo_id TEXT,
  drive_folder_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE photos(
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  drive_file_id TEXT NOT NULL,
  mime TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  taken_at INTEGER,
  sort_index INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX photos_project ON photos(project_id, sort_index);

CREATE TABLE orders(
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  visitor_id TEXT NOT NULL REFERENCES visitors(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft', 'submitted', 'printing', 'done')),
  name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  submitted_at INTEGER,
  UNIQUE(project_id, visitor_id)
);
CREATE INDEX orders_status ON orders(status, submitted_at);

CREATE TABLE order_items(
  order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 99),
  created_at INTEGER NOT NULL,
  PRIMARY KEY(order_id, photo_id)
);

CREATE TABLE print_links(
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  token_enc TEXT NOT NULL,
  label TEXT NOT NULL,
  print_size TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0,
  access_count INTEGER NOT NULL DEFAULT 0,
  last_access_at INTEGER,
  sent_to TEXT NOT NULL DEFAULT ''
);

CREATE TABLE print_link_items(
  id INTEGER PRIMARY KEY,
  print_link_id TEXT NOT NULL REFERENCES print_links(id) ON DELETE CASCADE,
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL,
  customer TEXT NOT NULL DEFAULT ''
);
CREATE INDEX print_link_items_link ON print_link_items(print_link_id);

CREATE TABLE print_link_orders(
  print_link_id TEXT NOT NULL REFERENCES print_links(id) ON DELETE CASCADE,
  order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  PRIMARY KEY(print_link_id, order_id)
);

CREATE TABLE audit(
  id INTEGER PRIMARY KEY,
  ts INTEGER NOT NULL,
  action TEXT NOT NULL,
  detail TEXT NOT NULL DEFAULT '',
  ip TEXT NOT NULL DEFAULT ''
);
''';
