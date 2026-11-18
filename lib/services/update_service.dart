import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../nav.dart';

/// Mises à jour : chaque compilation GitHub publie une « Release » avec
/// l'APK. L'application compare son numéro à la dernière version publiée.
class UpdateService {
  /// Numéro de cette version (fourni par GitHub lors de la compilation).
  static const build = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
  static const _repo = 'impaichaservices-sudo/aicha-services-app';
  static const apkUrl =
      'https://github.com/$_repo/releases/latest/download/aicha-services.apk';

  static bool _checked = false;

  /// Dernier numéro publié (0 si inconnu / pas d'internet).
  static Future<int> latest() async {
    try {
      final r = await http
          .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return 0;
      final tag = (jsonDecode(r.body)['tag_name'] ?? '') as String;
      return int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Au démarrage (une fois) : propose la mise à jour si elle existe.
  static Future<void> checkOnStart() async {
    if (_checked || build == 0) return;
    _checked = true;
    final last = await latest();
    if (last > build) _ask(last);
  }

  /// Depuis le profil : « Rechercher une mise à jour ».
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2), content: Text('Recherche…')));
    final last = await latest();
    if (last == 0) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Impossible de vérifier : vérifiez votre connexion.')));
    } else if (last > build) {
      _ask(last);
    } else {
      messenger.showSnackBar(const SnackBar(
          content: Text('Votre application est à jour ✅')));
    }
  }

  static void _ask(int last) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.system_update, color: AppConfig.green, size: 40),
        title: const Text('Nouvelle version disponible'),
        content: Text(
            'La version $last de ${AppConfig.shortName} est prête.\n\n'
            '1. Touchez « Mettre à jour » : le fichier se télécharge.\n'
            '2. Ouvrez-le puis touchez « Mettre à jour » / « Installer ».\n\n'
            'Vos commandes et messages sont conservés.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Plus tard')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('Mettre à jour'),
          ),
        ],
      ),
    );
  }
}
