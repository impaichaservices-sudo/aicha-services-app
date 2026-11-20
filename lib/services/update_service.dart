import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:aicha_media/aicha_media.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../nav.dart';

/// Mises à jour : chaque compilation publie une nouvelle version.
/// L'application la télécharge elle-même (barre de progression) puis lance
/// l'installation, par-dessus l'ancienne version.
class UpdateService {
  /// Numéro de cette version (fourni lors de la compilation).
  static const build = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
  static const _repo = 'impaichaservices-sudo/aicha-services-app';
  static const _base = 'https://github.com/$_repo/releases/latest/download/';

  /// APK léger adapté au téléphone (64 bits ou anciens 32 bits).
  /// En cas de doute : la version universelle, qui marche partout.
  static Future<String> apkUrl() async {
    final abis = await AichaMedia.abis();
    if (abis.contains('arm64-v8a')) return '${_base}aicha-services-arm64.apk';
    if (abis.contains('armeabi-v7a')) return '${_base}aicha-services-arm32.apk';
    return '${_base}aicha-services.apk';
  }

  /// Dernier numéro connu (null = pas encore vérifié).
  static final latestKnown = ValueNotifier<int?>(null);
  static int latestSize = 0; // octets
  static String latestNotes = '';
  static bool get hasUpdate => (latestKnown.value ?? 0) > build && build > 0;

  static bool _askedOnStart = false;
  static bool _dialogOpen = false;

  /// Dernier numéro publié (0 si inconnu / pas d'internet).
  static Future<int> latest() async {
    try {
      final r = await http
          .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return 0;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final n = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      latestNotes = ((j['body'] ?? '') as String).trim();
      latestSize = 0;
      for (final a in (j['assets'] as List? ?? const [])) {
        final m = a as Map<String, dynamic>;
        final name = (m['name'] ?? '').toString();
        if (name.endsWith('.apk') && (latestSize == 0 || name.contains('arm64'))) {
          latestSize = (m['size'] as num?)?.toInt() ?? 0;
        }
      }
      if (n > 0) latestKnown.value = n;
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Au démarrage (une fois) : propose la mise à jour si elle existe.
  static Future<void> checkOnStart() async {
    if (_askedOnStart || build == 0) return;
    _askedOnStart = true;
    _cleanOld();
    final last = await latest();
    if (last > build) _ask(last);
  }

  /// Bouton « Mettre à jour l'application » du menu.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Recherche d\'une nouvelle version…')));
    final last = await latest();
    messenger.hideCurrentSnackBar();
    if (last == 0) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Vérification impossible : vérifiez votre connexion internet.')));
    } else if (last > build && build > 0) {
      _ask(last);
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text('Votre application est à jour ✅ '
              '(version ${AppConfig.versionName})')));
    }
  }

  static void _ask(int last) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || _dialogOpen) return;
    _dialogOpen = true;
    showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.system_update, color: AppConfig.green, size: 42),
        title: const Text('Nouvelle mise à jour disponible'),
        content: SingleChildScrollView(
          child: Text(
              'Une nouvelle mise à jour de l\'application est prête.\n'
              '${latestSize > 0 ? 'Taille : ${(latestSize / (1024 * 1024)).toStringAsFixed(1)} Mo\n' : ''}'
              '${latestNotes.isNotEmpty ? '\nNouveautés :\n$latestNotes\n' : ''}'
              '\nLe téléchargement se fait dans l\'application, puis '
              'l\'installation démarre automatiquement. '
              'Vos commandes et messages sont conservés.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Plus tard')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Mettre à jour')),
        ],
      ),
    ).then((go) {
      _dialogOpen = false;
      final c2 = navigatorKey.currentContext;
      if (go == true && c2 != null) {
        showDialog<void>(
          context: c2,
          barrierDismissible: false,
          builder: (_) => _UpdateDialog(version: last),
        );
      }
    });
  }

  /// Supprime les fichiers d'installation déjà utilisés (place libérée).
  static Future<void> _cleanOld() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final f in dir.listSync()) {
        final m = RegExp(r'aicha_services_v(\d+)\.apk').firstMatch(f.path);
        if (m != null && (int.tryParse(m.group(1)!) ?? 0) <= build) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  /// Fichier de la nouvelle version sur le téléphone.
  static Future<File> _file(int version) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aicha_services_v$version.apk');
  }
}

/// Petite fenêtre : progression du téléchargement puis installation.
class _UpdateDialog extends StatefulWidget {
  final int version;
  const _UpdateDialog({required this.version});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _Step { downloading, installing, needPermission, error }

class _UpdateDialogState extends State<_UpdateDialog> {
  _Step _step = _Step.downloading;
  double? _progress; // null = taille inconnue
  int _received = 0;
  String _error = '';
  http.Client? _client;
  bool _cancelled = false;
  File? _apk;

