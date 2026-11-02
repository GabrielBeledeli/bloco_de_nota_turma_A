import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/note_model.dart';

class NoteLocalRepository {
  NoteLocalRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _databaseHelper;

  Future<void> insert(NoteModel note) async {
    final db = await _databaseHelper.database;
    await db.insert(
      DatabaseHelper.notesTable,
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> update(NoteModel note) async {
    final db = await _databaseHelper.database;
    return db.update(
      DatabaseHelper.notesTable,
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> upsert(NoteModel note) async {
    final db = await _databaseHelper.database;
    await db.insert(
      DatabaseHelper.notesTable,
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> markAsDeleted(String id) async {
    final db = await _databaseHelper.database;
    return db.update(
      DatabaseHelper.notesTable,
      {'sync_status': SyncStatus.pendingDelete.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Só marca como sincronizada se a nota não foi editada durante o envio.
  Future<int> markAsSynced(NoteModel note) async {
    final db = await _databaseHelper.database;
    return db.update(
      DatabaseHelper.notesTable,
      {'sync_status': SyncStatus.synced.name},
      where: 'id = ? AND updated_at = ?',
      whereArgs: [note.id, note.updatedAt.millisecondsSinceEpoch],
    );
  }

  Future<int> delete(String id) async {
    final db = await _databaseHelper.database;
    return db.delete(
      DatabaseHelper.notesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<NoteModel?> getById(String id) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.notesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : NoteModel.fromMap(rows.first);
  }

  Future<List<NoteModel>> getAll(String userId) {
    return query(userId: userId);
  }

  Future<bool> hasPendingChanges(String userId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.notesTable,
      columns: ['id'],
      where: 'user_id = ? AND sync_status != ?',
      whereArgs: [userId, SyncStatus.synced.name],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  /// Notas com [SyncStatus.pendingDelete] só são retornadas quando
  /// [syncStatus] é informado explicitamente.
  Future<List<NoteModel>> query({
    required String userId,
    String? searchTerm,
    String? categoryId,
    bool? isArchived,
    SyncStatus? syncStatus,
  }) async {
    final db = await _databaseHelper.database;
    final clauses = <String>['user_id = ?'];
    final args = <Object>[userId];

    if (syncStatus != null) {
      clauses.add('sync_status = ?');
      args.add(syncStatus.name);
    } else {
      clauses.add('sync_status != ?');
      args.add(SyncStatus.pendingDelete.name);
    }

    if (categoryId != null) {
      clauses.add('category_id = ?');
      args.add(categoryId);
    }

    if (isArchived != null) {
      clauses.add('is_archived = ?');
      args.add(isArchived ? 1 : 0);
    }

    final term = searchTerm?.trim();
    if (term != null && term.isNotEmpty) {
      final pattern = '%${_escapeLike(term)}%';
      clauses.add(r"(title LIKE ? ESCAPE '\' OR content LIKE ? ESCAPE '\')");
      args.addAll([pattern, pattern]);
    }

    final rows = await db.query(
      DatabaseHelper.notesTable,
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );

    return rows.map(NoteModel.fromMap).toList();
  }

  String _escapeLike(String term) {
    return term.replaceAllMapped(RegExp(r'[\\%_]'), (match) => '\\${match[0]}');
  }
}
