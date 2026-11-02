import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../models/note_model.dart';
import '../repositories/category_local_repository.dart';
import '../repositories/note_local_repository.dart';
import '../widgets/category_name_dialog.dart';

class NoteFormPage extends StatefulWidget {
  final NoteModel? note;

  const NoteFormPage({super.key, this.note});

  @override
  State<NoteFormPage> createState() => _NoteFormPageState();
}

class _NoteFormPageState extends State<NoteFormPage> {
  final titleController = TextEditingController();

  final contentController = TextEditingController();

  final repository = NoteLocalRepository();

  final categoryRepository = CategoryLocalRepository();

  List<CategoryModel> categories = [];

  String? selectedCategoryId;

  bool get isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      titleController.text = widget.note!.title;

      contentController.text = widget.note!.content;

      selectedCategoryId = widget.note!.categoryId;
    }

    loadCategories();
  }

  Future<void> loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await categoryRepository.ensureDefaults(user.uid);
      final result = await categoryRepository.getAll(user.uid);

      if (mounted) {
        setState(() {
          categories = result;
        });
      }
    } catch (error, stackTrace) {
      _reportFailure(
        'Falha ao carregar categorias',
        'Não foi possível carregar as categorias.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> createCategory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CategoryNameDialog(),
    );
    if (name == null || name.isEmpty) return;

    final existing = categories.where(
      (category) => category.name.toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      setState(() => selectedCategoryId = existing.first.id);
      return;
    }

    try {
      final category = CategoryModel.create(userId: user.uid, name: name);
      await categoryRepository.insert(category);
      await loadCategories();

      if (mounted) {
        setState(() => selectedCategoryId = category.id);
      }
    } catch (error, stackTrace) {
      _reportFailure(
        'Falha ao criar categoria',
        'Não foi possível criar a categoria.',
        error,
        stackTrace,
      );
    }
  }

  void _reportFailure(
    String logMessage,
    String feedback,
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      logMessage,
      name: 'NoteFormPage',
      error: error,
      stackTrace: stackTrace,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(feedback)));
    }
  }

  Future<void> saveNote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final title = titleController.text.trim();
    final content = contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite o conteúdo da nota antes de salvar.'),
        ),
      );
      return;
    }

    try {
      if (isEditing) {
        await repository.update(
          widget.note!.copyWith(
            title: title,
            content: content,
            categoryId: () => selectedCategoryId,
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.pendingUpload,
          ),
        );
      } else {
        await repository.insert(
          NoteModel.create(
            userId: user.uid,
            title: title,
            content: content,
            categoryId: selectedCategoryId,
          ),
        );
      }
    } catch (error, stackTrace) {
      _reportFailure(
        'Falha ao salvar nota',
        'Não foi possível salvar a nota.',
        error,
        stackTrace,
      );
      return;
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Editar nota' : 'Nova nota',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            onPressed: saveNote,
            icon: const Icon(Icons.check_rounded),
          ),

          const SizedBox(width: 8),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(22),

        child: Column(
          children: [
            TextField(
              controller: titleController,

              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF292333),
              ),

              decoration: const InputDecoration(
                hintText: 'Título',
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
            ),

            const Divider(color: Color(0xFFE4DFEA)),

            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category.name),
                        selected: selectedCategoryId == category.id,
                        onSelected: (selected) => setState(
                          () => selectedCategoryId = selected
                              ? category.id
                              : null,
                        ),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Nova categoria'),
                    onPressed: createCategory,
                  ),
                ],
              ),
            ),

            Expanded(
              child: TextField(
                controller: contentController,

                maxLines: null,

                expands: true,

                textAlignVertical: TextAlignVertical.top,

                style: const TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: Color(0xFF40394A),
                ),

                decoration: const InputDecoration(
                  hintText: 'Comece a escrever...',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
