import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/commerce.dart';
import 'commerce_service.dart';
import 'notify_service.dart';
import 'session.dart';

/// Devis et factures (hors ligne comme le reste).
class Docs {
  static final _fs = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> col(String kind) =>
      _fs.collection(kind == 'quote' ? 'quotes' : 'invoices');

  static Stream<List<BizDoc>> listOf(String shopId, String kind) => col(kind)
      .where('shopId', isEqualTo: shopId)
      .limit(1000)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map((d) => BizDoc.fromDoc(d, kind)).toList()
        ..sort((a, b) => b.at.compareTo(a.at)));

  static Stream<List<BizDoc>> ofCustomer(String shopId, String kind, String customerId) => col(kind)
      .where('shopId', isEqualTo: shopId)
      .where('customerId', isEqualTo: customerId)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map((d) => BizDoc.fromDoc(d, kind)).toList()
        ..sort((a, b) => b.at.compareTo(a.at)));

  static Stream<BizDoc?> stream(String kind, String id) => col(kind)
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? BizDoc.fromDoc(d, kind) : null);

  static Map<String, dynamic> _content(Customer c, List<DocLine> lines, int discount, int taxRate,
      String dueDate, String notes) {
    final t = DocTotals.of(lines, discount, taxRate);
    return {
      'customerId': customerIdFor(c.shopId, c.phone),
      'customer': c.toMap(),
      'lines': [for (final l in lines) l.toMap()],
      'subtotal': t.subtotal,
      'discount': t.discount,
      'taxRate': taxRate,
      'tax': t.tax,
      'total': t.total,
      'dueDate': dueDate,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Nouveau devis / nouvelle facture (brouillon). Renvoie l'identifiant.
  static Future<String> create({
    required Session s,
    required String shopId,
    required String kind,
    required Customer customer,
    required List<DocLine> lines,
    required int discount,
    required int taxRate,
    required String dueDate,
    required String notes,
    String fromQuote = '',
    String fromQuoteId = '',
    String replaces = '',
    WriteBatch? batch,
  }) async {
    final number = await Commerce.nextNumber(
        s, shopId, kind == 'quote' ? 'DEV' : 'FAC', kind);
    final dev = await Commerce.deviceId();
    final b = batch ?? Commerce.batch();
    final ref = col(kind).doc();
    b.set(ref, {
      ..._content(customer, lines, discount, taxRate, dueDate, notes),
      'shopId': shopId,
      'number': number,
      'status': 'brouillon',
      'fromQuote': fromQuote,
      'fromQuoteId': fromQuoteId,
      'replaces': replaces,
      'createdBy': s.uid,
      'createdByName': s.me.name,
      'deviceId': dev,
      'createdAt': FieldValue.serverTimestamp(),
      'localAt': DateTime.now().millisecondsSinceEpoch,
    });
    Commerce.upsertCustomer(b, shopId, customer.name, customer.phone, {
      if (customer.address.isNotEmpty) 'address': customer.address,
      if (customer.company.isNotEmpty) 'company': customer.company,
      if (customer.email.isNotEmpty) 'email': customer.email,
    });
    Commerce.log(b, s, shopId, kind == 'quote' ? 'creation_devis' : 'creation_facture', kind,
        ref.id, dev, {'numero': number});
    if (batch == null) Commerce.commit(b);
    return ref.id;
  }

  static Future<void> updateDraft(Session s, BizDoc d, Customer c, List<DocLine> lines,
      int discount, int taxRate, String dueDate, String notes) async {
    final dev = await Commerce.deviceId();
    final b = Commerce.batch();
    b.update(col(d.kind).doc(d.id), _content(c, lines, discount, taxRate, dueDate, notes));
    Commerce.upsertCustomer(b, d.shopId, c.name, c.phone);
    Commerce.log(b, s, d.shopId, 'modification_${d.kind}', d.kind, d.id, dev, {'numero': d.number});
    Commerce.commit(b);
  }

  static Future<void> setStatus(Session s, BizDoc d, String status, {String reason = ''}) async {
    final dev = await Commerce.deviceId();
    final b = Commerce.batch();
    b.update(col(d.kind).doc(d.id), {
      'status': status,
      if (reason.isNotEmpty) 'cancelReason': reason,
      if (status == 'annulee' || status == 'annule') ...{
        'cancelledBy': s.uid,
        'cancelledByName': s.me.name,
        'cancelledAt': FieldValue.serverTimestamp(),
      },
      if (status == 'validee') 'validatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Commerce.log(b, s, d.shopId, '${d.kind}_$status', d.kind, d.id, dev,
        {'numero': d.number, if (reason.isNotEmpty) 'motif': reason});
    Commerce.commit(b);
  }

  /// Signature (image PNG en base64), avec qui et quand.
  static Future<void> sign(Session s, BizDoc d, String pngBase64) async {
    final dev = await Commerce.deviceId();
    final b = Commerce.batch();
    b.update(col(d.kind).doc(d.id), {
      'signature': {
        'png': pngBase64,
        'by': s.uid,
        'byName': s.me.name,
        'at': DateTime.now().toIso8601String(),
        'deviceId': dev,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Commerce.log(b, s, d.shopId, 'signature', d.kind, d.id, dev, {'numero': d.number});
    Commerce.commit(b);
  }

  /// Devis accepté → facture (brouillon) ; le devis passe « converti ».
  static Future<String> convert(Session s, BizDoc q) async {
    final b = Commerce.batch();
    final due = dayKey(DateTime.now().add(const Duration(days: 30)));
    final id = await create(
      s: s,
      shopId: q.shopId,
      kind: 'invoice',
      customer: q.customer,
      lines: [for (final l in q.lines) l.copy()],
      discount: q.discount,
      taxRate: q.taxRate,
      dueDate: due,
      notes: q.notes,
      fromQuote: q.number,
      fromQuoteId: q.id,
      batch: b,
    );
    b.update(col('quote').doc(q.id), {
      'status': 'converti',
      'invoiceId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Commerce.commit(b);
    return id;
  }

  /// Correction d'une facture validée : annulation + nouvelle facture (brouillon).
  static Future<String> correct(Session s, BizDoc inv, String reason) async {
    final b = Commerce.batch();
    final id = await create(
      s: s,
      shopId: inv.shopId,
      kind: 'invoice',
      customer: inv.customer,
      lines: [for (final l in inv.lines) l.copy()],
      discount: inv.discount,
      taxRate: inv.taxRate,
      dueDate: inv.dueDate,
      notes: inv.notes,
      fromQuote: inv.fromQuote,
      fromQuoteId: inv.fromQuoteId,
      replaces: inv.number,
      batch: b,
    );
    b.update(col('invoice').doc(inv.id), {
      'status': 'annulee',
      'cancelReason': reason,
      'cancelledBy': s.uid,
      'cancelledByName': s.me.name,
      'cancelledAt': FieldValue.serverTimestamp(),
      'replacedBy': id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Commerce.commit(b);
    return id;
  }

  // ---------- Modèles de documents ----------
  static DocumentReference<Map<String, dynamic>> settingsRef(String shopId) =>
      _fs.collection('docSettings').doc(shopId);

  static Future<DocSettings> settings(String shopId) async {
    try {
      final d = await settingsRef(shopId).get().timeout(const Duration(seconds: 6));
      return DocSettings.fromMap(d.data());
    } catch (_) {
      try {
        final d = await settingsRef(shopId).get(const GetOptions(source: Source.cache));
        return DocSettings.fromMap(d.data());
      } catch (_) {
        return const DocSettings();
      }
    }
  }

  static Future<void> saveSettings(Session s, String shopId, DocSettings st) async {
    final dev = await Commerce.deviceId();
    final b = Commerce.batch();
    b.set(settingsRef(shopId), {
      ...st.toMap(),
      'shopId': shopId,
      'updatedBy': s.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Commerce.log(b, s, shopId, 'modele_documents', 'docSettings', shopId, dev, {'style': st.style});
    Commerce.commit(b);
  }

  /// Proposition de mise en page par l'IA (jamais de prix ni de données client).
  static Future<DocSettings> aiTemplate(String prompt, DocSettings base) async {
    final (code, j) = await NotifyService.callWorker({'action': 'ai_template', 'prompt': prompt});
    if (code != 200 || j['template'] is! Map) {
      final err = '${j['error'] ?? ''}';
      if (code == 0) throw Exception(err.isEmpty ? 'Serveur indisponible.' : err);
      if (err.contains('IA non configur')) {
        throw Exception('L\'IA n\'est pas encore activée sur le serveur Cloudflare.');
      }
      if (code == 400) throw Exception('Le serveur Cloudflare n\'est pas à jour.');
      throw Exception('L\'IA n\'a pas pu proposer de modèle. Réessayez.');
    }
    final m = Map<String, dynamic>.from(j['template'] as Map);
    final hex = '${m['color'] ?? ''}'.replaceFirst('#', '');
    final color = int.tryParse(hex, radix: 16);
    final p = DocSettings.fromMap({
      ...base.toMap(),
      ...m,
      'color': color == null || hex.length != 6 ? base.color : (0xFF000000 | color),
    });
    // Seule la présentation change : les textes légaux et conditions restent ceux de la boutique.
    return p.copyWith(email: base.email, legal: base.legal, conditions: base.conditions);
  }
}
