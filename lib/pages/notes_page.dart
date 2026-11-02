import 'dart:developer' as developer;

import 'package:bloco_de_nota_turma_a/models/category_model.dart';
import 'package:bloco_de_nota_turma_a/models/note_model.dart';
import 'package:bloco_de_nota_turma_a/pages/login_page.dart';
import 'package:bloco_de_nota_turma_a/pages/note_form_page.dart';
import 'package:bloco_de_nota_turma_a/repositories/category_local_repository.dart';
import 'package:bloco_de_nota_turma_a/repositories/note_local_repository.dart';
import 'package:bloco_de_nota_turma_a/services/auth_service.dart';
import 'package:bloco_de_nota_turma_a/services/sync_service.dart';
import 'package:bloco_de_nota_turma_a/widgets/note_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final NoteLocalRepository repository = NoteLocalRepository();
  final CategoryLocalRepository categoryRepository = CategoryLocalRepository();
  final SyncService syncService = SyncService();
  final AuthService authService = AuthService();
  final TextEditingController searchController = TextEditingController();

  List<NoteModel> notes = [];
  List<CategoryModel> categories = [];
  String? selectedCategoryId;
  int _loadRequest = 0;

  bool get hasActiveFilters =>
      selectedCategoryId != null || searchController.text.trim().isNotEmpty;

  String? categoryNameOf(String? categoryId) {
    if (categoryId == null) return null;
    for (final category in categories) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    loadNotes().then((_) => syncNotes());
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadNotes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final request = ++_loadRequest;
    try {
      await categoryRepository.ensureDefaults(user.uid);
      final loadedCategories = await categoryRepository.getAll(user.uid);
      final result = await repository.query(
        userId: user.uid,
        searchTerm: searchController.text,
        categoryId: selectedCategoryId,
      );

      if (mounted && request == _loadRequest) {
        setState(() {
          categories = loadedCategories;
          notes = result;
        });
      }
    } catch (error, stackTrace) {
      _handleFailure(
        'Falha ao carregar notas',
        'Não foi possível carregar as notas.',
        error,
        stackTrace,
      );
    }
  }

  void selectCategory(String? categoryId) {
    selectedCategoryId = categoryId;
    loadNotes();
  }

  void clearFilters() {
    searchController.clear();
    selectedCategoryId = null;
    loadNotes();
  }

  Future<void> syncNotes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final result = await syncService.sync(user.uid);

      if (result == SyncResult.completed) {
        await loadNotes();
      } else if (result == SyncResult.offline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sem conexão. As alterações serão sincronizadas depois.',
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      _handleFailure(
        'Falha na sincronização',
        'Não foi possível sincronizar as notas.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> deleteNote(String id) async {
    try {
      await repository.markAsDeleted(id);
      await loadNotes();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Nota deletada com sucesso!")));
      }
    } catch (error, stackTrace) {
      _handleFailure(
        'Falha ao deletar nota',
        'Não foi possível deletar a nota.',
        error,
        stackTrace,
      );
      return;
    }

    await syncNotes();
  }

  void _handleFailure(
    String logMessage,
    String feedback,
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      logMessage,
      name: 'NotesPage',
      error: error,
      stackTrace: stackTrace,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(feedback)));
    }
  }

  Future<void> logout() async {
    await authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
      (route) => false,
    );
  }

  Future<void> openEditNote(NoteModel note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteFormPage(note: note)),
    );

    await loadNotes();
    await syncNotes();
  }

  Future<void> openNewNote() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteFormPage()),
    );

    await loadNotes();
    await syncNotes();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Minhas notas",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: "Sair",
            onPressed: logout,
            icon: Icon(Icons.logout_rounded),
          ),
          SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openNewNote,
        backgroundColor: Color(0xff6c4ab6),
        foregroundColor: Colors.white,
        icon: Icon(Icons.add_rounded),
        label: Text("Nova Nota", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.email ?? "",
              style: TextStyle(color: Color(0xFF77717f), fontSize: 13),
            ),
            SizedBox(height: 16),
            TextField(
              controller: searchController,
              onChanged: (_) {
                setState(() {});
                loadNotes();
              },
              decoration: InputDecoration(
                hintText: 'Buscar por título ou conteúdo',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: Icon(Icons.close_rounded),
                        onPressed: () {
                          searchController.clear();
                          setState(() {});
                          loadNotes();
                        },
                      ),
              ),
            ),
            SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('Todas'),
                      selected: selectedCategoryId == null,
                      onSelected: (_) => selectCategory(null),
                    ),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category.name),
                        selected: selectedCategoryId == category.id,
                        onSelected: (selected) =>
                            selectCategory(selected ? category.id : null),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12),
            if (notes.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,

                        decoration: BoxDecoration(
                          color: Color(0xffede5fa),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasActiveFilters
                              ? Icons.search_off_rounded
                              : Icons.sticky_note_2_rounded,
                          color: Color(0xff6c4ab6),
                        ),
                      ),
                      SizedBox(height: 25),
                      Text(
                        hasActiveFilters
                            ? 'Nenhuma nota encontrada'
                            : 'Nenhuma nota ainda',
                      ),
                      SizedBox(height: 8),
                      Text(
                        hasActiveFilters
                            ? 'Ajuste a busca ou a categoria selecionada.'
                            : 'Crie sua primeira nota.',
                      ),
                      if (hasActiveFilters)
                        TextButton(
                          onPressed: clearFilters,
                          child: Text('Limpar filtros'),
                        ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];

                    return NoteCard(
                      note: note,
                      categoryName: categoryNameOf(note.categoryId),
                      onTap: () => openEditNote(note),
                      onDelete: () => deleteNote(note.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
