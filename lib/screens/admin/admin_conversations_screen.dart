import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/chat.dart';
import '../../services/db.dart';
import '../../utils.dart';
import '../../widgets/common.dart';
import '../chat_screen.dart';

/// Gestion → Discussions : toutes les conversations, les non lues en premier.
class AdminConversationsScreen extends StatefulWidget {
  final AppUser me;
  const AdminConversationsScreen({super.key, required this.me});

  @override
  State<AdminConversationsScreen> createState() =>
      _AdminConversationsScreenState();
}

class _AdminConversationsScreenState extends State<AdminConversationsScreen> {
  late final Stream<List<Conversation>> _convs = Db.allConversations();
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discussions')),
      body: StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!
              .where((c) => !_unreadOnly || c.unreadForShop > 0)
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                ChoiceChip(
                  label: const Text('Toutes'),
                  selected: !_unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Non lues'),
                  selected: _unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = true),
                ),
              ]),
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
                        return Card(
                          child: ListTile(
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
                            subtitle: Text(c.lastMessage,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Column(
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
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversationId: c.id,
                                  createIfMissing: const {},
                                  title: c.clientName,
                                  subtitle: c.isOrder
                                      ? 'Commande #${c.orderNumber}'
                                      : c.clientPhone,
                                  asShop: true,
                                  me: widget.me,
                                  clientPhone: c.clientPhone,
                                ),
                              ),
                            ),
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
