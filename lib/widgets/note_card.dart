import 'package:flutter/material.dart';

import '../models/note_model.dart';

class NoteCard extends StatelessWidget {
  final NoteModel note;
  final String? categoryName;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    this.categoryName,
    required this.onTap,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,

        child: Padding(
          padding: const EdgeInsets.all(20),

          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,

                decoration: BoxDecoration(
                  color: const Color(0xFFEDE5FA),
                  borderRadius: BorderRadius.circular(15),
                ),

                child: const Icon(
                  Icons.notes_rounded,
                  color: Color(0xFF6C4AB6),
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      note.title.isEmpty ? 'Sem título' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF292333),
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      note.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        color: Color(0xFF77717F),
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (categoryName != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE5FA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          categoryName!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6C4AB6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    Row(
                      children: [
                        Text(
                          _formatDate(note.updatedAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9A94A1),
                          ),
                        ),
                        if (note.syncStatus != SyncStatus.synced) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.cloud_upload_outlined,
                            size: 13,
                            color: Color(0xFFB26A00),
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'Pendente',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB26A00),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              IconButton(
                tooltip: note.isArchived ? 'Restaurar' : 'Arquivar',
                onPressed: onArchive,
                icon: Icon(
                  note.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  color: const Color(0xFF6C4AB6),
                ),
              ),

              IconButton(
                tooltip: 'Excluir',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFB45F6C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }
}
