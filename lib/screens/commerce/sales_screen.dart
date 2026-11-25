import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/pdf_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';

/// Ventes d'une journée de caisse.
class SalesScreen extends StatefulWidget {
  final CashSession session;
  final bool mine;
  const SalesScreen({super.key, required this.session, required this.mine});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late final Stream<List<Sale>> _sales =
      Commerce.salesOfSession(widget.session, mine: widget.mine);

  @override
  Widget build(BuildContext context) {
    final c = widget.session;
    return Scaffold(
      appBar: AppBar(title: Text('Ventes · ${c.agentName} · ${dayLabel(c.day)}')),
      body: StreamBuilder<List<Sale>>(
        stream: _sales,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const Center(
                child: Text('Aucune vente.', style: TextStyle(color: Colors.black54)));
          }
          final sum = DaySummary.of(list);
          return ListView(children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  SumRow('${sum.count} vente(s)', fcfa(sum.total), bold: true),
                  if (sum.cancelled > 0) SumRow('Annulées', '${sum.cancelled}'),
                ]),
              ),
            ),
            for (final v in list)
              ListTile(
                tileColor: Colors.white,
                title: Text(v.number,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        decoration: v.cancelled ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  timeLabel(v.at),
                  payMethods[v.payMethod] ?? v.payMethod,
                  if (v.customerName.isNotEmpty) v.customerName,
                  if (v.cancelled) 'ANNULÉE',
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(fcfa(v.total),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: v.cancelled ? Colors.black38 : null)),
                  const SizedBox(width: 6),
                  PendingIcon(v.pending),
                ]),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SaleDetailScreen(sale: v, session: c))),
              ),
            const SizedBox(height: 30),
          ]);
        },
      ),
    );
  }
}

class SaleDetailScreen extends StatelessWidget {
  final Sale sale;
  final CashSession session;
  const SaleDetailScreen({super.key, required this.sale, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    final v = sale;
    final canCancel = !v.cancelled &&
        !session.closed &&
        (s.isSuper ||
            (s.staff?.isManager ?? false) ||
            (v.agentId == s.uid && s.can('sales')));
    return Scaffold(
      appBar: AppBar(title: Text(v.number)),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (v.cancelled)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  color: const Color(0xFFFFEBEE),
                  child: Text('VENTE ANNULÉE${v.cancelReason.isEmpty ? '' : ' : ${v.cancelReason}'}',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
                ),
              SumRow('Date', timeLabel(v.at)),
              SumRow('Vendeur', v.agentName),
              if (v.customerName.isNotEmpty) SumRow('Client', v.customerName),
              if (v.customerPhone.isNotEmpty) SumRow('Téléphone', v.customerPhone),
              const Divider(),
              for (final l in v.lines) SumRow('${l.qty} × ${l.name}', fcfa(l.total)),
              const Divider(),
              SumRow('Sous-total', fcfa(v.subtotal)),
              if (v.discount > 0) SumRow('Remise', '-${fcfa(v.discount)}'),
              SumRow('Total', fcfa(v.total), bold: true),
              SumRow('Paiement', payMethods[v.payMethod] ?? v.payMethod),
              if (v.due > 0) ...[
                SumRow('Payé', fcfa(v.paid)),
                SumRow('Reste à payer', fcfa(v.due), color: Colors.red, bold: true),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            onPressed: () async {
              final bytes = await PdfService.receipt(v, s.shopById(v.shopId));
              await PdfService.open(bytes, 'Recu_${v.number}');
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Reçu PDF (voir, partager, imprimer)'),
          ),
        ),
        if (canCancel)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                final reason = await askText(context, 'Annuler ${v.number} ?',
                    'Motif de l\'annulation (obligatoire)');
                if (reason == null || reason.isEmpty) return;
                await Commerce.cancelSale(s, v, reason);
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Annuler la vente (le stock est remis)'),
            ),
          ),
        if (session.closed)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Journée clôturée : cette vente ne peut plus être modifiée.',
                style: TextStyle(color: Colors.black54)),
          ),
      ]),
    );
  }
}

/// Clôture d'une journée de caisse (ou consultation si déjà clôturée).
class ClosureScreen extends StatefulWidget {
  final CashSession session;
  final bool mine;
  const ClosureScreen({super.key, required this.session, required this.mine});

  @override
  State<ClosureScreen> createState() => _ClosureScreenState();
}

