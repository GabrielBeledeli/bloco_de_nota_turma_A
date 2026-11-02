import '../utils/id_generator.dart';
import 'note_model.dart';

class CategoryModel {
  final String id;
  final String name;
  final String userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pendingUpload,
  });

  factory CategoryModel.create({required String userId, required String name}) {
    final now = DateTime.now();

    return CategoryModel(
      id: generateId(now),
      name: name,
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      userId: map['user_id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.values.byName(map['sync_status'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'user_id': userId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'sync_status': syncStatus.name,
    };
  }
}
