import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note_model.dart';

class RemoteNoteService {
  RemoteNoteService({FirebaseFirestore? firestore, Duration? timeout})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _timeout = timeout ?? const Duration(seconds: 10);

  final FirebaseFirestore _firestore;
  final Duration _timeout;

  CollectionReference<Map<String, dynamic>> _notes(String userId) {
    return _firestore.collection('users').doc(userId).collection('notes');
  }

  Future<void> resetConnection() async {
    await _firestore.disableNetwork();
    await _firestore.enableNetwork();
  }

  Future<void> upsert(NoteModel note) {
    return _notes(
      note.userId,
    ).doc(note.id).set(_toDocument(note)).timeout(_timeout);
  }

  Future<void> delete(String userId, String noteId) {
    return _notes(userId).doc(noteId).delete().timeout(_timeout);
  }

  Future<NoteModel?> getById(String userId, String noteId) async {
    final snapshot = await _notes(userId)
        .doc(noteId)
        .get(const GetOptions(source: Source.server))
        .timeout(_timeout);

    final data = snapshot.data();
    return data == null ? null : _fromDocument(snapshot.id, userId, data);
  }

  Future<List<NoteModel>> getAll(String userId) async {
    final snapshot = await _notes(
      userId,
    ).get(const GetOptions(source: Source.server)).timeout(_timeout);

    return snapshot.docs
        .map((doc) => _fromDocument(doc.id, userId, doc.data()))
        .toList();
  }

  Map<String, dynamic> _toDocument(NoteModel note) {
    return {
      'title': note.title,
      'content': note.content,
      'categoryId': note.categoryId,
      'userId': note.userId,
      'createdAt': Timestamp.fromDate(note.createdAt),
      'updatedAt': Timestamp.fromDate(note.updatedAt),
      'isArchived': note.isArchived,
    };
  }

  NoteModel _fromDocument(
    String id,
    String fallbackUserId,
    Map<String, dynamic> data,
  ) {
    final now = DateTime.now();
    return NoteModel(
      id: id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      categoryId: data['categoryId'] as String?,
      userId: data['userId'] as String? ?? fallbackUserId,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? now,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? now,
      syncStatus: SyncStatus.synced,
      isArchived: data['isArchived'] as bool? ?? false,
    );
  }
}
