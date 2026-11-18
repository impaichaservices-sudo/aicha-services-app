import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../models/shop_settings.dart';
import 'db.dart';

class PickedUpload {
  final String name;
  final String url;
  final int size;
  const PickedUpload(this.name, this.url, this.size);
}

/// Envoi de fichiers (JPG, PNG, PDF, DOCX…) vers Cloudinary (gratuit, sans carte).
/// Le compte se configure dans Gestion → Paramètres (nom du cloud + preset).
class FileService {
  static const maxBytes = 10 * 1024 * 1024; // 10 Mo (limite du compte gratuit)
  static const allowed = ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'zip'];

  static Future<ShopSettings> _settings() async =>
      ShopSettings.fromDoc(await Db.settingsDoc.get());

  static Future<bool> enabled() async => (await _settings()).filesEnabled;

  /// Choisit un fichier puis l'envoie. Renvoie null si l'utilisateur annule.
  /// Lève une Exception avec un message en français en cas de problème.
  static Future<PickedUpload?> pickAndUpload({required String folder}) async {
    final s = await _settings();
    if (!s.filesEnabled) {
      throw Exception('L\'envoi de fichiers n\'est pas encore activé.');
    }
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowed,
    );
    final f = res?.files.single;
    if (f == null || f.path == null) return null;
    if (f.size > maxBytes) {
      throw Exception('Fichier trop lourd (10 Mo maximum).');
    }
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/${s.cloudinaryCloud}/auto/upload'),
    )
      ..fields['upload_preset'] = s.cloudinaryPreset
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath('file', File(f.path!).path,
          filename: f.name));
    final streamed = await req.send().timeout(const Duration(minutes: 3));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      String msg = 'Envoi impossible (${streamed.statusCode}).';
      try {
        final e = (jsonDecode(body) as Map)['error'];
        if (e is Map && e['message'] != null) msg = 'Envoi impossible : ${e['message']}';
      } catch (_) {}
      throw Exception(msg);
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = (json['secure_url'] ?? '') as String;
    if (url.isEmpty) throw Exception('Envoi impossible : réponse inattendue.');
    return PickedUpload(f.name, url, f.size);
  }
}
