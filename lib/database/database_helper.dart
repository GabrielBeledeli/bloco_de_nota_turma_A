import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const notesTable = 'notes';
  static const categoriesTable = 'categories';
  static const _databaseName = 'notes.db';
  static const _databaseVersion = 3;

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
      onUpgrade: _upgradeSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await _createNotesTable(db);
    await _createCategoriesTable(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS $notesTable');
      await _createNotesTable(db);
    }
    if (oldVersion < 3) {
      await _createCategoriesTable(db);
    }
  }

  Future<void> _createNotesTable(Database db) async {
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

  Future<void> _createCategoriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $categoriesTable(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_categories_user ON $categoriesTable(user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_categories_sync_status ON $categoriesTable(sync_status)',
    );
  }
}
