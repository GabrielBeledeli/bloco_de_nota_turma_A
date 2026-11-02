import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note_model.dart';
import '../repositories/category_local_repository.dart';
import '../repositories/note_local_repository.dart';
import 'remote_category_service.dart';
import 'remote_note_service.dart';

enum SyncState { completed, offline, failed }

class SyncReport {
  final SyncState state;
  final int pushedCount;
  final String? errorMessage;

  const SyncReport({
    required this.state,
    this.pushedCount = 0,
    this.errorMessage,
  });
}

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

  Future<SyncReport>? _activeSync;
  bool _needsAnotherPass = false;
  bool _wasOffline = false;

  bool get isSyncing => _activeSync != null;

  Future<bool> hasPendingChanges(String userId) async {
    return await _localNotes.hasPendingChanges(userId) ||
        await _localCategories.hasPendingChanges(userId);
  }

  /// Chamadas concorrentes aguardam o ciclo ativo e agendam uma passagem extra
  /// para que mutações gravadas durante um sync em andamento não fiquem retidas.
  Future<SyncReport> sync(String userId) {
    if (_activeSync != null) {
      _needsAnotherPass = true;
      return _activeSync!;
    }

    final future = _runSyncLoop(userId);
    _activeSync = future;
    return future;
  }

  Future<SyncReport> _runSyncLoop(String userId) async {
    try {
      var totalPushed = 0;
      var lastReport = const SyncReport(state: SyncState.completed);

      do {
        _needsAnotherPass = false;
        lastReport = await _executeSinglePass(userId);
        totalPushed += lastReport.pushedCount;
      } while (_needsAnotherPass && lastReport.state == SyncState.completed);

      return SyncReport(
        state: lastReport.state,
        pushedCount: totalPushed,
        errorMessage: lastReport.errorMessage,
      );
    } finally {
      _activeSync = null;
      _needsAnotherPass = false;
    }
  }

  /// Após falha offline, reinicia a camada de rede do SDK para zerar o backoff
  /// exponencial do canal gRPC quando a conectividade é restabelecida.
  Future<SyncReport> _executeSinglePass(String userId) async {
    try {
      if (_wasOffline) {
        await _remoteNotes.resetConnection();
      }

      await _pullCategories(userId);
      await _pullNotes(userId);
      final pushedCategories = await _pushCategories(userId);
      final pushedNotes = await _pushNotes(userId);

      _wasOffline = false;
      return SyncReport(
        state: SyncState.completed,
        pushedCount: pushedCategories + pushedNotes,
      );
    } on TimeoutException catch (error, stackTrace) {
      _wasOffline = true;
      developer.log(
        'Timeout ao sincronizar com o Cloud Firestore',
        name: 'SyncService',
        error: error,
        stackTrace: stackTrace,
      );
      return const SyncReport(state: SyncState.offline);
    } on FirebaseException catch (error, stackTrace) {
      if (_connectivityErrorCodes.contains(error.code)) {
        _wasOffline = true;
        developer.log(
          'Cloud Firestore indisponível (${error.code}): ${error.message}',
          name: 'SyncService',
          error: error,
        );
        return const SyncReport(state: SyncState.offline);
      }

      developer.log(
        'Falha do Firestore na sincronização (${error.code}): ${error.message}',
        name: 'SyncService',
        error: error,
        stackTrace: stackTrace,
      );
      return SyncReport(
        state: SyncState.failed,
        errorMessage:
            '[${error.code}] ${error.message ?? 'Erro ao sincronizar no Firestore'}',
      );
    } catch (error, stackTrace) {
      developer.log(
        'Erro inesperado na sincronização',
        name: 'SyncService',
        error: error,
        stackTrace: stackTrace,
      );
      return SyncReport(
        state: SyncState.failed,
        errorMessage: error.toString(),
      );
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

  Future<int> _pushCategories(String userId) async {
    var pushed = 0;
    Object? firstFailure;
    StackTrace? firstStackTrace;

    final pending = await _localCategories.getByStatus(
      userId,
      SyncStatus.pendingUpload,
    );
    for (final category in pending) {
      try {
        await _remoteCategories.upsert(category);
        await _localCategories.markAsSynced(category);
        pushed++;
      } on TimeoutException {
        rethrow;
      } on FirebaseException catch (error, stackTrace) {
        if (_connectivityErrorCodes.contains(error.code)) rethrow;
        developer.log(
          'Falha ao enviar categoria ${category.id} (${error.code}): ${error.message}',
          name: 'SyncService',
          error: error,
          stackTrace: stackTrace,
        );
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }

    return pushed;
  }

  Future<int> _pushNotes(String userId) async {
    var pushed = 0;
    Object? firstFailure;
    StackTrace? firstStackTrace;

    final pendingUploads = await _localNotes.query(
      userId: userId,
      syncStatus: SyncStatus.pendingUpload,
    );
    for (final note in pendingUploads) {
      try {
        await _remoteNotes.upsert(note);
        await _localNotes.markAsSynced(note);
        pushed++;
      } on TimeoutException {
        rethrow;
      } on FirebaseException catch (error, stackTrace) {
        if (_connectivityErrorCodes.contains(error.code)) rethrow;
        developer.log(
          'Falha ao enviar nota ${note.id} (${error.code}): ${error.message}',
          name: 'SyncService',
          error: error,
          stackTrace: stackTrace,
        );
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    final pendingDeletes = await _localNotes.query(
      userId: userId,
      syncStatus: SyncStatus.pendingDelete,
    );
    for (final note in pendingDeletes) {
      try {
        await _remoteNotes.delete(userId, note.id);
        await _localNotes.delete(note.id);
        pushed++;
      } on TimeoutException {
        rethrow;
      } on FirebaseException catch (error, stackTrace) {
        if (_connectivityErrorCodes.contains(error.code)) rethrow;
        developer.log(
          'Falha ao excluir nota remota ${note.id} (${error.code}): ${error.message}',
          name: 'SyncService',
          error: error,
          stackTrace: stackTrace,
        );
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }

    return pushed;
  }
}
