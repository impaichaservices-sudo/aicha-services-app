import 'package:flutter/material.dart';

import '../config.dart';
import '../models/file_record.dart';
import '../services/db.dart';
import '../services/file_service.dart';
import '../utils.dart';
import '../widgets/common.dart';

/// Profil → Mes fichiers : fichiers envoyés depuis les discussions.
class MyFilesScreen extends StatelessWidget {
  final String uid;
  const MyFilesScreen({super.key, required this.uid});

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png')) {
      return Icons.image_rounded;
    }
    if (n.endsWith('.doc') || n.endsWith('.docx')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String _size(int b) => b >= 1024 * 1024
      ? '${(b / (1024 * 1024)).toStringAsFixed(1)} Mo'
      : '${(b / 1024).ceil()} Ko';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes fichiers')),
      body: StreamBuilder<List<FileRecord>>(
        stream: Db.myFiles(uid),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error), textAlign: TextAlign.center));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_open_rounded,
              title: 'Aucun fichier',
              message:
                  'Envoyez un fichier depuis une discussion (bouton trombone) : il apparaîtra ici.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final f = list[i];
              return Card(
                child: ListTile(
                  leading: Icon(_icon(f.name), color: AppConfig.green, size: 32),
                  title: Text(f.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${_size(f.size)} • ${shortDate(f.createdAt)}'),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await FileService.open(f.url, f.name);
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(
                          content: Text(friendlyError(e))));
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