class _ClosureScreenState extends State<ClosureScreen> {
  late final Stream<CashSession?> _c = Commerce.sessionStream(widget.session.id);
  late final Stream<List<Sale>> _sales =
      Commerce.salesOfSession(widget.session, mine: widget.mine);
  late final Stream<List<CashOut>> _outs =
      Commerce.cashOutsOf(widget.session, mine: widget.mine);
  late final Stream<List<Payment>> _pays =
      Commerce.paymentsOfSession(widget.session, mine: widget.mine);
  final _counted = TextEditingController();

  Future<void> _addOut(CashSession c) async {
    final s = sessionOf(context, listen: false);
    final amount = await askAmount(context, title: 'Sortie de caisse');
    if (amount == null || amount <= 0 || !mounted) return;
    final reason = await askText(context, 'Motif de la sortie', 'Ex : transport, achat urgent');
    if (reason == null || reason.isEmpty) return;
    await Commerce.addCashOut(s, c, amount, reason);
  }

  Future<void> _close(CashSession c, DaySummary sum, int outs) async {
    final s = sessionOf(context, listen: false);
    final counted = int.tryParse(_counted.text.trim());
    if (counted == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saisissez le montant réellement compté dans la caisse.')));
      return;
    }
    final expected = c.openingFloat + (sum.byMethod['especes'] ?? 0) - outs;
    final gap = counted - expected;
    final ok = await confirm(
      context,
      'Clôturer la journée du ${dayLabel(c.day)} ?',
      '${c.agentName}\n${sum.count} vente(s) · ${fcfa(sum.total)}\n'
          'Espèces attendues : ${fcfa(expected)}\nCompté : ${fcfa(counted)}\n'
          'Écart : ${gap > 0 ? '+' : ''}${fcfa(gap)}\n\n'
          'Après clôture, les ventes de la journée ne peuvent plus être modifiées.',
      ok: 'CLÔTURER',
    );
    if (!ok) return;
    await Commerce.closeSession(s, c, sum, outs, counted);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Journée clôturée (envoyée au retour d\'internet si besoin).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    return StreamBuilder<CashSession?>(
      stream: _c,
      initialData: widget.session,
      builder: (context, cs) {
        final c = cs.data ?? widget.session;
        final canClose = !c.closed &&
            (s.isSuper ||
                ((s.staff?.isManager ?? false) && s.staff!.shopId == c.shopId) ||
                (c.agentId == s.uid && s.can('sales')));
        return Scaffold(
          appBar: AppBar(title: Text('Clôture · ${dayLabel(c.day)}')),
          body: StreamBuilder<List<Sale>>(
            stream: _sales,
            builder: (context, ss) => StreamBuilder<List<CashOut>>(
              stream: _outs,
              builder: (context, os) => StreamBuilder<List<Payment>>(
              stream: _pays,
              builder: (context, pys) {
                final sales = ss.data ?? const <Sale>[];
                final outs = os.data ?? const <CashOut>[];
                final sum = DaySummary.of(sales).addPayments(pys.data ?? const <Payment>[]);
                final outTotal = outs.fold<int>(0, (a, o) => a + o.amount);
                final especes = sum.byMethod['especes'] ?? 0;
                final expected = c.closed ? c.expectedCash : c.openingFloat + especes - outTotal;
                return ListView(padding: const EdgeInsets.all(12), children: [
                  Card(
                    color: c.closed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
                    child: ListTile(
                      leading: Icon(c.closed ? Icons.lock_rounded : Icons.lock_open_rounded,
                          color: c.closed ? AppConfig.green : Colors.orange),
                      title: Text(c.closed ? 'Journée clôturée' : 'Journée ouverte',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(c.closed
                          ? 'Par ${c.closedByName}${c.closedAt == null ? '' : ' · ${timeLabel(c.closedAt)}'}'
                          : 'Agent : ${c.agentName}'),
                      trailing: PendingIcon(c.pending),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        SumRow('Agent', c.agentName),
                        SumRow('Nombre de ventes', '${sum.count}'),
                        for (final e in payMethods.entries)
                          if ((sum.byMethod[e.key] ?? 0) > 0)
                            SumRow(e.value, fcfa(sum.byMethod[e.key] ?? 0)),
                        if (sum.creditPaid > 0)
                          SumRow('dont crédits / factures encaissés', fcfa(sum.creditPaid)),
                        if (sum.discount > 0) SumRow('Remises accordées', fcfa(sum.discount)),
                        if (sum.cancelled > 0) SumRow('Ventes annulées', '${sum.cancelled}'),
                        const Divider(),
                        SumRow('Total des ventes', fcfa(sum.total), bold: true),
                        SumRow('Total encaissé', fcfa(sum.collected), bold: true),
                        if (sum.credit > 0)
                          SumRow('Reste en crédit', fcfa(sum.credit), color: Colors.red),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Caisse (espèces)',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 6),
                        SumRow('Fond de caisse initial', fcfa(c.openingFloat)),
                        SumRow('+ Espèces reçues', fcfa(especes)),
                        SumRow('− Sorties de caisse', fcfa(outTotal)),
                        SumRow('= Montant attendu', fcfa(expected), bold: true),
                        if (c.closed) ...[
                          SumRow('Montant compté', fcfa(c.countedCash)),
                          SumRow('Écart', '${c.gap > 0 ? '+' : ''}${fcfa(c.gap)}',
                              bold: true,
                              color: c.gap == 0 ? AppConfig.green : Colors.red),
                        ],
                        for (final o in outs)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• ${fcfa(o.amount)} — ${o.reason} (${o.userName})',
                                style: const TextStyle(fontSize: 13, color: Colors.black54)),
                          ),
                        if (canClose) ...[
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: () => _addOut(c),
                            icon: const Icon(Icons.outbox_rounded),
                            label: const Text('Ajouter une sortie de caisse'),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  if (canClose) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _counted,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Espèces réellement comptées', suffixText: 'FCFA'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: const Color(0xFFB71C1C)),
                      onPressed: () => _close(c, sum, outTotal),
                      icon: const Icon(Icons.lock_rounded),
                      label: const Text('CLÔTURER LA JOURNÉE',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SalesScreen(session: c, mine: widget.mine))),
                    child: const Text('Voir le détail des ventes'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bytes = await PdfService.closure(
                          c, sum, outTotal, outs, s.shopById(c.shopId));
                      await PdfService.open(bytes, 'Cloture_${c.agentName}_${c.day}');
                    },
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Rapport de clôture PDF'),
                  ),
                  const SizedBox(height: 30),
                ]);
              },
            ),
            ),
          ),
        );
      },
    );
  }
}

