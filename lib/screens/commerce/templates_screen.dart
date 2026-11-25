import 'package:flutter/material.dart';

import '../../models/commerce.dart';
import '../../services/commerce_service.dart';
import '../../services/docs_service.dart';
import '../../services/pdf_service.dart';
import '../../services/session.dart';
import '../../utils.dart';

/// Modèles de devis / factures et informations de la boutique.
class TemplatesScreen extends StatefulWidget {
  final String shopId;
  const TemplatesScreen({super.key, required this.shopId});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  DocSettings? _st;
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _conditions = TextEditingController();
  final _email = TextEditingController();
  final _legal = TextEditingController();
  final _ai = TextEditingController();
  bool _busy = false;

  static const _colors = [
    0xFF1E8B09, 0xFF111111, 0xFF0D47A1, 0xFF00838F, 0xFF6A1B9A,
    0xFFB71C1C, 0xFFEF6C00, 0xFF5D4037, 0xFF37474F,
  ];

  @override
  void initState() {
    super.initState();
    Docs.settings(widget.shopId).then((st) {
      if (!mounted) return;
      _fill(st);
    });
  }

  void _fill(DocSettings st) {
    setState(() {
      _st = st;
      _header.text = st.header;
      _footer.text = st.footer;
      _conditions.text = st.conditions;
      _email.text = st.email;
      _legal.text = st.legal;
    });
  }

  DocSettings get _current => _st!.copyWith(
        header: _header.text.trim(),
        footer: _footer.text.trim(),
        conditions: _conditions.text.trim(),
        email: _email.text.trim(),
        legal: _legal.text.trim(),
      );

  Future<void> _preview() async {
    final s = sessionOf(context, listen: false);
    final sample = BizDoc(
      id: 'apercu',
      kind: 'invoice',
      shopId: widget.shopId,
      number: 'FAC-APERCU-000001',
      status: 'brouillon',
      customer: Customer(
          id: '', shopId: widget.shopId, name: 'Client exemple', phone: '70 00 00 00',
          address: 'Bamako', company: 'Exemple SARL'),
      lines: [
        DocLine(ref: 'IMP-01', name: 'Impression couleur A4', qty: 100, unit: 'page', price: 150),
        DocLine(ref: 'TS-02', name: 'T-shirt personnalisé', qty: 5, unit: 'pièce', price: 5000, discount: 1000),
      ],
      subtotal: 39000,
      discount: 0,
      taxRate: 0,
      tax: 0,
      total: 39000,
      dueDate: '',
      fromQuote: '',
      fromQuoteId: '',
      replaces: '',
      notes: _conditions.text.trim(),
      createdByName: s.me.name,
      at: DateTime.now(),
      signature: const {},
      cancelReason: '',
      pending: false,
    );
    final bytes = await PdfService.doc(sample, s.shopById(widget.shopId), st: _current);
    await PdfService.open(bytes, 'Apercu_modele');
  }

