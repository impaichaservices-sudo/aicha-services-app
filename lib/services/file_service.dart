import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class PickedUpload {
  final String name;
  final String url; // "blob:<id>"
  final int size;
  const PickedUpload(this.name, this.url, this.size);
}

/// Fichiers (photos, PDF, Word…) enregistrés directement dans Firestore,
/// découpés en morceaux : aucun service externe, aucune carte bancaire.
///   blobs/{id}            : nom, taille, propriétaire, boutique, discussion
///   blobs/{id}/chunks/{i} : morceaux de 700 Ko
class FileService {
  static const maxBytes = 15 * 1024 * 1024; // 15 Mo
  static const _chunk = 700 * 1024;
  static const allowed = [
    'jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  ];

  static final _fs = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get blobs =>
      _fs.collection('blobs');

  /// Toujours disponible (aucune configuration nécessaire).
  static Future<bool> enabled() async => true;

  /// Choisit un fichier puis l'enregistre. Renvoie null si l'utilisateur annule.
  static Future<PickedUpload?> pickAndUpload({
    required String shopId,
    required String conversationId,
  }) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowed,
      withData: true,
    );
    final f = res?.files.single;
    if (f == null) return null;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) throw Exception('Fichier illisible.');
    return uploadBytes(
      bytes: bytes,
      name: f.name,
      shopId: shopId,
      conversationId: conversationId,
    );
  }

  /// Enregistre des octets (fichier, photo, plus tard message vocal).
  static Future<PickedUpload> uploadBytes({
    required Uint8List bytes,
    required String name,
    required String shopId,
    required String conversationId,
  }) async {
    if (bytes.length > maxBytes) {
      throw Exception('Fichier trop lourd (15 Mo maximum). '
          'Envoyez-le plutôt par WhatsApp.');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ref = blobs.doc();
    final count = (bytes.length / _chunk).ceil();
    // Plusieurs envois de 5 morceaux (≈3,5 Mo) : Firestore limite la taille
    // d'un envoi à 10 Mo.
    var batch = _fs.batch();
    batch.set(ref, {
      'ownerId': uid,
      'shopId': shopId,
      'conversationId': conversationId,
      'name': name,
      'size': bytes.length,
      'chunks': count,
      'createdAt': FieldValue.serverTimestamp(),
    });
    var inBatch = 0;
    for (var i = 0; i < count; i++) {
      final end = (i + 1) * _chunk > bytes.length ? bytes.length : (i + 1) * _chunk;
      batch.set(ref.collection('chunks').doc('$i'), {
        'i': i,
        'data': Blob(Uint8List.fromList(bytes.sublist(i * _chunk, end))),
      });
      inBatch++;
      if (inBatch == 5 && i < count - 1) {
        await batch.commit();
        batch = _fs.batch();
        inBatch = 0;
      }
    }
    await batch.commit();
    return PickedUpload(name, 'blob:${ref.id}', bytes.length);
  }

  /// Type d'affichage selon l'extension : image, audio, video ou doc.
  static String kindOf(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) return 'image';
    if (['m4a', 'aac', 'mp3', 'ogg', 'wav', 'amr'].contains(ext)) return 'audio';
    if (['mp4', '3gp', 'mov', 'mkv', 'webm'].contains(ext)) return 'video';
    return 'doc';
  }

  static final Map<String, Future<Uint8List>> _cache = {};

  /// Contenu du fichier (gardé en mémoire pour les petites images).
  static Future<Uint8List> load(String url) {
    final f = _cache[url] ??= _download(url);
    f.catchError((_) {
      _cache.remove(url);
      return Uint8List(0);
    });
    return f;
  }

  static Future<Uint8List> _download(String url) async {
    if (!url.startsWith('blob:')) {
      throw Exception('Lien de fichier inconnu.');
    }
    final id = url.substring(5);
    final meta = await blobs.doc(id).get();
    if (!meta.exists) throw Exception('Fichier introuvable.');
    final count = (meta.data()?['chunks'] as num?)?.toInt() ?? 0;
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      final c = await blobs.doc(id).collection('chunks').doc('$i').get();
      final data = c.data()?['data'];
      if (data is Blob) out.addAll(data.bytes);
    }
    return Uint8List.fromList(out);
  }

  /// Fichier enregistré sur le téléphone (téléchargé une seule fois).
  static Future<String> localPath(String url, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = url.startsWith('blob:') ? url.substring(5) : 'f';
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/${id}_$safe');
    if (await file.exists() && await file.length() > 0) return file.path;
    final bytes = await _download(url);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Télécharge le fichier sur le téléphone puis l'ouvre (le lecteur du
  /// téléphone permet ensuite de l'enregistrer ou de le partager).
  static Future<void> open(String url, String name) async {
    final path = await localPath(url, name);
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done) {
      throw Exception('Aucune application pour ouvrir ce fichier.');
    }
  }
}
