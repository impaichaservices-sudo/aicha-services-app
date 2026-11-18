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
}
