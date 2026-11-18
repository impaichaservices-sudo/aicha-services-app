import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../services/call_service.dart';
import '../../services/db.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/common.dart';
import '../chat_screen.dart';

/// Gestion → Clients : liste, appel, WhatsApp, discussion.
class AdminClientsScreen extends StatefulWidget {
  final AppUser me;
  final String? shopId;
  const AdminClientsScreen({super.key, required this.me, this.shopId});

  @override
  State<AdminClientsScreen> createState() => _AdminClientsScreenState();
}

class _AdminClientsScreenState extends State<AdminClientsScreen> {
  late final Stream<List<AppUser>> _users = widget.shopId == null
      ? Db.allUsers()
      : Db.shopUsers(widget.shopId!);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'Rechercher un nom ou un numéro',
                prefixIcon: Icon(Icons.search),
                isDense: true),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<AppUser>>(
            stream: _users,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!
                  .where((u) =>
                      _q.isEmpty ||
                      u.name.toLowerCase().contains(_q) ||
                      u.phone.replaceAll(' ', '').contains(_q.replaceAll(' ', '')))
                  .toList();
              if (list.isEmpty) {
                return const EmptyState(
                    icon: Icons.people_outline, title: 'Aucun client');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final u = list[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppConfig.green,
                        child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(u.name.isEmpty ? 'Sans nom' : u.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${u.phone}${u.createdAt == null ? '' : ' • inscrit le ${shortDate(u.createdAt).split(' ').first}'}'
                          '${widget.shopId == null && sessionOf(context).shops.isNotEmpty ? '\n${sessionOf(context).shopById(u.shopId).name}' : ''}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) {
                          if (a == 'chat') {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                conversationId: Db.generalConversationId(u.uid),
                                createIfMissing: Db.generalConversationData(u,
                                    shopId: widget.shopId ?? u.shopId),
                                shopId: widget.shopId ?? u.shopId,
                                title: u.name,
                                subtitle: u.phone,
                                asShop: true,
                                me: widget.me,
                                clientPhone: u.phone,
                              ),
                            ));
                          } else if (a == 'netcall') {
                            final sid = widget.shopId ?? u.shopId;
                            CallService.openCall(
                              context,
                              conversationId: Db.generalConversationId(u.uid),
                              createIfMissing:
                                  Db.generalConversationData(u, shopId: sid),
                              asShop: true,
                              shopId: sid,
                              otherName: u.name,
                              me: widget.me,
                            );
                          } else if (a == 'call') {
                            launchUrl(Uri.parse('tel:${u.phone}'));
                          } else if (a == 'wa') {
                            launchUrl(whatsappUri(u.phone),
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'chat', child: Text('Discuter')),
                          PopupMenuItem(
                              value: 'netcall',
                              child: Text('Appeler par internet')),
                          PopupMenuItem(
                              value: 'call', child: Text('Appeler (numéro)')),
                          PopupMenuItem(value: 'wa', child: Text('WhatsApp')),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
