import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config.dart';
import '../models/commerce.dart';
import '../models/shop.dart';
import '../utils.dart';

/// Documents PDF fabriqués sur le téléphone (aucune connexion nécessaire).
class PdfService {
  static const _green = PdfColor.fromInt(0xFF1E8B09);
  static const _grey = PdfColor.fromInt(0xFF666666);
  static const _pale = PdfColor.fromInt(0xFFEAF6E5);

  /// Police standard : on remplace les caractères qu'elle ne connaît pas.
  static String t(String s) {
    const map = {
      '’': "'", '‘': "'", '“': '"', '”': '"', '…': '...', '−': '-', '–': '-', '—': '-',
      '→': '->', '•': '-', 'œ': 'oe', 'Œ': 'OE', ' ': ' ', ' ': ' ',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (map.containsKey(ch)) {
        b.write(map[ch]);
      } else if (r < 256) {
        b.write(ch);
      }
    }
    return b.toString();
  }

  static String money(int v) => t(fcfa(v));

  /// Teinte très claire d'une couleur (mélangée à du blanc).
  static PdfColor _paleOf(int argb) {
    int mix(int c) => (c + (255 - c) * 0.88).round();
    final r = mix((argb >> 16) & 0xFF), g = mix((argb >> 8) & 0xFF), b = mix(argb & 0xFF);
    return PdfColor.fromInt(0xFF000000 | (r << 16) | (g << 8) | b);
  }

  static Future<pw.MemoryImage?> _logo() async {
    try {
      final d = await rootBundle.load(AppConfig.logo);
      return pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _header(pw.MemoryImage? logo, Shop shop, String title, String number,
      List<String> right) {
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (logo != null) pw.Container(width: 64, height: 64, child: pw.Image(logo)),
      if (logo != null) pw.SizedBox(width: 12),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(t(AppConfig.fullName),
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _green)),
          pw.Text(t(shop.name), style: const pw.TextStyle(fontSize: 10)),
          if (shop.address.isNotEmpty) pw.Text(t(shop.address), style: const pw.TextStyle(fontSize: 9)),
          if (shop.phone.isNotEmpty) pw.Text(t('Tél. ${shop.phone}'), style: const pw.TextStyle(fontSize: 9)),
          if (shop.whatsapp.isNotEmpty)
            pw.Text(t('WhatsApp ${shop.whatsapp}'), style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(t(title.toUpperCase()),
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(t(number), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        for (final r in right) pw.Text(t(r), style: const pw.TextStyle(fontSize: 9)),
      ]),
    ]);
  }

