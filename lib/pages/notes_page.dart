import 'dart:async';
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

class _NotesPageState extends State<NotesPage> with WidgetsBindingObserver {
  final NoteLocalRepository repository = NoteLocalRepository();
  final CategoryLocalRepository categoryRepository = CategoryLocalRepository();
  final SyncService syncService = SyncService();
  final AuthService authService = AuthService();
  final TextEditingController searchController = TextEditingController();

  List<NoteModel> notes = [];
  List<CategoryModel> categories = [];
  String? selectedCategoryId;
  bool showArchived = false;
  bool isSyncing = false;
  bool hasPendingSync = false;
  int _loadRequest = 0;
  Timer? _pendingRetryTimer;

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
    WidgetsBinding.instance.addObserver(this);
    _initializePage();
  }

  Future<void> _initializePage() async {
    await loadNotes();
    await syncNotes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingRetryTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncNotes(showOfflineSnackBar: false);
    }
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
        isArchived: showArchived,
      );
      final pending = await syncService.hasPendingChanges(user.uid);

      if (mounted && request == _loadRequest) {
        setState(() {
          categories = loadedCategories;
          notes = result;
          hasPendingSync = pending;
        });
        _configurePendingRetryTimer(pending);
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

  void _configurePendingRetryTimer(bool shouldRun) {
    if (shouldRun) {
      _pendingRetryTimer ??= Timer.periodic(
        const Duration(seconds: 15),
        (_) => syncNotes(showOfflineSnackBar: false),
      );
    } else {
      _pendingRetryTimer?.cancel();
      _pendingRetryTimer = null;
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

  Future<void> syncNotes({
    bool isManual = false,
    bool showOfflineSnackBar = true,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      setState(() => isSyncing = true);
    }

    try {
      final report = await syncService.sync(user.uid);

      if (report.state == SyncState.completed || report.pushedCount > 0) {
        await loadNotes();
      } else {
        final pending = await syncService.hasPendingChanges(user.uid);
        if (mounted) {
          setState(() => hasPendingSync = pending);
          _configurePendingRetryTimer(pending);
        }
      }

      if (!mounted) return;

      switch (report.state) {
        case SyncState.completed:
          if (isManual) {
            final message = report.pushedCount > 0
                ? 'Sincronização concluída (${report.pushedCount} pendência(s) enviada(s)).'
                : 'Sincronização concluída.';
            _showFeedback(message);
          } else if (!showOfflineSnackBar && report.pushedCount > 0) {
            _showFeedback('Conexão restabelecida: alterações sincronizadas.');
          }
        case SyncState.offline:
          if (isManual || showOfflineSnackBar) {
            _showFeedback(
              'Sem conexão. As alterações serão sincronizadas quando a rede voltar.',
            );
          }
        case SyncState.failed:
          _showFeedback(
            'Falha ao sincronizar: ${report.errorMessage ?? 'erro desconhecido'}',
          );
      }
    } catch (error, stackTrace) {
      _handleFailure(
        'Falha na sincronização',
        'Falha ao sincronizar: $error',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => isSyncing = syncService.isSyncing);
      }
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: isDestructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(dialogContext).colorScheme.error,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> deleteNote(String id) async {
    final confirmed = await _confirmAction(
      title: 'Excluir nota',
      message: 'Tem certeza de que deseja excluir esta nota permanentemente?',
      confirmLabel: 'Excluir',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await repository.markAsDeleted(id);
      await loadNotes();
      if (mounted) {
        _showFeedback('Nota deletada com sucesso!');
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

  Future<void> toggleArchive(NoteModel note) async {
    final archiving = !note.isArchived;
    final confirmed = await _confirmAction(
      title: archiving ? 'Arquivar nota' : 'Restaurar nota',
      message: archiving
          ? 'Deseja mover esta nota para as notas arquivadas?'
          : 'Deseja restaurar esta nota para a lista principal?',
      confirmLabel: archiving ? 'Arquivar' : 'Restaurar',
    );
    if (!confirmed || !mounted) return;

    try {
      await repository.update(
        note.copyWith(
          isArchived: archiving,
          updatedAt: DateTime.now(),
          syncStatus: SyncStatus.pendingUpload,
        ),
      );
      await loadNotes();
      if (mounted) {
        _showFeedback(archiving ? 'Nota arquivada.' : 'Nota restaurada.');
      }
    } catch (error, stackTrace) {
      _handleFailure(
        'Falha ao alterar arquivamento',
        'Não foi possível alterar o arquivamento da nota.',
        error,
        stackTrace,
      );
      return;
    }

    await syncNotes();
  }

  void toggleArchivedView() {
    showArchived = !showArchived;
    loadNotes();
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    _showFeedback(feedback);
  }

  Future<void> logout() async {
    await authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
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
      MaterialPageRoute(builder: (_) => const NoteFormPage()),
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
          showArchived ? 'Notas arquivadas' : 'Minhas notas',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: hasPendingSync
                ? 'Sincronizar pendências'
                : 'Sincronizar agora',
            onPressed: isSyncing ? null : () => syncNotes(isManual: true),
            icon: isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(
                    hasPendingSync
                        ? Icons.cloud_upload_outlined
                        : Icons.sync_rounded,
                  ),
          ),
          IconButton(
            tooltip: showArchived ? 'Ver notas ativas' : 'Ver notas arquivadas',
            onPressed: toggleArchivedView,
            icon: Icon(
              showArchived
                  ? Icons.sticky_note_2_outlined
                  : Icons.archive_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openNewNote,
        backgroundColor: const Color(0xff6c4ab6),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nova Nota',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.email ?? '',
              style: const TextStyle(color: Color(0xFF77717f), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              onChanged: (_) {
                setState(() {});
                loadNotes();
              },
              decoration: InputDecoration(
                hintText: 'Buscar por título ou conteúdo',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          searchController.clear();
                          setState(() {});
                          loadNotes();
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Todas'),
                      selected: selectedCategoryId == null,
                      onSelected: (_) => selectCategory(null),
                    ),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
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
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => syncNotes(isManual: true),
                child: notes.isEmpty
                    ? LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 100,
                                    height: 100,
                                    decoration: const BoxDecoration(
                                      color: Color(0xffede5fa),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      hasActiveFilters
                                          ? Icons.search_off_rounded
                                          : showArchived
                                          ? Icons.archive_outlined
                                          : Icons.sticky_note_2_rounded,
                                      color: const Color(0xff6c4ab6),
                                    ),
                                  ),
                                  const SizedBox(height: 25),
                                  Text(
                                    hasActiveFilters
                                        ? 'Nenhuma nota encontrada'
                                        : showArchived
                                        ? 'Nenhuma nota arquivada'
                                        : 'Nenhuma nota ainda',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    hasActiveFilters
                                        ? 'Ajuste a busca ou a categoria selecionada.'
                                        : showArchived
                                        ? 'Arquive notas para vê-las aqui.'
                                        : 'Crie sua primeira nota.',
                                  ),
                                  if (hasActiveFilters)
                                    TextButton(
                                      onPressed: clearFilters,
                                      child: const Text('Limpar filtros'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final note = notes[index];

                          return NoteCard(
                            note: note,
                            categoryName: categoryNameOf(note.categoryId),
                            onTap: () => openEditNote(note),
                            onArchive: () => toggleArchive(note),
                            onDelete: () => deleteNote(note.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