/// Historique des clôtures (responsable / Super Admin : toute la boutique).
class ClosuresScreen extends StatefulWidget {
  final String shopId;
  final bool all; // toute l'équipe (sinon : mes journées)
  const ClosuresScreen({super.key, required this.shopId, required this.all});

  @override
  State<ClosuresScreen> createState() => _ClosuresScreenState();
}

class _ClosuresScreenState extends State<ClosuresScreen> {
  DateTime _day = DateTime.now();
  Stream<List<CashSession>>? _stream;
  String _key = '';

  Stream<List<CashSession>> _streamFor(Session s) {
    final k = widget.all ? dayKey(_day) : 'mine';
    if (k != _key || _stream == null) {
      _key = k;
      _stream = widget.all
          ? Commerce.sessionsOfDay(widget.shopId, dayKey(_day))
          : Commerce.mySessions(widget.shopId, s.uid);
    }
    return _stream!;
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.all ? 'Historique des clôtures' : 'Mes journées'),
        actions: [
          if (widget.all)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime(2025),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _day = d);
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(dayLabel(dayKey(_day))),
            ),
        ],
      ),
      body: StreamBuilder<List<CashSession>>(
        stream: _streamFor(s),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const Center(
                child: Text('Aucune journée de caisse.', style: TextStyle(color: Colors.black54)));
          }
          final open = list.where((c) => !c.closed).length;
          return ListView(children: [
            if (widget.all && open > 0)
              Card(
                margin: const EdgeInsets.all(12),
                color: const Color(0xFFFFF3E0),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  title: Text('$open journée(s) non clôturée(s)',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            for (final c in list)
              ListTile(
                tileColor: Colors.white,
                leading: Icon(c.closed ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: c.closed ? AppConfig.green : Colors.orange),
                title: Text(widget.all ? c.agentName : dayLabel(c.day),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(c.closed
                    ? 'Clôturée · ${c.salesCount} vente(s)${c.gap != 0 ? ' · écart ${fcfa(c.gap)}' : ''}'
                    : 'Non clôturée'),
                trailing: Text(c.closed ? fcfa(c.totals['total'] ?? 0) : '',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ClosureScreen(session: c, mine: !widget.all))),
              ),
          ]);
        },
      ),
    );
  }
}
