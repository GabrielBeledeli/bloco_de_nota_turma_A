import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/category_model.dart';
import '../models/note_model.dart';

class CategoryLocalRepository {
  CategoryLocalRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  static const _defaultNames = {
    'estudos': 'Estudos',
    'trabalho': 'Trabalho',
    'pessoal': 'Pessoal',
  };

  final DatabaseHelper _databaseHelper;

  /// Ids determinísticos evitam duplicar as categorias padrão entre
  /// dispositivos; a data fixa impede que uma cópia sobrescreva a outra.
  Future<void> ensureDefaults(String userId) async {
    final db = await _databaseHelper.database;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);

    for (final entry in _defaultNames.entries) {
      final category = CategoryModel(
        id: 'default-${entry.key}',
        name: entry.value,
        userId: userId,
        createdAt: epoch,
        updatedAt: epoch,
      );
      await db.insert(
        DatabaseHelper.categoriesTable,
        category.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> insert(CategoryModel category) async {
    final db = await _databaseHelper.database;
    await db.insert(
      DatabaseHelper.categoriesTable,
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> upsert(CategoryModel category) async {
    final db = await _databaseHelper.database;
    await db.insert(
      DatabaseHelper.categoriesTable,
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CategoryModel?> getById(String id) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.categoriesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : CategoryModel.fromMap(rows.first);
  }

  Future<List<CategoryModel>> getAll(String userId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.categoriesTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(CategoryModel.fromMap).toList();
  }

  Future<List<CategoryModel>> getByStatus(
    String userId,
    SyncStatus syncStatus,
  ) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.categoriesTable,
      where: 'user_id = ? AND sync_status = ?',
      whereArgs: [userId, syncStatus.name],
    );

    return rows.map(CategoryModel.fromMap).toList();
  }

  Future<int> markAsSynced(CategoryModel category) async {
    final db = await _databaseHelper.database;
    return db.update(
      DatabaseHelper.categoriesTable,
      {'sync_status': SyncStatus.synced.name},
      where: 'id = ? AND updated_at = ?',
      whereArgs: [category.id, category.updatedAt.millisecondsSinceEpoch],
    );
  }

  Future<bool> hasPendingChanges(String userId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.categoriesTable,
      columns: ['id'],
      where: 'user_id = ? AND sync_status != ?',
      whereArgs: [userId, SyncStatus.synced.name],
      limit: 1,
    );

    return rows.isNotEmpty;
  }
}
