import 'dart:developer' as developer;

import 'package:bloco_de_nota_turma_a/models/note_model.dart';
import 'package:bloco_de_nota_turma_a/pages/login_page.dart';
import 'package:bloco_de_nota_turma_a/pages/note_form_page.dart';
import 'package:bloco_de_nota_turma_a/repositories/note_local_repository.dart';
import 'package:bloco_de_nota_turma_a/services/auth_service.dart';
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
  final AuthService authService = AuthService();

  List<NoteModel> notes = [];
  @override
  void initState() {
    super.initState();
    loadNotes();
  }

  Future<void> loadNotes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final result = await repository.getAll(user.uid);

      if (mounted) {
        setState(() {
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

  Future<void> deleteNote(String id) async {
    try {
      await repository.delete(id);
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
    }
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
  }

  Future<void> openNewNote() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteFormPage()),
    );

    await loadNotes();
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
            SizedBox(height: 20),
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
                          Icons.sticky_note_2_rounded,
                          color: Color(0xffede5fa),
                        ),
                      ),
                      SizedBox(height: 25),
                      Text("Nenhuma nota ainda"),
                      SizedBox(height: 8),
                      Text('Crie sua primeira nota.'),
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
