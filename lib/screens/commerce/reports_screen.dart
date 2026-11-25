import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/docs_service.dart';
import '../../services/pdf_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import 'commerce_widgets.dart';
import 'customers_screen.dart' show paidByTarget;

/// Barres horizontales simples (pas de bibliothèque de graphiques).
class Bars extends StatelessWidget {
  final List<(String, int)> data;
  final Color color;
  final String Function(int)? format;
  const Bars(this.data, {super.key, this.color = AppConfig.green, this.format});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Aucune donnée.', style: TextStyle(color: Colors.black54)),
      );
    }
    final max = data.map((e) => e.$2).fold<int>(1, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final e in data)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 92,
              child: Text(e.$1, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 16,
                    width: (box.maxWidth * (e.$2 <= 0 ? 0 : e.$2 / max)).clamp(2.0, box.maxWidth).toDouble(),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(format == null ? fcfa(e.$2) : format!(e.$2),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}

class _Data {
  final List<Sale> sales;
  final List<StockMove> moves;
  final List<CashSession> sessions;
  final List<Payment> payments;
  const _Data(this.sales, this.moves, this.sessions, this.payments);
}

/// Tableau de bord et rapports.
class ReportsScreen extends StatefulWidget {
  final String shopId;
  const ReportsScreen({super.key, required this.shopId});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'jour';
  DateTimeRange? _custom;
  Future<_Data>? _future;
  late final Stream<List<Product>> _products = Commerce.productsOf(widget.shopId);
  late final Stream<List<Sale>> _credit = Commerce.creditSales(widget.shopId);
  late final Stream<List<Payment>> _salePays = Commerce.paymentsWhere(widget.shopId, 'targetType', 'sale');
  late final Stream<List<Payment>> _invPays = Commerce.paymentsWhere(widget.shopId, 'targetType', 'invoice');
  late final Stream<List<BizDoc>> _quotes = Docs.listOf(widget.shopId, 'quote');
  late final Stream<List<BizDoc>> _invoices = Docs.listOf(widget.shopId, 'invoice');

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    switch (_period) {
      case 'semaine':
        return (now.subtract(const Duration(days: 6)), now);
      case 'mois':
        return (DateTime(now.year, now.month, 1), now);
      case 'perso':
        final r = _custom;
        return r == null ? (now, now) : (r.start, r.end);
      default:
        return (now, now);
    }
  }

  List<String> get _days => Commerce.daysBetween(_range.$1, _range.$2);

  String get _periodLabel {
    final d = _days;
    return d.length == 1 ? dayLabel(d.first) : '${dayLabel(d.first)} au ${dayLabel(d.last)}';
  }

  void _load() {
    final days = _days;
    _future = () async {
      final r = await Future.wait([
        Commerce.salesOfDays(widget.shopId, days),
        Commerce.movesOfDays(widget.shopId, days),
        Commerce.sessionsOfDays(widget.shopId, days),
        Commerce.paymentsOfDays(widget.shopId, days),
      ]);
      return _Data(r[0] as List<Sale>, r[1] as List<StockMove>, r[2] as List<CashSession>,
          r[3] as List<Payment>);
    }();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setPeriod(String p) async {
    if (p == 'perso') {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2025),
        lastDate: now,
        initialDateRange: _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      );
      if (r == null) return;
      _custom = r;
    }
    setState(() {
      _period = p;
      _load();
    });
  }

  Widget _card(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _kpi(String label, String value, Color color, {IconData? icon}) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (icon != null) Icon(icon, color: color, size: 18),
                if (icon != null) const SizedBox(width: 4),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              ),
            ]),
          ),
        ),
      );

  Widget _dashboard(_Data d) {
    final valid = d.sales.where((v) => !v.cancelled).toList();
    final sum = DaySummary.of(d.sales).addPayments(d.payments);
    final items = valid.fold<int>(0, (a, v) => a + v.lines.fold<int>(0, (b, l) => b + l.qty));
    CashSession? last;
    for (final c in d.sessions.where((c) => c.closed)) {
      if (last == null || c.day.compareTo(last.day) > 0) last = c;
    }
    return ListView(padding: const EdgeInsets.all(10), children: [
      Row(children: [
        _kpi('Ventes', fcfa(sum.total), AppConfig.green, icon: Icons.point_of_sale),
        _kpi('Nombre de ventes', '${sum.count}', const Color(0xFF1565C0), icon: Icons.receipt),
      ]),
      Row(children: [
        _kpi('Encaissé', fcfa(sum.collected), const Color(0xFF00838F), icon: Icons.payments),
        _kpi('Articles vendus', '$items', const Color(0xFF6A1B9A), icon: Icons.inventory_2),
      ]),
      StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, ps) {
          final low = (ps.data ?? const <Product>[]).where((p) => p.lowStock).length;
          return StreamBuilder<List<Sale>>(
            stream: _credit,
            builder: (context, cs) => StreamBuilder<List<Payment>>(
              stream: _salePays,
              builder: (context, sp) {
                final paid = paidByTarget(sp.data ?? const []);
                final credits = (cs.data ?? const <Sale>[])
                    .fold<int>(0, (a, v) => a + (v.due - (paid[v.id] ?? 0)).clamp(0, v.due).toInt());
                return Row(children: [
                  _kpi('Stock faible', '$low produit(s)', low > 0 ? Colors.red : AppConfig.green,
                      icon: Icons.warning_amber),
                  _kpi('Crédits clients', fcfa(credits), credits > 0 ? Colors.red : AppConfig.green,
                      icon: Icons.account_balance_wallet),
                ]);
              },
            ),
          );
        },
      ),
      StreamBuilder<List<BizDoc>>(
        stream: _quotes,
        builder: (context, qs) => StreamBuilder<List<BizDoc>>(
          stream: _invoices,
          builder: (context, is_) => StreamBuilder<List<Payment>>(
            stream: _invPays,
            builder: (context, ip) {
              final pending = (qs.data ?? const <BizDoc>[])
                  .where((q) => q.status == 'brouillon' || q.status == 'envoye')
                  .length;
              final paid = paidByTarget(ip.data ?? const []);
              final unpaid = (is_.data ?? const <BizDoc>[])
                  .where((d) => d.status == 'validee')
                  .fold<int>(0, (a, d) => a + (d.total - (paid[d.id] ?? 0)).clamp(0, d.total).toInt());
              return Row(children: [
                _kpi('Devis en attente', '$pending', const Color(0xFFEF6C00), icon: Icons.request_quote),
                _kpi('Factures impayées', fcfa(unpaid), unpaid > 0 ? Colors.red : AppConfig.green,
                    icon: Icons.receipt_long),
              ]);
            },
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.lock_clock, color: AppConfig.green),
          title: const Text('Dernière clôture de la période'),
          subtitle: Text(last == null
              ? 'Aucune'
              : '${dayLabel(last.day)} · ${last.agentName} · ${fcfa(last.totals['total'] ?? 0)}'),
          trailing: Text('${d.sessions.where((c) => !c.closed).length} ouverte(s)'),
        ),
      ),
      _card('Moyens de paiement', [
        Bars([
          for (final e in payMethods.entries)
            if ((sum.byMethod[e.key] ?? 0) > 0) (e.value, sum.byMethod[e.key] ?? 0),
        ], color: const Color(0xFF1565C0)),
      ]),
      _card('Ventes par jour', [Bars(_byDay(valid))]),
    ]);
  }

  List<(String, int)> _byDay(List<Sale> valid) {
    final m = <String, int>{};
    for (final d in _days) {
      m[d] = 0;
    }
    for (final v in valid) {
      m[v.day] = (m[v.day] ?? 0) + v.total;
    }
    final keys = m.keys.toList()..sort();
    final shown = keys.length > 31 ? keys.sublist(keys.length - 31) : keys;
    return [for (final k in shown) (dayLabel(k).substring(0, 5), m[k] ?? 0)];
  }

  List<(String, int)> _top(Map<String, int> m, [int n = 10]) {
    final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in l.take(n)) (e.key, e.value)];
  }

  Widget _salesTab(_Data d) {
    final valid = d.sales.where((v) => !v.cancelled).toList();
    final sum = DaySummary.of(d.sales);
    final byProduct = <String, int>{};
    final qtyProduct = <String, int>{};
    for (final v in valid) {
      for (final l in v.lines) {
        byProduct[l.name] = (byProduct[l.name] ?? 0) + l.total;
        qtyProduct[l.name] = (qtyProduct[l.name] ?? 0) + l.qty;
      }
    }
    return ListView(padding: const EdgeInsets.all(10), children: [
      _card('Ventes · $_periodLabel', [
        SumRow('Nombre de ventes', '${sum.count}'),
        SumRow('Chiffre d\'affaires', fcfa(sum.total), bold: true),
        SumRow('Remises', fcfa(sum.discount)),
        SumRow('Vendu à crédit', fcfa(sum.credit)),
        SumRow('Ventes annulées', '${sum.cancelled}'),
        SumRow('Panier moyen', fcfa(sum.count == 0 ? 0 : sum.total ~/ sum.count)),
      ]),
      _card('Produits les plus vendus (montant)', [Bars(_top(byProduct))]),
      _card('Produits les plus vendus (quantité)', [
        Bars(_top(qtyProduct), color: const Color(0xFF6A1B9A), format: (v) => '$v'),
      ]),
      _card('Ventes par jour', [Bars(_byDay(valid))]),
    ]);
  }

  Widget _stockTab(_Data d) {
    final byType = <String, int>{};
    for (final m in d.moves) {
      byType[m.type] = (byType[m.type] ?? 0) + m.qty;
    }
    return StreamBuilder<List<Product>>(
      stream: _products,
      builder: (context, ps) {
        final products = ps.data ?? const <Product>[];
        final tracked = products.where((p) => p.trackStock && p.active).toList();
        final value = tracked.fold<int>(0, (a, p) => a + p.stock * p.buyPrice);
        final low = tracked.where((p) => p.lowStock).toList();
        return ListView(padding: const EdgeInsets.all(10), children: [
          _card('Mouvements · $_periodLabel', [
            for (final e in moveTypes.entries)
              if (byType.containsKey(e.key)) SumRow(e.value, '${byType[e.key]! > 0 ? '+' : ''}${byType[e.key]}'),
            if (byType.isEmpty) const Text('Aucun mouvement.', style: TextStyle(color: Colors.black54)),
          ]),
          _card('Stock actuel', [
            SumRow('Produits suivis', '${tracked.length}'),
            SumRow('Valeur du stock (prix d\'achat)', fcfa(value), bold: true),
            SumRow('En stock faible', '${low.length}', color: low.isEmpty ? null : Colors.red),
          ]),
          if (low.isNotEmpty)
            _card('STOCK FAIBLE', [
              for (final p in low)
                SumRow(p.name, '${p.stock} / min ${p.minStock}', color: Colors.red),
            ]),
        ]);
      },
    );
  }

  Widget _cashTab(_Data d) {
    final closed = d.sessions.where((c) => c.closed).toList()..sort((a, b) => b.day.compareTo(a.day));
    final float = closed.fold<int>(0, (a, c) => a + c.openingFloat);
    final cash = closed.fold<int>(0, (a, c) => a + (c.totals['especes'] ?? 0));
    final outs = closed.fold<int>(0, (a, c) => a + c.cashOut);
    final expected = closed.fold<int>(0, (a, c) => a + c.expectedCash);
    final counted = closed.fold<int>(0, (a, c) => a + c.countedCash);
    return ListView(padding: const EdgeInsets.all(10), children: [
      _card('Caisse · $_periodLabel (${closed.length} clôture(s))', [
        SumRow('Fonds de caisse', fcfa(float)),
        SumRow('Ventes et encaissements en espèces', fcfa(cash)),
        SumRow('Sorties de caisse', fcfa(outs)),
        SumRow('Montant attendu', fcfa(expected), bold: true),
        SumRow('Montant compté', fcfa(counted)),
        SumRow('Écart total', fcfa(counted - expected),
            bold: true, color: counted - expected == 0 ? AppConfig.green : Colors.red),
      ]),
      if (d.sessions.any((c) => !c.closed))
        _card('Journées non clôturées', [
          for (final c in d.sessions.where((c) => !c.closed))
            SumRow('${dayLabel(c.day)} · ${c.agentName}', 'ouverte', color: Colors.orange),
        ]),
      _card('Détail des clôtures', [
        for (final c in closed)
          SumRow('${dayLabel(c.day)} · ${c.agentName}',
              '${fcfa(c.totals['total'] ?? 0)}${c.gap != 0 ? ' (écart ${fcfa(c.gap)})' : ''}',
              color: c.gap != 0 ? Colors.red : null),
      ]),
    ]);
  }

  Widget _agentsTab(_Data d) {
    final total = <String, int>{};
    final count = <String, int>{};
    for (final v in d.sales.where((v) => !v.cancelled)) {
      total[v.agentName] = (total[v.agentName] ?? 0) + v.total;
      count[v.agentName] = (count[v.agentName] ?? 0) + 1;
    }
    final closures = <String, int>{};
    for (final c in d.sessions.where((c) => c.closed)) {
      closures[c.agentName] = (closures[c.agentName] ?? 0) + 1;
    }
    return ListView(padding: const EdgeInsets.all(10), children: [
      _card('Ventes par agent · $_periodLabel', [Bars(_top(total, 20))]),
      _card('Détail', [
        for (final e in _top(total, 50))
          SumRow(e.$1, '${count[e.$1]} vente(s) · ${closures[e.$1] ?? 0} clôture(s) · ${fcfa(e.$2)}'),
      ]),
    ]);
  }

  Future<void> _pdf(_Data d) async {
    final s = sessionOf(context, listen: false);
    final valid = d.sales.where((v) => !v.cancelled).toList();
    final sum = DaySummary.of(d.sales).addPayments(d.payments);
    final agents = <String, int>{};
    final prods = <String, int>{};
    for (final v in valid) {
      agents[v.agentName] = (agents[v.agentName] ?? 0) + v.total;
      for (final l in v.lines) {
        prods[l.name] = (prods[l.name] ?? 0) + l.total;
      }
    }
    final closed = d.sessions.where((c) => c.closed);
    final gap = closed.fold<int>(0, (a, c) => a + c.gap);
    final bytes = await PdfService.report(
      'Rapport',
      'Période : $_periodLabel',
      s.shopById(widget.shopId),
      [
        ('Ventes', [
          ('Nombre de ventes', '${sum.count}'),
          ('Chiffre d\'affaires', fcfa(sum.total)),
          ('Encaissé (avec crédits remboursés)', fcfa(sum.collected)),
          ('Remises', fcfa(sum.discount)),
          ('Vendu à crédit', fcfa(sum.credit)),
          ('Ventes annulées', '${sum.cancelled}'),
        ]),
        ('Moyens de paiement', [
          for (final e in payMethods.entries)
            if ((sum.byMethod[e.key] ?? 0) > 0) (e.value, fcfa(sum.byMethod[e.key] ?? 0)),
        ]),
        ('Ventes par agent', [for (final e in _top(agents, 30)) (e.$1, fcfa(e.$2))]),
        ('Produits les plus vendus', [for (final e in _top(prods, 15)) (e.$1, fcfa(e.$2))]),
        ('Caisse', [
          ('Clôtures', '${closed.length}'),
          ('Journées non clôturées', '${d.sessions.where((c) => !c.closed).length}'),
          ('Écart de caisse total', fcfa(gap)),
        ]),
      ],
    );
    await PdfService.open(bytes, 'Rapport_${_days.first}_${_days.last}');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rapports'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Tableau de bord'),
            Tab(text: 'Ventes'),
            Tab(text: 'Stock'),
            Tab(text: 'Caisse'),
            Tab(text: 'Agents'),
          ]),
        ),
        body: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(children: [
              for (final p in const [
                ('jour', 'Aujourd\'hui'),
                ('semaine', '7 jours'),
                ('mois', 'Ce mois'),
                ('perso', 'Période…'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(p.$1 == 'perso' && _period == 'perso' ? _periodLabel : p.$2),
                    selected: _period == p.$1,
                    onSelected: (_) => _setPeriod(p.$1),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<_Data>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
                final d = snap.data;
                if (d == null) return const Center(child: CircularProgressIndicator());
                return Stack(children: [
                  TabBarView(children: [
                    _dashboard(d),
                    _salesTab(d),
                    _stockTab(d),
                    _cashTab(d),
                    _agentsTab(d),
                  ]),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'pdf',
                      tooltip: 'Rapport PDF',
                      onPressed: () => _pdf(d),
                      child: const Icon(Icons.picture_as_pdf),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
