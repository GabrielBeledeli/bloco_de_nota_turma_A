import '../utils/id_generator.dart';

enum SyncStatus { synced, pendingUpload, pendingDelete }

class NoteModel {
  final String id;
  final String title;
  final String content;
  final String? categoryId;
  final String userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isArchived;

  const NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.syncStatus = SyncStatus.pendingUpload,
    this.isArchived = false,
  });

  factory NoteModel.create({
    required String userId,
    required String title,
    required String content,
    String? categoryId,
  }) {
    final now = DateTime.now();

    return NoteModel(
      id: generateId(now),
      title: title,
      content: content,
      userId: userId,
      categoryId: categoryId,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      categoryId: map['category_id'] as String?,
      userId: map['user_id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.values.byName(map['sync_status'] as String),
      isArchived: (map['is_archived'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category_id': categoryId,
      'user_id': userId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'sync_status': syncStatus.name,
      'is_archived': isArchived ? 1 : 0,
    };
  }

  NoteModel copyWith({
    String? title,
    String? content,
    String? Function()? categoryId,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isArchived,
  }) {
    return NoteModel(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
