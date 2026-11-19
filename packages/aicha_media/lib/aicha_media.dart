import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Micro et lecteur audio (code Android dans android/src).
class AichaMedia {
  static const _ch = MethodChannel('aicha_media');
  static void Function()? _onDone;
  static bool _init = false;

  static void _setup() {
    if (_init) return;
    _init = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'net') {
        online.value = call.arguments == true;
        return;
      }
      if (call.method == 'done') {
        final f = _onDone;
        _onDone = null;
        f?.call();
      }
    });
  }

  /// true si le micro est déjà autorisé (sans rien demander).
  static Future<bool> hasMic() async =>
      (await _ch.invokeMethod<bool>('hasMic')) ?? false;

  /// true si le micro est autorisé ; sinon la demande est affichée.
  static Future<bool> askMic() async =>
      (await _ch.invokeMethod<bool>('askMic')) ?? false;

  static Future<void> start(String path) =>
      _ch.invokeMethod('start', {'path': path});

  /// Arrête l'enregistrement. false si trop court ou en échec.
  static Future<bool> stop() async =>
      (await _ch.invokeMethod<bool>('stop')) ?? false;

  /// Lit un fichier ; [onDone] est appelé à la fin. Renvoie la durée (ms).
  static Future<int> play(String path, {void Function()? onDone}) async {
    _setup();
    final old = _onDone;
    _onDone = null;
    old?.call();
    final d = await _ch.invokeMethod<int>('play', {'path': path}) ?? 0;
    _onDone = onDone;
    return d;
  }

  static Future<void> stopPlay() async {
    final f = _onDone;
    _onDone = null;
    await _ch.invokeMethod('stopPlay');
    f?.call();
  }

  /// Sonnerie du téléphone (appel entrant) + vibration.
  static Future<void> ring() => _ch.invokeMethod('ring');
  static Future<void> stopRing() => _ch.invokeMethod('stopRing');

  /// Position de lecture du message vocal (ms) et durée totale (ms).
  static Future<(int, int)> position() async {
    final m = await _ch.invokeMapMethod<String, int>('position') ?? const {};
    return (m['position'] ?? 0, m['duration'] ?? 0);
  }

  /// Ouvre les paramètres de l'application (autoriser le micro).
  static Future<void> openSettings() => _ch.invokeMethod('openSettings');

  /// Appel entrant application fermée : notification plein écran + sonnerie.
  static Future<void> showIncomingCall(String callId, String title, String body) =>
      _ch.invokeMethod('showIncomingCall',
          {'callId': callId, 'title': title, 'body': body});

  static Future<void> cancelIncomingCall() => _ch.invokeMethod('cancelIncomingCall');

  /// Afficher l'application par-dessus l'écran verrouillé.
  static Future<void> showOnLock(bool on) =>
      _ch.invokeMethod('showOnLock', {'on': on});

  /// Chiffre sur l'icône de l'application (0 = effacer).
  static Future<void> setBadge(int count, String text) =>
      _ch.invokeMethod('setBadge', {'count': count, 'text': text});

  /// Tonalité « ça sonne » pour l'appelant.
  static Future<void> ringback() => _ch.invokeMethod('ringback');

  /// Tonalité « occupé » (2,5 s) : appel refusé ou correspondant occupé.
  static Future<void> busyTone() => _ch.invokeMethod('busyTone');

  static Future<void> stopTone() => _ch.invokeMethod('stopTone');

  /// État de la connexion Internet (mis à jour automatiquement).
  static final online = ValueNotifier<bool>(true);

  /// Commence à suivre la connexion (à appeler une fois au démarrage).
  static Future<void> watchNetwork() async {
    _setup();
    try {
      online.value = (await _ch.invokeMethod<bool>('watchNet')) ?? true;
    } catch (_) {}
    // Android 6 : pas de suivi automatique, on vérifie toutes les 10 s.
    Stream.periodic(const Duration(seconds: 10)).listen((_) async {
      try {
        online.value = (await _ch.invokeMethod<bool>('isOnline')) ?? true;
      } catch (_) {}
    });
  }
}
