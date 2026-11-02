import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note_model.dart';
import '../repositories/category_local_repository.dart';
import '../repositories/note_local_repository.dart';
import 'remote_category_service.dart';
import 'remote_note_service.dart';

enum SyncResult { completed, offline, alreadyRunning }

class SyncService {
  SyncService({
    NoteLocalRepository? localNotes,
    CategoryLocalRepository? localCategories,
    RemoteNoteService? remoteNotes,
    RemoteCategoryService? remoteCategories,
  }) : _localNotes = localNotes ?? NoteLocalRepository(),
       _localCategories = localCategories ?? CategoryLocalRepository(),
       _remoteNotes = remoteNotes ?? RemoteNoteService(),
       _remoteCategories = remoteCategories ?? RemoteCategoryService();

  static const _connectivityErrorCodes = {'unavailable', 'deadline-exceeded'};

  final NoteLocalRepository _localNotes;
  final CategoryLocalRepository _localCategories;
  final RemoteNoteService _remoteNotes;
  final RemoteCategoryService _remoteCategories;

  bool _isSyncing = false;

  Future<SyncResult> sync(String userId) async {
    if (_isSyncing) return SyncResult.alreadyRunning;

    _isSyncing = true;
    try {
      await _pullCategories(userId);
      await _pullNotes(userId);
      await _pushCategories(userId);
      await _pushNotes(userId);
      return SyncResult.completed;
    } on TimeoutException {
      return SyncResult.offline;
    } on FirebaseException catch (error) {
      if (_connectivityErrorCodes.contains(error.code)) {
        return SyncResult.offline;
      }
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pullCategories(String userId) async {
    final remoteCategories = await _remoteCategories.getAll(userId);

    for (final remote in remoteCategories) {
      final local = await _localCategories.getById(remote.id);
      final remoteIsNewer =
          local == null ||
          remote.updatedAt.millisecondsSinceEpoch >
              local.updatedAt.millisecondsSinceEpoch;
      if (remoteIsNewer) await _localCategories.upsert(remote);
    }
  }

  /// Conflitos seguem last-write-wins por `updatedAt`: a versão remota só
  /// substitui a local quando é mais recente, inclusive sobre pendências locais.
  /// Exclusões locais pendentes nunca são revertidas pelo servidor.
  Future<void> _pullNotes(String userId) async {
    final remoteNotes = await _remoteNotes.getAll(userId);
    final remoteIds = remoteNotes.map((note) => note.id).toSet();

    for (final remote in remoteNotes) {
      final local = await _localNotes.getById(remote.id);

      if (local == null) {
        await _localNotes.upsert(remote);
        continue;
      }
      if (local.syncStatus == SyncStatus.pendingDelete) continue;

      final remoteIsNewer =
          remote.updatedAt.millisecondsSinceEpoch >
          local.updatedAt.millisecondsSinceEpoch;
      if (remoteIsNewer) await _localNotes.upsert(remote);
    }

    final syncedLocally = await _localNotes.query(
      userId: userId,
      syncStatus: SyncStatus.synced,
    );
    for (final note in syncedLocally) {
      if (!remoteIds.contains(note.id)) await _localNotes.delete(note.id);
    }
  }

  Future<void> _pushCategories(String userId) async {
    final pending = await _localCategories.getByStatus(
      userId,
      SyncStatus.pendingUpload,
    );
    for (final category in pending) {
      await _remoteCategories.upsert(category);
      await _localCategories.markAsSynced(category);
    }
  }

  Future<void> _pushNotes(String userId) async {
    final pendingUploads = await _localNotes.query(
      userId: userId,
      syncStatus: SyncStatus.pendingUpload,
    );
    for (final note in pendingUploads) {
      await _remoteNotes.upsert(note);
      await _localNotes.markAsSynced(note);
    }

    final pendingDeletes = await _localNotes.query(
      userId: userId,
      syncStatus: SyncStatus.pendingDelete,
    );
    for (final note in pendingDeletes) {
      await _remoteNotes.delete(userId, note.id);
      await _localNotes.delete(note.id);
    }
  }
}
