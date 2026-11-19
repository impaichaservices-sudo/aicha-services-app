import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/chat.dart';
import '../../services/call_service.dart';
import '../../services/db.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/common.dart';
import '../chat_screen.dart';

/// Gestion → Discussions.
/// - Agent : uniquement ses discussions + les nouvelles pas encore prises.
/// - Responsable / Super Admin : toutes, avec le nom de l'agent responsable.
class AdminConversationsScreen extends StatefulWidget {
  final AppUser me;
  final String? shopId;
  const AdminConversationsScreen({super.key, required this.me, this.shopId});

  @override
  State<AdminConversationsScreen> createState() =>
      _AdminConversationsScreenState();
}

class _AdminConversationsScreenState extends State<AdminConversationsScreen> {
  late final Stream<List<Conversation>> _convs = Db.allConversations(
      shopId: widget.shopId, agentUid: sessionOf(context, listen: false).agentUid);
  String _filter = 'all'; // all | unread | mine | free

  void _open(Conversation c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: c.id,
        createIfMissing: const {},
        title: c.clientName,
        subtitle: c.isOrder ? 'Commande #${c.orderNumber}' : c.clientPhone,
        asShop: true,
        me: widget.me,
        clientPhone: c.clientPhone,
        shopId: c.shopId,
        orderId: c.orderId,
      ),
    ));
  }

  void _call(Conversation c) {
    CallService.openCall(
      context,
      conversationId: c.id,
      createIfMissing: const {},
      asShop: true,
      shopId: c.shopId,
      otherName: c.clientName,
      me: widget.me,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionOf(context);
    final isAgent = session.agentUid != null;
    return Scaffold(
      appBar: AppBar(title: Text(isAgent ? 'Mes discussions' : 'Discussions')),
      body: StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error), textAlign: TextAlign.center));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final me = widget.me.uid;
          final list = snap.data!.where((c) {
            switch (_filter) {
              case 'unread':
                return c.unreadForShop > 0;
              case 'mine':
                return c.assignedTo == me;
              case 'free':
                return c.assignedTo.isEmpty;
              default:
                return true;
            }
          }).toList();
          Widget chip(String key, String label) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filter == key,
                  onSelected: (_) => setState(() => _filter = key),
                ),
              );
          return Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                chip('all', 'Toutes'),
                chip('unread', 'Non lues'),
                chip('mine', 'Les miennes'),
                chip('free', 'Nouvelles (libres)'),
              ]),
            ),
            if (isAgent)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Vous voyez vos discussions et les nouvelles. '
                  'Quand vous répondez à une nouvelle, elle devient la vôtre.',
                  style: TextStyle(color: Colors.black54, fontSize: 12.5),
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.forum_outlined, title: 'Aucune discussion')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final who = c.assignedTo.isEmpty
                            ? '🆕 Pas encore prise'
                            : c.assignedTo == me
                                ? '👤 Vous'
                                : '👤 ${c.assignedName}';
                        final shopLine = widget.shopId == null &&
                                session.shops.isNotEmpty
                            ? '${session.shopById(c.shopId).name} • '
                            : '';
                        return Card(
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.fromLTRB(12, 4, 4, 4),
                            leading: CircleAvatar(
                              backgroundColor: AppConfig.paleGreen,
                              child: Icon(
                                  c.isOrder ? Icons.receipt_long : Icons.person,
                                  color: AppConfig.green),
                            ),
                            title: Text(
                              c.isOrder
                                  ? '${c.clientName} • #${c.orderNumber}'
                                  : c.clientName,
                              style: TextStyle(
                                  fontWeight: c.unreadForShop > 0
                                      ? FontWeight.w900
                                      : FontWeight.w600),
                            ),
                            subtitle: Text('$shopLine$who\n${c.lastMessage}',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(timeLabel(c.lastAt),
                                      style: const TextStyle(
                                          fontSize: 11.5, color: Colors.black45)),
                                  const SizedBox(height: 4),
                                  CountBadge(c.unreadForShop),
                                ],
                              ),
                              IconButton(
                                tooltip: 'Rappeler par internet',
                                onPressed: () => _call(c),
                                icon: const Icon(Icons.call, color: AppConfig.green),
                              ),
                            ]),
                            onTap: () => _open(c),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}
