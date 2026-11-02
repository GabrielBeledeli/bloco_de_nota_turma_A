import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const notesTable = 'notes';
  static const _databaseName = 'notes.db';
  static const _databaseVersion = 2;

  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    return _database ??= await _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createSchema,
      onUpgrade: _recreateSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $notesTable(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category_id TEXT,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status TEXT NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_notes_user_updated ON $notesTable(user_id, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_notes_category ON $notesTable(category_id)',
    );
    await db.execute(
      'CREATE INDEX idx_notes_sync_status ON $notesTable(sync_status)',
    );
  }

  Future<void> _recreateSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.execute('DROP TABLE IF EXISTS $notesTable');
    await _createSchema(db, newVersion);
  }
}