  static pw.Widget _sum(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(
              child: pw.Text(t(label),
                  style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null))),
          pw.Text(t(value),
              style: pw.TextStyle(
                  fontWeight: bold ? pw.FontWeight.bold : null, fontSize: bold ? 12 : 10)),
        ]),
      );

  static pw.Widget _footer(String text) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 18),
        child: pw.Text(t(text), style: const pw.TextStyle(fontSize: 8, color: _grey)),
      );

  /// Devis ou facture, selon le modèle choisi par la boutique.
  static Future<Uint8List> doc(BizDoc d, Shop shop,
      {int paid = 0, DocSettings st = const DocSettings()}) async {
    final logo = st.logoPos == 'aucun' ? null : await _logo();
    final mini = st.style == 'minimaliste';
    final color = mini ? PdfColors.black : PdfColor.fromInt(st.color);
    final pale = mini ? PdfColors.white : _paleOf(st.color);
    final sig = d.signed ? pw.MemoryImage(base64Decode('${d.signature['png']}')) : null;
    final c = d.customer;
    final p = pw.Document(title: '${d.title} ${d.number}');
    p.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        _styledHeader(st, color, logo, shop, d.title, d.number, [
          'Date : ${shortDate(d.at)}',
          if (d.dueDate.isNotEmpty)
            '${d.isInvoice ? 'Échéance' : 'Valable jusqu\'au'} : ${dayLabel(d.dueDate)}',
          if (d.fromQuote.isNotEmpty) 'Devis : ${d.fromQuote}',
          if (d.replaces.isNotEmpty) 'Remplace : ${d.replaces}',
          'Statut : ${d.displayStatus(paid)}',
        ]),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
              color: pale,
              border: st.style == 'professionnel' || mini
                  ? pw.Border.all(color: color, width: 0.6)
                  : null),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(t('Client : '), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(t(c.name), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (c.company.isNotEmpty) pw.Text(t(c.company)),
                if (c.phone.isNotEmpty) pw.Text(t('Tél. ${c.phone}')),
                if (c.address.isNotEmpty) pw.Text(t(c.address)),
                if (c.email.isNotEmpty) pw.Text(t(c.email)),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, color: mini ? PdfColors.black : PdfColors.white),
          headerDecoration: mini ? null : pw.BoxDecoration(color: color),
          border: st.tableStyle == 'grille'
              ? pw.TableBorder.all(color: PdfColors.grey400, width: 0.5)
              : const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
          oddRowDecoration: st.tableStyle == 'zebre' ? pw.BoxDecoration(color: pale) : null,
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          cellAlignments: {
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
          headers: [t('Réf.'), t('Désignation'), t('Qté'), t('Prix unit.'), t('Remise'), t('Montant')],
          data: [
            for (final l in d.lines)
              [
                t(l.ref),
                t(l.name),
                t('${l.qty} ${l.unit}'),
                money(l.price),
                l.discount > 0 ? money(l.discount) : '',
                money(l.total),
              ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Spacer(),
          pw.SizedBox(
            width: 230,
            child: pw.Column(children: [
              _sum('Sous-total', fcfa(d.subtotal)),
              if (d.discount > 0) _sum('Remise', '-${fcfa(d.discount)}'),
              if (d.taxRate > 0) _sum('Taxe (${d.taxRate} %)', fcfa(d.tax)),
              pw.Divider(),
              _sum('TOTAL', fcfa(d.total), bold: true),
              if (d.isInvoice && paid > 0) ...[
                _sum('Déjà payé', fcfa(paid)),
                _sum('Reste à payer', fcfa(d.total - paid), bold: true),
              ],
            ]),
          ),
        ]),
        if (d.notes.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(t('Conditions / remarques'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(t(d.notes), style: const pw.TextStyle(fontSize: 9.5)),
        ],
        pw.SizedBox(height: 24),
        if (st.showSignature || d.signed)
        pw.Row(children: [
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Text(t('Signature et cachet'), style: const pw.TextStyle(fontSize: 9)),
            pw.Container(
              width: 180,
              height: 70,
              alignment: pw.Alignment.center,
              child: sig == null ? pw.SizedBox() : pw.Image(sig),
            ),
            if (d.signed)
              pw.Text(t('${d.signature['byName'] ?? ''}'), style: const pw.TextStyle(fontSize: 8.5)),
          ]),
        ]),
        _footer('${st.footer.isEmpty ? '${AppConfig.fullName} - ${AppConfig.tagline}.' : st.footer} '
            '${st.legal.isEmpty ? '' : '${st.legal}. '}'
            '${d.signed ? 'Signature électronique interne à l\'application (non certifiée). ' : ''}'
            'Document établi par ${d.createdByName}.'),
      ],
    ));
    return p.save();
  }

  /// En-tête selon le modèle (bandeau coloré pour « moderne »).
  static pw.Widget _styledHeader(DocSettings st, PdfColor color, pw.MemoryImage? logo,
      Shop shop, String title, String number, List<String> right) {
    final info = <pw.Widget>[
      pw.Text(t(AppConfig.fullName),
          style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: st.style == 'moderne' ? PdfColors.white : color)),
      if (st.header.isNotEmpty)
        pw.Text(t(st.header),
            style: pw.TextStyle(
                fontSize: 9,
                fontStyle: pw.FontStyle.italic,
                color: st.style == 'moderne' ? PdfColors.white : _grey)),
      pw.Text(t(shop.name),
          style: pw.TextStyle(fontSize: 10, color: st.style == 'moderne' ? PdfColors.white : null)),
      if (shop.address.isNotEmpty)
        pw.Text(t(shop.address),
            style: pw.TextStyle(fontSize: 9, color: st.style == 'moderne' ? PdfColors.white : null)),
      if (shop.phone.isNotEmpty)
        pw.Text(t('Tél. ${shop.phone}${shop.whatsapp.isNotEmpty ? ' - WhatsApp ${shop.whatsapp}' : ''}'),
            style: pw.TextStyle(fontSize: 9, color: st.style == 'moderne' ? PdfColors.white : null)),
      if (st.email.isNotEmpty)
        pw.Text(t(st.email),
            style: pw.TextStyle(fontSize: 9, color: st.style == 'moderne' ? PdfColors.white : null)),
      if (st.legal.isNotEmpty)
        pw.Text(t(st.legal),
            style: pw.TextStyle(fontSize: 8, color: st.style == 'moderne' ? PdfColors.white : _grey)),
    ];
    final titleBox = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Container(
        padding: st.style == 'professionnel'
            ? const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : pw.EdgeInsets.zero,
        decoration: st.style == 'professionnel'
            ? pw.BoxDecoration(border: pw.Border.all(color: color, width: 1))
            : null,
        child: pw.Text(t(title.toUpperCase()),
            style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: st.style == 'moderne' ? PdfColors.white : color)),
      ),
      pw.Text(t(number),
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: st.style == 'moderne' ? PdfColors.white : null)),
      for (final r in right)
        pw.Text(t(r),
            style: pw.TextStyle(fontSize: 9, color: st.style == 'moderne' ? PdfColors.white : null)),
    ]);
    final logoW = logo == null
        ? null
        : pw.Container(
            width: 64,
            height: 64,
            padding: st.style == 'moderne' ? const pw.EdgeInsets.all(4) : pw.EdgeInsets.zero,
            color: st.style == 'moderne' ? PdfColors.white : null,
            child: pw.Image(logo));
    pw.Widget body;
    if (st.logoPos == 'centre') {
      body = pw.Column(children: [
        if (logoW != null) pw.Center(child: logoW),
        pw.SizedBox(height: 6),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: info)),
          titleBox,
        ]),
      ]);
    } else if (st.logoPos == 'droite') {
      body = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          ...info,
          pw.SizedBox(height: 6),
          titleBox,
        ])),
        if (logoW != null) logoW,
      ]);
    } else {
      body = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (logoW != null) logoW,
        if (logoW != null) pw.SizedBox(width: 12),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: info)),
        titleBox,
      ]);
    }
    if (st.style == 'moderne') {
      return pw.Container(padding: const pw.EdgeInsets.all(12), color: color, child: body);
    }
    if (st.style == 'professionnel') {
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: color, width: 2))),
        child: body,
      );
    }
    return body;
  }

  /// Rapport (sections de lignes « libellé : valeur »).
  static Future<Uint8List> report(String title, String subtitle, Shop shop,
      List<(String, List<(String, String)>)> sections) async {
    final logo = await _logo();
    final p = pw.Document(title: title);
    p.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        _header(logo, shop, title, subtitle, ['Édité le ${timeLabel(DateTime.now())}']),
        pw.SizedBox(height: 16),
        for (final sec in sections) ...[
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
            padding: const pw.EdgeInsets.all(5),
            color: _pale,
            child: pw.Text(t(sec.$1), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _green)),
          ),
          if (sec.$2.isEmpty) pw.Text(t('Aucune donnée.'), style: const pw.TextStyle(color: _grey)),
          for (final l in sec.$2) _sum(l.$1, l.$2),
        ],
        _footer('${AppConfig.fullName} - rapport généré sur le téléphone.'),
      ],
    ));
    return p.save();
  }

  /// Reçu de vente (format ticket).
  static Future<Uint8List> receipt(Sale v, Shop shop) async {
    final logo = await _logo();
    final p = pw.Document(title: 'Reçu ${v.number}');
    p.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if (logo != null) pw.Center(child: pw.Container(height: 40, child: pw.Image(logo))),
        pw.Center(
            child: pw.Text(t(AppConfig.shopName),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
        pw.Center(child: pw.Text(t(shop.name), style: const pw.TextStyle(fontSize: 8))),
        if (shop.phone.isNotEmpty)
          pw.Center(child: pw.Text(t('Tél. ${shop.phone}'), style: const pw.TextStyle(fontSize: 8))),
        pw.Divider(),
        pw.Text(t('Reçu ${v.number}'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.Text(t('${timeLabel(v.at)} - ${v.agentName}'), style: const pw.TextStyle(fontSize: 8)),
        if (v.customerName.isNotEmpty) pw.Text(t('Client : ${v.customerName}'), style: const pw.TextStyle(fontSize: 8)),
        pw.Divider(),
        for (final l in v.lines)
          pw.Row(children: [
            pw.Expanded(child: pw.Text(t('${l.qty} x ${l.name}'), style: const pw.TextStyle(fontSize: 8.5))),
            pw.Text(money(l.total), style: const pw.TextStyle(fontSize: 8.5)),
          ]),
        pw.Divider(),
        if (v.discount > 0) _sum('Remise', '-${fcfa(v.discount)}'),
        _sum('TOTAL', fcfa(v.total), bold: true),
        _sum('Paiement', payMethods[v.payMethod] ?? v.payMethod),
        if (v.due > 0) ...[_sum('Payé', fcfa(v.paid)), _sum('Reste à payer', fcfa(v.due), bold: true)],
        if (v.cancelled) pw.Text(t('VENTE ANNULÉE'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text(t('Merci pour votre confiance !'), style: const pw.TextStyle(fontSize: 8.5))),
      ]),
    ));
    return p.save();
  }

  /// Rapport de clôture journalière.
  static Future<Uint8List> closure(CashSession c, DaySummary sum, int cashOut,
      List<CashOut> outs, Shop shop) async {
    final logo = await _logo();
    final expected = c.closed ? c.expectedCash : c.openingFloat + (sum.byMethod['especes'] ?? 0) - cashOut;
    final p = pw.Document(title: 'Clôture ${c.day}');
    p.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _header(logo, shop, 'Clôture journalière', dayLabel(c.day), [
          'Agent : ${c.agentName}',
          c.closed ? 'Clôturée par ${c.closedByName}' : 'Journée NON clôturée',
        ]),
        pw.SizedBox(height: 20),
        _sum('Nombre de ventes', '${sum.count}'),
        for (final e in payMethods.entries)
          if ((sum.byMethod[e.key] ?? 0) > 0) _sum(e.value, fcfa(sum.byMethod[e.key] ?? 0)),
        if (sum.creditPaid > 0) _sum('dont crédits remboursés', fcfa(sum.creditPaid)),
        if (sum.discount > 0) _sum('Remises accordées', fcfa(sum.discount)),
        if (sum.cancelled > 0) _sum('Ventes annulées', '${sum.cancelled}'),
        pw.Divider(),
        _sum('Total des ventes', fcfa(sum.total), bold: true),
        _sum('Total encaissé', fcfa(sum.collected), bold: true),
        if (sum.credit > 0) _sum('Reste en crédit', fcfa(sum.credit)),
        pw.SizedBox(height: 16),
        pw.Text(t('Caisse (espèces)'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        _sum('Fond de caisse initial', fcfa(c.openingFloat)),
        _sum('+ Espèces reçues', fcfa(sum.byMethod['especes'] ?? 0)),
        _sum('- Sorties de caisse', fcfa(cashOut)),
        _sum('= Montant attendu', fcfa(expected), bold: true),
        if (c.closed) ...[
          _sum('Montant compté', fcfa(c.countedCash)),
          _sum('Écart', fcfa(c.gap), bold: true),
        ],
        for (final o in outs)
          pw.Text(t('- ${fcfa(o.amount)} : ${o.reason} (${o.userName})'),
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
        pw.SizedBox(height: 30),
        pw.Row(children: [
          pw.Expanded(child: pw.Text(t('Signature agent :'))),
          pw.Expanded(child: pw.Text(t('Signature responsable :'))),
        ]),
        _footer('Édité le ${timeLabel(DateTime.now())} - ${AppConfig.fullName}'),
      ]),
    ));
    return p.save();
  }

  /// Enregistre le PDF sur le téléphone et l'ouvre (lire, partager, imprimer).
  static Future<String> open(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/pdf');
    if (!await folder.exists()) await folder.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final f = File('${folder.path}/$safe.pdf');
    await f.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(f.path, type: 'application/pdf');
    return f.path;
  }
}
