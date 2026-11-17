import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  static String safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static Future<String> upload(File file, String path,
      {String? contentType}) async {
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(
      file,
      contentType == null ? null : SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  /// Fichier joint par un client (document à imprimer, logo…).
  static Future<String> uploadClientFile(String uid, File file, String name) =>
      upload(file,
          'uploads/$uid/${DateTime.now().millisecondsSinceEpoch}_${safeName(name)}');

  /// Photo d'un service du catalogue (patron).
  static Future<String> uploadCatalogImage(File file) => upload(
      file, 'catalog/${DateTime.now().millisecondsSinceEpoch}.jpg',
      contentType: 'image/jpeg');
}
