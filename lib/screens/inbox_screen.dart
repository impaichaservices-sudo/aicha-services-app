import 'package:flutter/material.dart';

import '../config.dart';
import '../models/inbox_item.dart';
import '../services/db.dart';
import '../services/notify_service.dart';
import '../utils.dart';
import '../widgets/common.dart';

/// Cloche 🔔 : toutes les notifications reçues dans l'application.
/// staff = true : notifications de l'équipe (nouvelles commandes, messages).
class InboxScreen extends StatefulWidget {
  final String uid;
  final bool staff;
  final String? shopId; // boutique de l'équipe (null = toutes)
  final DateTime? seenAt;
  const InboxScreen({
    super.key,
    required this.uid,
    this.staff = false,
    this.shopId,
    this.seenAt,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final Stream<List<InboxItem>> _items = widget.staff
      ? Db.staffInbox(shopId: widget.shopId, uid: widget.uid)
      : Db.clientInbox(widget.uid);

  @override
  void initState() {
    super.initState();
    Db.markSeen(widget.uid, widget.staff ? 'staffSeenAt' : 'inboxSeenAt');
  }

  IconData _icon(String type) {
    switch (type) {
      case 'order':
        return Icons.receipt_long_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'promo':
        return Icons.local_offer_rounded;
    }
    return Icons.notifications_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.staff ? 'Notifications de l\'équipe' : 'Notifications')),
      body: StreamBuilder<List<InboxItem>>(
        stream: _items,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error), textAlign: TextAlign.center));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!.take(100).toList();
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Aucune notification',
              message: 'Les nouvelles commandes, réponses et mises à jour apparaîtront ici.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = list[i];
              final fresh = n.isNewerThan(widget.seenAt);
              return Card(
                color: fresh ? AppConfig.paleGreen : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: fresh ? AppConfig.green : const Color(0xFFE6EAE4),
                    child: Icon(_icon(n.type),
                        color: fresh ? Colors.white : AppConfig.green),
                  ),
                  title: Text(n.title,
                      style: TextStyle(
                          fontWeight: fresh ? FontWeight.w800 : FontWeight.w600)),
                  subtitle: Text('${n.body}\n${timeLabel(n.createdAt)}',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  onTap: () => PushService.openData(n.data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Icône cloche avec compteur des notifications non vues.
class InboxBell extends StatefulWidget {
  final String uid;
  final bool staff;
  final String? shopId;
  final DateTime? seenAt;
  final Color color;
  const InboxBell({
    super.key,
    required this.uid,
    this.staff = false,
    this.shopId,
    this.seenAt,
    this.color = AppConfig.black,
  });

  @override
  State<InboxBell> createState() => _InboxBellState();
}

class _InboxBellState extends State<InboxBell> {
  Stream<List<InboxItem>>? _items;
  String _key = '';

  Stream<List<InboxItem>> _stream() {
    final key = '${widget.uid}|${widget.staff}|${widget.shopId}';
    if (_items == null || key != _key) {
      _key = key;
      _items = widget.staff
          ? Db.staffInbox(shopId: widget.shopId, uid: widget.uid)
          : Db.clientInbox(widget.uid);
    }
    return _items!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InboxItem>>(
      stream: _stream(),
      builder: (context, snap) {
        final unseen = (snap.data ?? const <InboxItem>[])
            .where((n) => n.isNewerThan(widget.seenAt))
            .length;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InboxScreen(
              uid: widget.uid,
              staff: widget.staff,
              shopId: widget.shopId,
              seenAt: widget.seenAt,
            ),
          )),
          icon: Badge(
            isLabelVisible: unseen > 0,
            label: Text(unseen > 99 ? '99+' : '$unseen'),
            backgroundColor: const Color(0xFFD32F2F),
            child: Icon(Icons.notifications_rounded, color: widget.color, size: 28),
          ),
        );
      },
    );
  }
}
