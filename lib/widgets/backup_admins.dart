import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/db.dart';

/// Super Admins de secours : si le compte principal est perdu, un autre
/// compte garde l'accès complet à l'administration.
class BackupAdmins extends StatefulWidget {
  const BackupAdmins({super.key});

  @override
  State<BackupAdmins> createState() => _BackupAdminsState();
}

class _BackupAdminsState extends State<BackupAdmins> {
  final _phone = TextEditingController();
  bool _busy = false;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _admins =
      Db.admins.snapshots();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AuthService.isValidPhone(_phone.text)) {
      messenger.showSnackBar(const SnackBar(content: Text('Numéro invalide (8 chiffres).')));
      return;
    }
    setState(() => _busy = true);
    try {
      final u = await Db.userByPhone(AuthService.displayPhone(_phone.text));
      if (u == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Aucun compte avec ce numéro : la personne doit d\'abord s\'inscrire.')));
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nommer un Super Admin de secours ?'),
          content: Text('${u.name}\n${u.phone}\n\nCette personne aura TOUS les droits '
              'sur l\'application. Choisissez quelqu\'un de confiance.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmer')),
          ],
        ),
      );
      if (ok != true) return;
      await Db.admins.doc(u.uid).set({
        'name': u.name,
        'phone': u.phone,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _phone.clear();
      messenger.showSnackBar(SnackBar(content: Text('${u.name} est Super Admin de secours ✅')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Action impossible pour le moment.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Si votre compte est perdu (téléphone volé, mot de passe oublié), un '
        'Super Admin de secours pourra toujours tout gérer.',
        style: TextStyle(color: Colors.black54, fontSize: 13),
      ),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _admins,
        builder: (_, snap) => Column(children: [
          for (final d in snap.data?.docs ?? const [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.admin_panel_settings, color: AppConfig.green),
              title: Text((d.data()['name'] ?? 'Super Admin') as String),
              subtitle: Text((d.data()['phone'] ?? d.id) as String),
              trailing: IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => d.reference.delete(),
              ),
            ),
        ]),
      ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro du compte'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _busy ? null : _add, child: const Text('Ajouter')),
      ]),
    ]);
  }
}
