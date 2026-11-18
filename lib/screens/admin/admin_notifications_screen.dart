import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/db.dart';
import '../../services/notify_service.dart';
import '../../services/session.dart';
import '../../utils.dart';

/// Envoyer une notification (nouveauté, promotion, annonce) aux clients.
class AdminNotificationsScreen extends StatefulWidget {
  final String? shopId; // null = Super Admin
  const AdminNotificationsScreen({super.key, this.shopId});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late Set<String> _targets =
      widget.shopId != null ? {widget.shopId!} : {'all'};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) return;
    final session = sessionOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    if (!session.settings.pushEnabled) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Notifications non configurées : renseignez l\'adresse '
              'du serveur dans Paramètres.')));
      return;
    }
    setState(() => _busy = true);
    final shops = _targets.toList();
    final title = _title.text.trim().isEmpty ? AppConfig.shopName : _title.text.trim();
    final ok = await NotifyService.toShops(
      shops: shops,
      title: title,
      body: _body.text.trim(),
      data: {'type': 'announce'},
    );
    if (ok) {
      await Db.logNotification({
        'title': title,
        'body': _body.text.trim(),
        'shops': shops,
        'kind': 'annonce',
      });
      _title.clear();
      _body.clear();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Notification envoyée' : 'Envoi impossible, réessayez.')));
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionOf(context);
    Query<Map<String, dynamic>> q =
        Db.notifications.orderBy('createdAt', descending: true).limit(30);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!session.settings.pushEnabled)
            Card(
              color: const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(session.isSuper
                    ? 'Les notifications ne sont pas encore configurées : renseignez '
                        'l\'adresse du serveur dans Gestion → Paramètres.'
                    : 'Les notifications ne sont pas encore activées par l\'administration.'),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Titre', hintText: 'AÏCHA SERVICES'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Nouveau service disponible ! Découvrez…',
            ),
          ),
          if (widget.shopId == null && session.shops.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Destinataires',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(
                label: const Text('Toutes les boutiques'),
                selected: _targets.contains('all'),
                onSelected: (_) => setState(() => _targets = {'all'}),
              ),
              for (final sh in session.shops)
                FilterChip(
                  label: Text(sh.name),
                  selected: _targets.contains(sh.id),
                  onSelected: (v) => setState(() {
                    _targets.remove('all');
                    v ? _targets.add(sh.id) : _targets.remove(sh.id);
                    if (_targets.isEmpty) _targets = {'all'};
                  }),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Envoyer la notification'),
          ),
          const SizedBox(height: 24),
          if (session.isSuper) ...[
            const Text('Derniers envois',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Text('Aucun envoi pour le moment.',
                      style: TextStyle(color: Colors.black54));
                }
                return Column(children: [
                  for (final d in docs)
                    Card(
                      child: ListTile(
                        title: Text((d.data()['title'] ?? '').toString()),
                        subtitle: Text(
                            '${(d.data()['body'] ?? '').toString()}\n${shortDate((d.data()['createdAt'] as Timestamp?)?.toDate())}'),
                        isThreeLine: true,
                      ),
                    ),
                ]);
              },
            ),
          ],
        ],
      ),
    );
  }
}