  Future<void> _save() async {
    final s = sessionOf(context, listen: false);
    await Docs.saveSettings(s, widget.shopId, _current);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Modèle enregistré.')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _askAi() async {
    final prompt = _ai.text.trim();
    if (prompt.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final st = await Docs.aiTemplate(prompt, _current);
      _fill(st);
      messenger.showSnackBar(const SnackBar(
          content: Text('Proposition appliquée : vérifiez avec « Aperçu », puis enregistrez.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chips(String title, Map<String, String> options, String value, void Function(String) on) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 6, children: [
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: value == e.key,
                onSelected: (_) => setState(() => on(e.key)),
              ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return Scaffold(
      appBar: AppBar(title: const Text('Modèles de documents')),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              Card(
                color: const Color(0xFFF3E5F5),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('✨ Créer un modèle avec l\'IA',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const Text(
                      'Décrivez la présentation voulue. L\'IA ne change que la mise en page '
                      '(jamais les prix, montants, numéros ou clients).',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                    TextField(
                      controller: _ai,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          hintText: 'Ex : facture moderne bleue, logo en haut à gauche, signature en bas'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _askAi,
                      icon: _busy
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: const Text('Proposer un modèle'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              _chips('Modèle', docStyles, st.style, (v) => _st = st.copyWith(style: v)),
              const Text('Couleur', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _colors)
                  GestureDetector(
                    onTap: () => setState(() => _st = st.copyWith(color: c)),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(c),
                      child: st.color == c ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              _chips('Position du logo', logoPositions, st.logoPos, (v) => _st = st.copyWith(logoPos: v)),
              _chips('Tableau des articles', tableStyles, st.tableStyle,
                  (v) => _st = st.copyWith(tableStyle: v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: st.showSignature,
                onChanged: (v) => setState(() => _st = st.copyWith(showSignature: v)),
                title: const Text('Zone de signature'),
              ),
              TextField(controller: _header, decoration: const InputDecoration(labelText: 'Phrase d\'en-tête (ex : slogan)')),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'E-mail de la boutique')),
              TextField(controller: _legal, decoration: const InputDecoration(labelText: 'Identifiants (NIF, RCCM…)')),
              TextField(
                controller: _conditions,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Conditions proposées par défaut'),
              ),
              TextField(controller: _footer, decoration: const InputDecoration(labelText: 'Pied de page')),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _preview,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Aperçu PDF'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer'),
                  ),
                ),
              ]),
              const SizedBox(height: 30),
            ]),
    );
  }
}

/// Journal d'activité (responsable / Super Admin).
class ActivityScreen extends StatefulWidget {
  final String shopId;
  const ActivityScreen({super.key, required this.shopId});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

const _actionLabels = {
  'vente': 'Vente',
  'annulation_vente': 'Annulation de vente',
  'mouvement_stock': 'Mouvement de stock',
  'inventaire': 'Inventaire',
  'creation_produit': 'Création de produit',
  'modification_produit': 'Modification de produit',
  'ouverture_caisse': 'Ouverture de caisse',
  'sortie_caisse': 'Sortie de caisse',
  'cloture': 'Clôture journalière',
  'paiement': 'Paiement client',
  'fiche_client': 'Fiche client',
  'creation_devis': 'Création de devis',
  'creation_facture': 'Création de facture',
  'signature': 'Signature',
  'modele_documents': 'Modèle de documents',
};

class _ActivityScreenState extends State<ActivityScreen> {
  DateTime _day = DateTime.now();
  Future<List<Map<String, dynamic>>>? _f;
  String _q = '';

  void _load() => _f = Commerce.logsOfDays(widget.shopId, [dayKey(_day)]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d\'activité'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _day, firstDate: DateTime(2025), lastDate: DateTime.now());
              if (d == null) return;
              setState(() {
                _day = d;
                _load();
              });
            },
            icon: const Icon(Icons.calendar_month),
            label: Text(dayLabel(dayKey(_day))),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Personne, action, numéro…'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
              final all = snap.data;
              if (all == null) return const Center(child: CircularProgressIndicator());
              final list = all.where((m) {
                if (_q.isEmpty) return true;
                return '${m['userName']} ${m['action']} ${m['details']}'.toLowerCase().contains(_q);
              }).toList();
              if (list.isEmpty) {
                return const Center(child: Text('Aucune activité.', style: TextStyle(color: Colors.black54)));
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = list[i];
                  final at = DateTime.fromMillisecondsSinceEpoch(((m['localAt'] as num?) ?? 0).toInt());
                  final details = (m['details'] as Map?) ?? const {};
                  final action = '${m['action'] ?? ''}';
                  return ListTile(
                    dense: true,
                    title: Text(_actionLabels[action] ?? action.replaceAll('_', ' '),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      '${m['userName'] ?? ''} · ${timeLabel(at)}',
                      if (details.isNotEmpty)
                        details.entries.map((e) => '${e.key} : ${e.value}').join(' · '),
                    ].join('\n')),
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
