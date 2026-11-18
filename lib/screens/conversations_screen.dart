import 'package:flutter/material.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/chat.dart';
import '../services/db.dart';
import '../services/session.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Onglet Discussion du client : la discussion générale avec l'équipe,
/// puis une discussion par commande.
class ConversationsScreen extends StatefulWidget {
  final String uid;
  final AppUser? user;
  final bool standalone;
  const ConversationsScreen(
      {super.key, required this.uid, required this.user, this.standalone = false});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final Stream<List<Conversation>> _convs =
      Db.clientConversations(widget.uid);

  AppUser get _me =>
      widget.user ??
      AppUser(uid: widget.uid, name: 'Client', phone: '', email: '');

  String get _shopId {
    final id = sessionOf(context, listen: false).clientShopId;
    return id.isEmpty ? 'main' : id;
  }

  void _open(Conversation c) {
    final team = sessionOf(context, listen: false).teamName(c.shopId);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: c.id,
        createIfMissing: const {},
        title: c.isOrder ? 'Commande #${c.orderNumber}' : 'Équipe $team',
        subtitle: c.isOrder ? 'Équipe $team' : null,
        asShop: false,
        me: _me,
        shopId: c.shopId,
        orderId: c.orderId,
      ),
    ));
  }

  void _openGeneral() {
    final team = sessionOf(context, listen: false).teamName(_shopId);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: Db.generalConversationId(widget.uid),
        createIfMissing: Db.generalConversationData(_me, shopId: _shopId),
        title: 'Équipe $team',
        asShop: false,
        me: _me,
        shopId: _shopId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discussion'),
        automaticallyImplyLeading: widget.standalone,
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, snap) {
          final list = snap.data ?? const <Conversation>[];
          Conversation? general;
          for (final c in list) {
            if (!c.isOrder) general = c;
          }
          final orderConvs = list.where((c) => c.isOrder).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Discussion générale, toujours en haut.
              Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: AppConfig.paleGreen,
                    child: ClipOval(
                        child: Image.asset(AppConfig.logo, width: 46, height: 46)),
                  ),
                  title: Text('Équipe ${sessionOf(context).teamName(_shopId)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    general?.lastMessage.isNotEmpty == true
                        ? general!.lastMessage
                        : 'Posez vos questions, demandez un devis…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(timeLabel(general?.lastAt),
                          style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                      const SizedBox(height: 4),
                      CountBadge(general?.unreadForClient ?? 0),
                    ],
                  ),
                  onTap: _openGeneral,
                ),
              ),
              if (orderConvs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                  child: Text('Discussions de mes commandes',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                for (final c in orderConvs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppConfig.paleGreen,
                          child: Icon(Icons.receipt_long, color: AppConfig.green),
                        ),
                        title: Text('Commande #${c.orderNumber}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
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
                            CountBadge(c.unreadForClient),
                          ],
                        ),
                        onTap: () => _open(c),
                      ),
                    ),
                  ),
              ],
              if (snap.hasData && orderConvs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    'Chaque commande a aussi sa propre discussion : ouvrez une commande puis « Discuter de cette commande ».',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
