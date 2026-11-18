import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Vérifie l'autorisation du micro (vocaux et appels).
/// Affiche la demande Android, attend la réponse (20 s max) ; si elle est
/// refusée, explique comment l'autoriser avec un bouton vers les paramètres.
Future<bool> ensureMic(BuildContext context, {String usage = 'passer un appel vocal'}) async {
  try {
    if (await AichaMedia.hasMic()) return true;
    await AichaMedia.askMic();
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await AichaMedia.hasMic()) return true;
    }
  } catch (_) {
    return false;
  }
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.mic_off, color: AppConfig.green, size: 40),
      title: const Text('Microphone nécessaire'),
      content: Text('Le microphone est nécessaire pour $usage. '
          'Autorisez l\'accès au microphone dans les paramètres de votre téléphone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
        FilledButton(
          onPressed: () {
            Navigator.pop(c);
            AichaMedia.openSettings();
          },
          child: const Text('Ouvrir les paramètres'),
        ),
      ],
    ),
  );
  return false;
}
