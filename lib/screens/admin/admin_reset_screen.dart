import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../services/notify_service.dart';
import '../../utils.dart';
import '../../widgets/common.dart';

/// Nouveau mot de passe provisoire : 6 chiffres faciles à dicter.
String newTempPassword() {
  final r = Random.secure();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

/// Réinitialise le mot de passe d'un utilisateur puis propose de l'envoyer
/// par WhatsApp. Renvoie true si c'est fait.
Future<bool> resetUserPassword(BuildContext context, AppUser u) async {
  final pwd = newTempPassword();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.lock_reset, color: AppConfig.green, size: 40),
      title: const Text('Réinitialiser le mot de passe ?'),
      content: Text('${u.name.isEmpty ? 'Utilisateur' : u.name}\n${u.phone}\n\n'
          'Nouveau mot de passe provisoire : $pwd\n\n'
          'L\'ancien mot de passe ne fonctionnera plus.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Réinitialiser')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
      duration: Duration(seconds: 2), content: Text('Réinitialisation…')));
  final err = await NotifyService.resetPassword(uid: u.uid, password: pwd);
  if (!context.mounted) return false;
  if (err.isNotEmpty) {
    messenger.showSnackBar(SnackBar(duration: const Duration(seconds: 6), content: Text(err)));
    return false;
  }
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.check_circle, color: AppConfig.green, size: 40),
      title: const Text('Mot de passe réinitialisé'),
      content: Text('Nouveau mot de passe : $pwd\n\n'
          'Envoyez-le au client. Il pourra se connecter avec son numéro '
          'et ce mot de passe.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(c);
            launchUrl(
              whatsappUri(u.phone,
                  'Bonjour ${u.name}, votre mot de passe ${AppConfig.shortName} a été '
                  'réinitialisé. Nouveau mot de passe : $pwd\n'
                  'Connectez-vous avec votre numéro ${u.phone} et ce mot de passe.'),
              mode: LaunchMode.externalApplication,
            );
          },
          icon: const Icon(Icons.chat),
          label: const Text('Envoyer par WhatsApp'),
        ),
      ],
    ),
  );
  return true;
}

/// Gestion → Mots de passe oubliés (Super Admin).
class AdminResetScreen extends StatelessWidget {
  final AppUser me;
  const AdminResetScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mots de passe oubliés')),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: Db.pendingResets(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.lock_open_rounded,
              title: 'Aucune demande',
              message: 'Les demandes « Mot de passe oublié » des clients apparaîtront ici.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final d = list[i].data();
              final phone = (d['phone'] ?? '') as String;
              final name = (d['name'] ?? '') as String;
              final msg = (d['message'] ?? '') as String;
              final at = (d['createdAt'] as Timestamp?)?.toDate();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Sans nom' : name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(phone, style: const TextStyle(color: Colors.black54)),
                      if (msg.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(msg),
                      ],
                      Text(shortDate(at),
                          style: const TextStyle(fontSize: 12, color: Colors.black45)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final u = await Db.userByPhone(AuthService.displayPhone(phone));
                            if (!context.mounted) return;
                            if (u == null) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text('Aucun compte avec le numéro $phone.')));
                              return;
                            }
                            final done = await resetUserPassword(context, u);
                            if (done) await Db.closeReset(list[i].id, me.uid);
                          },
                          icon: const Icon(Icons.lock_reset),
                          label: const Text('Réinitialiser'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(whatsappUri(phone),
                              mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.chat),
                          label: const Text('WhatsApp'),
                        ),
                        TextButton(
                          onPressed: () => Db.closeReset(list[i].id, me.uid),
                          child: const Text('Ignorer'),
                        ),
                      ]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
