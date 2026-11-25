import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';

/// Petits éléments communs de la gestion commerciale.
Future<int?> askAmount(BuildContext context,
    {required String title, String label = 'Montant', String hint = '', int? initial}) {
  final c = TextEditingController(text: initial == null ? '' : '$initial');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, hintText: hint, suffixText: 'FCFA'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim()) ?? 0),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body,
    {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

/// Ligne « libellé ……… valeur » d'un récapitulatif.
class SumRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const SumRow(this.label, this.value, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(
        fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
        fontSize: bold ? 16 : 14.5,
        color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: st)),
        Text(value, style: st),
      ]),
    );
  }
}

/// Indique qu'une opération attend internet (enregistrée sur le téléphone).
class PendingIcon extends StatelessWidget {
  final bool pending;
  const PendingIcon(this.pending, {super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: pending
            ? 'Enregistré sur le téléphone, envoi au retour d\'internet'
            : 'Synchronisé',
        child: Icon(pending ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
            size: 18, color: pending ? Colors.orange : AppConfig.green),
      );
}

/// Saisie d'un paiement (montant + moyen). Renvoie (montant, moyen).
Future<(int, String)?> askPayment(BuildContext context, int remaining, String label) {
  final c = TextEditingController(text: '$remaining');
  var method = 'especes';
  return showDialog<(int, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('Paiement · $label'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reste à payer : $remaining FCFA',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Montant reçu', suffixText: 'FCFA'),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final m in const {
                'especes': 'Espèces',
                'orange': 'Orange Money',
                'moov': 'Moov Money',
                'wave': 'Wave',
                'autre': 'Autre',
              }.entries)
                ChoiceChip(
                  label: Text(m.value),
                  selected: method == m.key,
                  onSelected: (_) => set(() => method = m.key),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(c.text.trim()) ?? 0;
              if (v <= 0) return;
              Navigator.pop(ctx, (v > remaining ? remaining : v, method));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}
