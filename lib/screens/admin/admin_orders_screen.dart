import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/order.dart';
import '../../services/db.dart';
import '../../utils.dart';
import '../../widgets/common.dart';
import '../../widgets/order_card.dart';
import '../chat_screen.dart';

const _adminFilters = {
  'a_traiter': 'À traiter',
  'nouvelles': 'Nouvelles',
  'en_cours': 'En cours',
  'pretes': 'Prêtes',
  'devis': 'Devis à faire',
  'terminees': 'Terminées',
  'toutes': 'Toutes',
};

bool _match(ShopOrder o, String f) {
  switch (f) {
    case 'a_traiter':
      return !o.isClosed;
    case 'nouvelles':
      return o.status == 'nouvelle';
    case 'en_cours':
      return o.status == 'confirmee' || o.status == 'en_cours';
    case 'pretes':
      return o.status == 'prete';
    case 'devis':
      return o.quoteNeeded && o.quotedTotal == null && !o.isClosed;
    case 'terminees':
      return o.isClosed;
  }
  return true;
}

/// Gestion → Commandes.
class AdminOrdersScreen extends StatefulWidget {
  final AppUser me;
  final String initialFilter;
  const AdminOrdersScreen(
      {super.key, required this.me, this.initialFilter = 'a_traiter'});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  late final Stream<List<ShopOrder>> _orders = Db.allOrders();
  late String _filter = widget.initialFilter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Rechercher (numéro, client, téléphone)',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: [
              for (final f in _adminFilters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.value),
                    selected: _filter == f.key,
                    onSelected: (_) => setState(() => _filter = f.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ShopOrder>>(
            stream: _orders,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erreur : ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!.where((o) {
                if (!_match(o, _filter)) return false;
                if (_query.isEmpty) return true;
                return o.displayNumber.toLowerCase().contains(_query) ||
                    o.buyerName.toLowerCase().contains(_query) ||
                    o.phone.contains(_query);
              }).toList();
              if (list.isEmpty) {
                return const EmptyState(
                    icon: Icons.inbox_outlined, title: 'Aucune commande ici');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => OrderCard(
                  order: list[i],
                  adminView: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        AdminOrderDetailScreen(orderId: list[i].id, me: widget.me),
                  )),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Détail d'une commande côté équipe : statut, devis, client, discussion.
class AdminOrderDetailScreen extends StatelessWidget {
  final String orderId;
  final AppUser me;
  const AdminOrderDetailScreen({super.key, required this.orderId, required this.me});

  Future<void> _setStatus(BuildContext context, ShopOrder o, String s) async {
    try {
      await Db.setOrderStatus(o, s,
          senderId: me.uid, senderName: AppConfig.shopName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _setQuote(BuildContext context, ShopOrder o) async {
    final amount = TextEditingController(
        text: (o.quotedTotal ?? (o.total > 0 ? o.total : '')).toString());
    final note = TextEditingController(text: o.adminNote);
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prix final'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Montant total (livraison comprise)',
                  suffixText: 'FCFA'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Message au client (facultatif)'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true) return;
    final value = int.parse(amount.text);
    await Db.setQuote(o.id, value, note.text.trim());
    await Db.sendMessage(
      conversationId: Db.orderConversationId(o.id),
      createIfMissing: Db.orderConversationData(o),
      senderId: me.uid,
      senderRole: 'shop',
      senderName: AppConfig.shopName,
      type: 'system',
      text: 'Commande ${o.displayNumber} : prix final ${fcfa(value)}'
          '${note.text.trim().isEmpty ? '' : ' — ${note.text.trim()}'}',
    );
  }

  void _chat(BuildContext context, ShopOrder o) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: Db.orderConversationId(o.id),
        createIfMissing: Db.orderConversationData(o),
        title: '${o.buyerName} • #${o.displayNumber}',
        subtitle: o.itemsSummary,
        asShop: true,
        me: me,
        clientPhone: o.phone,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ShopOrder?>(
      stream: Db.orderStream(orderId),
      builder: (context, snap) {
        final o = snap.data;
        return Scaffold(
          appBar: AppBar(
              title: Text(o == null ? 'Commande' : '#${o.displayNumber}')),
          body: o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(o.buyerName,
                                    style: const TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w800)),
                              ),
                              Pill(orderStatusLabels[o.status] ?? o.status,
                                  color: statusColor(o.status)),
                            ]),
                            Text('📞 ${o.phone}'),
                            Text(o.isDelivery
                                ? '📍 Livraison : ${o.address}, ${o.city}'
                                : '🏪 Retrait en boutique'),
                            if (o.deliveryInfo.isNotEmpty) Text('ℹ️ ${o.deliveryInfo}'),
                            Text('🗓 ${shortDate(o.createdAt)}',
                                style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 12),
                            StatusProgress(status: o.status),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              FilledButton.icon(
                                onPressed: () => _chat(context, o),
                                icon: const Icon(Icons.chat_bubble_rounded),
                                label: const Text('Discussion'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    launchUrl(Uri.parse('tel:${o.phone}')),
                                icon: const Icon(Icons.call),
                                label: const Text('Appeler'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => launchUrl(whatsappUri(o.phone),
                                    mode: LaunchMode.externalApplication),
                                icon: const Icon(Icons.chat),
                                label: const Text('WhatsApp'),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!o.isClosed)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Changer le statut',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 15)),
                              const Text(
                                  'Le client est prévenu dans la discussion de la commande.',
                                  style: TextStyle(color: Colors.black54, fontSize: 12.5)),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final s in [
                                  'confirmee',
                                  'en_cours',
                                  'prete',
                                  'livree',
                                  'annulee'
                                ])
                                  if (s != o.status)
                                    ActionChip(
                                      avatar: Icon(Icons.circle,
                                          size: 12, color: statusColor(s)),
                                      label: Text(orderStatusLabels[s]!),
                                      onPressed: () => _setStatus(context, o, s),
                                    ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Articles',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 8),
                            for (final i in o.items) ...[
                              Row(children: [
                                Expanded(
                                    child: Text('${i.qty} × ${i.name}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                                Text(i.onQuote ? 'sur devis' : fcfa(i.price * i.qty)),
                              ]),
                              if (i.note.isNotEmpty)
                                Text('📝 ${i.note}',
                                    style: const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 6),
                            ],
                            const Divider(),
                            Text('Sous-total : ${fcfa(o.subtotal)}'),
                            if (o.deliveryFee > 0)
                              Text('Livraison : ${fcfa(o.deliveryFee)}'),
                            Text(
                              o.amountDue == null
                                  ? 'Total : devis à préparer'
                                  : 'Total : ${fcfa(o.amountDue!)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            if (o.adminNote.isNotEmpty) Text('💬 ${o.adminNote}'),
                            if (!o.isClosed &&
                                (o.quoteNeeded || o.quotedTotal != null)) ...[
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () => _setQuote(context, o),
                                icon: const Icon(Icons.request_quote),
                                label: Text(o.quotedTotal == null
                                    ? 'Fixer le prix final'
                                    : 'Modifier le prix final'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