  @override
  void initState() {
    super.initState();
    _download();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _step = _Step.downloading;
      _progress = null;
      _received = 0;
    });
    try {
      final file = await UpdateService._file(widget.version);
      final part = File('${file.path}.part');
      if (!await file.exists()) {
        _client = http.Client();
        final res = await _client!
            .send(http.Request('GET', Uri.parse(await UpdateService.apkUrl())))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw Exception('serveur indisponible (${res.statusCode})');
        }
        final total = res.contentLength ?? 0;
        final sink = part.openWrite();
        try {
          await for (final chunk in res.stream) {
            if (_cancelled) break;
            sink.add(chunk);
            _received += chunk.length;
            if (mounted) {
              setState(() => _progress = total > 0 ? _received / total : null);
            }
          }
        } finally {
          await sink.close();
        }
        if (_cancelled) {
          if (await part.exists()) await part.delete();
          return;
        }
        if (total > 0 && _received < total) {
          throw Exception('téléchargement interrompu');
        }
        await part.rename(file.path);
      }
      _apk = file;
      await _install();
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() {
        _step = _Step.error;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _install() async {
    final f = _apk;
    if (f == null) return;
    if (mounted) setState(() => _step = _Step.installing);
    final r = await OpenFilex.open(f.path,
        type: 'application/vnd.android.package-archive');
    if (!mounted) return;
    if (r.type == ResultType.done) {
      // L'écran d'installation d'Android s'ouvre par-dessus.
      Navigator.of(context).pop();
    } else {
      // Première fois : Android demande d'autoriser l'installation.
      setState(() => _step = _Step.needPermission);
    }
  }

  String get _mb => (_received / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final List<Widget> actions;
    switch (_step) {
      case _Step.downloading:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: _progress, minHeight: 10, color: AppConfig.green),
          ),
          const SizedBox(height: 12),
          Text(
            _progress != null
                ? '${(_progress! * 100).round()} %  •  $_mb Mo'
                : '$_mb Mo',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text('Gardez l\'application ouverte.',
              style: TextStyle(color: Colors.black54)),
        ]);
        actions = [
          TextButton(
            onPressed: () {
              _cancelled = true;
              _client?.close();
              Navigator.of(context).pop();
            },
            child: const Text('Annuler'),
          ),
        ];
        break;
      case _Step.installing:
        body = const Row(children: [
          SizedBox(
              width: 26, height: 26,
              child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(width: 16),
          Expanded(child: Text('Ouverture de l\'installation…')),
        ]);
        actions = const [];
        break;
      case _Step.needPermission:
        body = const Text(
            'Dernière étape (une seule fois) :\n\n'
            '1. Sur l\'écran qui s\'est ouvert, activez « Autoriser cette source » '
            'pour Aïcha Services.\n'
            '2. Revenez ici et touchez « Installer ».');
        actions = [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Plus tard')),
          FilledButton(onPressed: _install, child: const Text('Installer')),
        ];
        break;
      case _Step.error:
        body = Text('Le téléchargement a échoué : $_error.\n\n'
            'Vérifiez votre connexion internet puis réessayez.');
        actions = [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer')),
          FilledButton(onPressed: _download, child: const Text('Réessayer')),
        ];
        break;
    }
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(children: [
          const Icon(Icons.system_update, color: AppConfig.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _step == _Step.downloading
                  ? 'Téléchargement de la mise à jour'
                  : 'Mise à jour de l\'application',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ]),
        content: body,
        actions: actions,
      ),
    );
  }
}

/// Ligne du menu Profil : « Mettre à jour l'application ».
class UpdateTile extends StatefulWidget {
  const UpdateTile({super.key});

  @override
  State<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<UpdateTile> {
  @override
  void initState() {
    super.initState();
    if (UpdateService.latestKnown.value == null) UpdateService.latest();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: UpdateService.latestKnown,
      builder: (context, last, _) {
        final available = UpdateService.hasUpdate;
        final String sub;
        if (UpdateService.build == 0) {
          sub = 'Vérifier les nouvelles versions';
        } else if (last == null) {
          sub = 'Version ${AppConfig.versionName}';
        } else if (available) {
          sub = 'Nouvelle mise à jour disponible';
        } else {
          sub = 'Version ${AppConfig.versionName} • à jour ✅';
        }
        return ListTile(
          leading: Badge(
            isLabelVisible: available,
            smallSize: 10,
            child: const Icon(Icons.system_update_rounded, color: AppConfig.green),
          ),
          title: const Text('Mettre à jour l\'application',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub,
              style: TextStyle(
                  color: available ? AppConfig.green : null,
                  fontWeight: available ? FontWeight.w700 : null)),
          trailing: available
              ? FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                  onPressed: () => UpdateService.checkNow(context),
                  child: const Text('Installer'),
                )
              : const Icon(Icons.chevron_right),
          onTap: () => UpdateService.checkNow(context),
        );
      },
    );
  }
}
