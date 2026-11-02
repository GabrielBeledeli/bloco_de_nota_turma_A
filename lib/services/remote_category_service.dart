import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category_model.dart';
import '../models/note_model.dart';

class RemoteCategoryService {
  RemoteCategoryService({FirebaseFirestore? firestore, Duration? timeout})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _timeout = timeout ?? const Duration(seconds: 10);

  final FirebaseFirestore _firestore;
  final Duration _timeout;

  CollectionReference<Map<String, dynamic>> _categories(String userId) {
    return _firestore.collection('users').doc(userId).collection('categories');
  }

  Future<void> upsert(CategoryModel category) {
    return _categories(category.userId)
        .doc(category.id)
        .set({
          'name': category.name,
          'userId': category.userId,
          'createdAt': Timestamp.fromDate(category.createdAt),
          'updatedAt': Timestamp.fromDate(category.updatedAt),
        })
        .timeout(_timeout);
  }

  Future<List<CategoryModel>> getAll(String userId) async {
    final snapshot = await _categories(
      userId,
    ).get(const GetOptions(source: Source.server)).timeout(_timeout);

    final now = DateTime.now();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return CategoryModel(
        id: doc.id,
        name: data['name'] as String? ?? '',
        userId: data['userId'] as String? ?? userId,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? now,
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? now,
        syncStatus: SyncStatus.synced,
      );
    }).toList();
  }
}
