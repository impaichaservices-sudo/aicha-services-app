import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/notify_service.dart';

/// Vérifie que le téléphone peut sonner pour les appels, même application
/// fermée, et permet de tester.
class CallSettingsScreen extends StatefulWidget {
  const CallSettingsScreen({super.key});

  @override
  State<CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<CallSettingsScreen>
    with WidgetsBindingObserver {
  Map<String, bool> _c = const {};
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Retour des réglages Android : on revérifie.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final c = await AichaMedia.callChecks();
    if (mounted) setState(() => _c = c);
  }

  bool get _allOk =>
      _c.isNotEmpty && _c.values.every((v) => v);

  Widget _item(String key, String title, String why, {bool optional = false}) {
    final ok = _c[key] ?? true;
    return Card(
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: ok ? AppConfig.green : (optional ? Colors.orange : Colors.red),
            size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(ok ? 'Activé ✅' : why),
        trailing: ok
            ? null
            : FilledButton(
                onPressed: () => AichaMedia.openCallSetting(key),
                child: const Text('Activer'),
              ),
      ),
    );
  }

  Future<void> _test({required bool server}) async {
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.of(context);
    var how = 'local';
    if (server) {
      final r = await NotifyService.testCall();
      if (r == 'ok') {
        how = 'server';
      } else {
        messenger.showSnackBar(SnackBar(
            content: Text(r == 'old'
                ? 'Le serveur Cloudflare n\'est pas à jour : test sur ce téléphone seulement.'
                : 'Serveur injoignable : test sur ce téléphone seulement.')));
        await AichaMedia.testIncomingCall();
      }
    } else {
      await AichaMedia.testIncomingCall();
    }
    if (!mounted) return;
    setState(() => _testing = false);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Verrouillez l\'écran maintenant 🔒'),
        content: Text(how == 'server'
            ? 'Appuyez sur le bouton marche/arrêt du téléphone. Dans environ 10 secondes, '
                'un appel test passera par internet : le téléphone doit sonner et '
                'afficher l\'appel en plein écran.'
            : 'Appuyez sur le bouton marche/arrêt du téléphone. Dans 8 secondes, le '
                'téléphone doit sonner et afficher l\'appel en plein écran.'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sonnerie des appels')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _allOk ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _allOk
                    ? 'Tout est prêt : les appels sonneront même application fermée '
                        'et écran éteint.'
                    : 'Activez les réglages en rouge pour que les appels sonnent '
                        'quand l\'application est fermée.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _item('notifications', 'Notifications',
              'Sans elles, aucun appel ne peut sonner.'),
          _item('fullScreen', 'Appel en plein écran',
              'Pour afficher l\'appel sur l\'écran verrouillé.'),
          _item('battery', 'Batterie sans restriction',
              'Sinon le téléphone peut bloquer les appels quand l\'application est fermée.'),
          _item('overlay', 'Afficher par-dessus les autres applis',
              'Pour voir l\'appel en grand même quand vous utilisez le téléphone '
                  '(sinon : petit bandeau en haut).',
              optional: true),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _testing ? null : () => _test(server: true),
            icon: const Icon(Icons.ring_volume_rounded),
            label: const Text('Tester un appel (par internet)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _testing ? null : () => _test(server: false),
            icon: const Icon(Icons.phone_android_rounded),
            label: const Text('Tester la sonnerie sur ce téléphone'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sur certains téléphones (Tecno, Infinix, Itel, Xiaomi…), activez aussi '
            '« Démarrage automatique » pour Aïcha Services dans les réglages du '
            'téléphone, et ne fermez pas l\'application en la balayant.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
