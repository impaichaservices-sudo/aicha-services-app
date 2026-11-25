import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../models/commerce.dart';
import 'offline_queue.dart';
import 'session.dart';

/// Gestion commerciale : produits, stock, ventes, caisse et clôtures.
///
/// Hors ligne : tout passe par Firestore et son cache sur le téléphone.
/// Les écritures sont enregistrées localement puis envoyées UNE SEULE fois
/// au retour d'internet (identifiants créés sur le téléphone, mouvements de
/// stock en « +/− » : deux ventes hors ligne s'additionnent sans s'écraser).
class Commerce {
  static final _fs = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get products => _fs.collection('products');
  static CollectionReference<Map<String, dynamic>> get moves => _fs.collection('stockMovements');
  static CollectionReference<Map<String, dynamic>> get sales => _fs.collection('sales');
  static CollectionReference<Map<String, dynamic>> get sessions => _fs.collection('cashSessions');
  static CollectionReference<Map<String, dynamic>> get cashOuts => _fs.collection('cashMovements');
  static CollectionReference<Map<String, dynamic>> get logs => _fs.collection('activityLogs');

  // ---------- Identité du téléphone ----------
  static Map<String, dynamic>? _device;

  static Future<File> _deviceFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/appareil.json');
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Map<String, dynamic>> _loadDevice() async {
    if (_device != null) return _device!;
    try {
      final f = await _deviceFile();
      if (await f.exists()) {
        _device = Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
      }
    } catch (_) {}
    _device ??= {'id': _randomId(), 'letters': <String, dynamic>{}, 'seq': <String, dynamic>{}};
    await _saveDevice();
    return _device!;
  }

  static Future<void> _saveDevice() async {
    try {
      final f = await _deviceFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_device));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  static Future<String> deviceId() async => (await _loadDevice())['id'] as String;

  static String _letters(int i) {
    var n = i;
    var s = '';
    do {
      s = String.fromCharCode(65 + n % 26) + s;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return s;
  }

  /// Lettre du téléphone pour une boutique (A, B, C…). Donnée une seule fois,
  /// la première fois (connexion nécessaire), puis gardée sur le téléphone.
  static Future<String> deviceLetter(Session s, String shopId) async {
    final d = await _loadDevice();
    final letters = Map<String, dynamic>.from(d['letters'] as Map? ?? {});
    final known = letters[shopId];
    if (known is String && known.isNotEmpty) return known;
    final ref = _fs.collection('shopDevices').doc(shopId);
    final id = d['id'] as String;
    final letter = await _fs.runTransaction<String>((t) async {
      final snap = await t.get(ref);
      final count = (snap.data()?['count'] as num?)?.toInt() ?? 0;
      final l = _letters(count);
      t.set(ref, {'count': count + 1}, SetOptions(merge: true));
      t.set(ref.collection('list').doc(id), {
        'letter': l,
        'uid': s.uid,
        'name': s.me.name,
        'at': FieldValue.serverTimestamp(),
      });
      return l;
    }).timeout(const Duration(seconds: 15));
    letters[shopId] = letter;
    d['letters'] = letters;
    await _saveDevice();
    return letter;
  }

  static Future<int> _nextSeq(String shopId) async {
    final d = await _loadDevice();
    final seq = Map<String, dynamic>.from(d['seq'] as Map? ?? {});
    final n = ((seq[shopId] as num?)?.toInt() ?? 0) + 1;
    seq[shopId] = n;
    d['seq'] = seq;
    await _saveDevice();
    return n;
  }

  static String shopCode(Session s, String shopId) {
    final c = s.shopById(shopId).code.trim().toUpperCase();
    return c.isEmpty ? 'AS' : c;
  }

  /// Écriture enregistrée tout de suite sur le téléphone, envoyée dès que possible.
  static void _commit(WriteBatch b) => SyncStatus.trackWrite(b.commit());
  static void commit(WriteBatch b) => _commit(b);
  static WriteBatch batch() => _fs.batch();
  static void log(WriteBatch b, Session s, String shopId, String action, String objectType,
          String objectId, String device, [Map<String, dynamic>? details]) =>
      _log(b, s, shopId, action, objectType, objectId, device, details);

  /// Numéro suivant pour une série (« quote », « invoice »…) sur ce téléphone.
  static Future<String> nextNumber(Session s, String shopId, String prefix, String series) async {
    final letter = await deviceLetter(s, shopId);
    final seq = await _nextSeq('${shopId}_$series');
    return '$prefix-${shopCode(s, shopId)}-$letter-${seq.toString().padLeft(6, '0')}';
  }

  static CollectionReference<Map<String, dynamic>> get customers => _fs.collection('customers');
  static CollectionReference<Map<String, dynamic>> get payments => _fs.collection('payments');

  /// Fiche client créée ou complétée (identifiant = boutique + téléphone : pas de doublon).
  static void upsertCustomer(WriteBatch b, String shopId, String name, String phone,
      [Map<String, dynamic> extra = const {}]) {
    final id = customerIdFor(shopId, phone);
    if (id.isEmpty) return;
    b.set(
        customers.doc(id),
        {
          'shopId': shopId,
          'phone': phone,
          if (name.isNotEmpty) 'name': name,
          ...extra,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
  }

  static void _log(WriteBatch b, Session s, String shopId, String action,
      String objectType, String objectId, String device, [Map<String, dynamic>? details]) {
    b.set(logs.doc(), {
      'shopId': shopId,
      'userId': s.uid,
      'userName': s.me.name,
      'action': action,
      'objectType': objectType,
      'objectId': objectId,
      'deviceId': device,
      'details': details ?? const {},
      'day': dayKey(DateTime.now()),
      'at': FieldValue.serverTimestamp(),
      'localAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---------- Produits ----------
  static Stream<List<Product>> productsOf(String shopId) => products
      .where('shopId', isEqualTo: shopId)
      .limit(2000)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map(Product.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  static Stream<Product?> productStream(String id) => products
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? Product.fromDoc(d) : null);

  static Future<String> createProduct(Session s, String shopId, Product p, int initialStock) async {
    final dev = await deviceId();
    final b = _fs.batch();
    final ref = products.doc();
    b.set(ref, {
      ...p.editableFields(),
      'shopId': shopId,
      'stock': p.trackStock ? initialStock : 0,
      'lastMovementId': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (p.trackStock && initialStock != 0) {
      b.set(moves.doc(), _moveData(s, shopId, ref.id, p.name, initialStock, 'entree',
          'Stock initial', '', '', dev));
    }
    _log(b, s, shopId, 'creation_produit', 'product', ref.id, dev, {'name': p.name});
    _commit(b);
    return ref.id;
  }

  static Future<void> updateProduct(Session s, Product p) async {
    final dev = await deviceId();
    final b = _fs.batch();
    b.update(products.doc(p.id), {...p.editableFields(), 'updatedAt': FieldValue.serverTimestamp()});
    _log(b, s, p.shopId, 'modification_produit', 'product', p.id, dev, {'name': p.name});
    _commit(b);
  }

  // ---------- Stock ----------
  static Map<String, dynamic> _moveData(Session s, String shopId, String productId,
      String productName, int qty, String type, String reason, String ref, String refNumber,
      String device) => {
        'shopId': shopId,
        'productId': productId,
        'productName': productName,
        'qty': qty,
        'type': type,
        'userId': s.uid,
        'userName': s.me.name,
        'deviceId': device,
        'reason': reason,
        'ref': ref,
        'refNumber': refNumber,
        'day': dayKey(DateTime.now()),
        'createdAt': FieldValue.serverTimestamp(),
        'localAt': DateTime.now().millisecondsSinceEpoch,
      };

  /// Ajoute au lot : le mouvement + la variation du stock du produit.
  static void _move(WriteBatch b, Session s, String shopId, String productId, String productName,
      int qty, String type, String reason, String device, {String ref = '', String refNumber = ''}) {
    final m = moves.doc();
    b.set(m, _moveData(s, shopId, productId, productName, qty, type, reason, ref, refNumber, device));
    b.update(products.doc(productId), {
      'stock': FieldValue.increment(qty),
      'lastMovementId': m.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> stockMove(Session s, Product p, int qty, String type, String reason) async {
    if (qty == 0) return;
    final dev = await deviceId();
    final b = _fs.batch();
    _move(b, s, p.shopId, p.id, p.name, qty, type, reason, dev);
    _log(b, s, p.shopId, 'mouvement_stock', 'product', p.id, dev,
        {'type': type, 'qty': qty, 'reason': reason});
    _commit(b);
  }

  /// Inventaire : une correction par produit compté (écart réel − théorique).
  static Future<int> inventory(Session s, String shopId, Map<Product, int> counted) async {
    final dev = await deviceId();
    final b = _fs.batch();
    var n = 0;
    counted.forEach((p, real) {
      final gap = real - p.stock;
      if (gap == 0) return;
      _move(b, s, shopId, p.id, p.name, gap, 'inventaire',
          'Inventaire : ${p.stock} → $real', dev);
      n++;
    });
    if (n == 0) return 0;
    _log(b, s, shopId, 'inventaire', 'shop', shopId, dev, {'corrections': n});
    _commit(b);
    return n;
  }

  static Stream<List<StockMove>> movesOf(String shopId, String productId) => moves
      .where('shopId', isEqualTo: shopId)
      .where('productId', isEqualTo: productId)
      .limit(500)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map(StockMove.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));

  // ---------- Caisse (journée) ----------
  static String sessionId(String shopId, String agentId, String day) =>
      '${shopId}_${agentId}_${day.replaceAll('-', '')}';

  static Stream<CashSession?> sessionStream(String id) => sessions
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? CashSession.fromDoc(d) : null);

  static Future<void> openSession(Session s, String shopId, int openingFloat) async {
    final day = dayKey(DateTime.now());
    final id = sessionId(shopId, s.uid, day);
    final dev = await deviceId();
    final b = _fs.batch();
    b.set(sessions.doc(id), {
      'shopId': shopId,
      'agentId': s.uid,
      'agentName': s.me.name,
      'day': day,
      'openingFloat': openingFloat,
      'status': 'ouverte',
      'openedAt': FieldValue.serverTimestamp(),
      'deviceId': dev,
    });
    _log(b, s, shopId, 'ouverture_caisse', 'cashSession', id, dev, {'fond': openingFloat});
    _commit(b);
  }

  static Stream<List<CashSession>> sessionsOfDay(String shopId, String day) => sessions
      .where('shopId', isEqualTo: shopId)
      .where('day', isEqualTo: day)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map(CashSession.fromDoc).toList()
        ..sort((a, b) => a.agentName.compareTo(b.agentName)));

  static Stream<List<CashSession>> mySessions(String shopId, String uid) => sessions
      .where('shopId', isEqualTo: shopId)
      .where('agentId', isEqualTo: uid)
      .limit(120)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map(CashSession.fromDoc).toList()..sort((a, b) => b.day.compareTo(a.day)));

  /// Ventes d'une journée de caisse (mine = vendeur qui consulte les siennes).
  static Stream<List<Sale>> salesOfSession(CashSession c, {required bool mine}) {
    Query<Map<String, dynamic>> q = sales.where('sessionId', isEqualTo: c.id);
    q = mine
        ? q.where('agentId', isEqualTo: c.agentId)
        : q.where('shopId', isEqualTo: c.shopId);
    return q
        .snapshots(includeMetadataChanges: true)
        .map((x) => x.docs.map(Sale.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));
  }

  static Stream<List<Sale>> salesOfDay(String shopId, String day) => sales
      .where('shopId', isEqualTo: shopId)
      .where('day', isEqualTo: day)
      .snapshots(includeMetadataChanges: true)
      .map((x) => x.docs.map(Sale.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));

  static Stream<List<CashOut>> cashOutsOf(CashSession c, {required bool mine}) {
    Query<Map<String, dynamic>> q = cashOuts.where('sessionId', isEqualTo: c.id);
    q = mine
        ? q.where('agentId', isEqualTo: c.agentId)
        : q.where('shopId', isEqualTo: c.shopId);
    return q
        .snapshots(includeMetadataChanges: true)
        .map((x) => x.docs.map(CashOut.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));
  }

  static Future<void> addCashOut(Session s, CashSession c, int amount, String reason) async {
    final dev = await deviceId();
    final b = _fs.batch();
    final ref = cashOuts.doc();
    b.set(ref, {
      'shopId': c.shopId,
      'sessionId': c.id,
      'agentId': c.agentId,
      'amount': amount,
      'reason': reason,
      'userId': s.uid,
      'userName': s.me.name,
      'deviceId': dev,
      'createdAt': FieldValue.serverTimestamp(),
      'localAt': DateTime.now().millisecondsSinceEpoch,
    });
    _log(b, s, c.shopId, 'sortie_caisse', 'cashSession', c.id, dev,
        {'montant': amount, 'motif': reason});
    _commit(b);
  }

  /// Clôture : une seule par journée (même identifiant), rejouable sans doublon.
  static Future<void> closeSession(Session s, CashSession c, DaySummary sum, int cashOut,
      int counted) async {
    final dev = await deviceId();
    final expected = c.openingFloat + (sum.byMethod['especes'] ?? 0) - cashOut;
    final b = _fs.batch();
    b.update(sessions.doc(c.id), {
      'status': 'cloturee',
      'salesCount': sum.count,
      'totals': {
        ...sum.byMethod,
        'total': sum.total,
        'remises': sum.discount,
        'credit': sum.credit,
        'encaisse': sum.collected,
        'annulees': sum.cancelled,
        'creditsRembourses': sum.creditPaid,
      },
      'cashOut': cashOut,
      'expectedCash': expected,
      'countedCash': counted,
      'gap': counted - expected,
      'closedBy': s.uid,
      'closedByName': s.me.name,
      'closedAt': FieldValue.serverTimestamp(),
      'closedDevice': dev,
    });
    _log(b, s, c.shopId, 'cloture', 'cashSession', c.id, dev,
        {'total': sum.total, 'ecart': counted - expected, 'agent': c.agentName});
    _commit(b);
  }

  // ---------- Ventes ----------
  static Future<Sale> createSale({
    required Session s,
    required String shopId,
    required CashSession session,
    required List<SaleLine> lines,
    required int discount,
    required String payMethod,
    required int paid,
    String customerName = '',
    String customerPhone = '',
  }) async {
    final letter = await deviceLetter(s, shopId);
    final seq = await _nextSeq(shopId);
    final number = 'VTE-${shopCode(s, shopId)}-$letter-${seq.toString().padLeft(6, '0')}';
    final dev = await deviceId();
    final subtotal = lines.fold<int>(0, (a, l) => a + l.total);
    final total = subtotal - discount;
    final isCredit = payMethod == 'credit';
    final paidNow = !isCredit ? total : (paid < 0 ? 0 : (paid > total ? total : paid));
    final ref = sales.doc();
    final b = _fs.batch();
    final custId = customerIdFor(shopId, customerPhone);
    upsertCustomer(b, shopId, customerName, customerPhone);
    final data = {
      'customerId': custId,
      'hasCredit': total - paidNow > 0,
      'shopId': shopId,
      'number': number,
      'sessionId': session.id,
      'day': session.day,
      'agentId': s.uid,
      'agentName': s.me.name,
      'deviceId': dev,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'lines': [for (final l in lines) l.toMap()],
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'paid': paidNow,
      'due': total - paidNow,
      'payMethod': payMethod,
      'status': 'validee',
      'createdAt': FieldValue.serverTimestamp(),
      'localAt': DateTime.now().millisecondsSinceEpoch,
    };
    b.set(ref, data);
    for (final l in lines) {
      if (!l.trackStock) continue;
      _move(b, s, shopId, l.productId, l.name, -l.qty, 'vente', 'Vente $number', dev,
          ref: ref.id, refNumber: number);
    }
    _log(b, s, shopId, 'vente', 'sale', ref.id, dev, {'numero': number, 'total': total});
    _commit(b);
    return Sale(
      id: ref.id,
      shopId: shopId,
      number: number,
      sessionId: session.id,
      day: session.day,
      agentId: s.uid,
      agentName: s.me.name,
      customerName: customerName,
      customerPhone: customerPhone,
      lines: lines,
      subtotal: subtotal,
      discount: discount,
      total: total,
      paid: paidNow,
      due: total - paidNow,
      payMethod: payMethod,
      status: 'validee',
      cancelReason: '',
      at: DateTime.now(),
      pending: true,
    );
  }

  /// Annulation (journée encore ouverte) : la vente reste visible, barrée,
  /// et le stock est remis (mouvements « retour »).
  static Future<void> cancelSale(Session s, Sale v, String reason) async {
    final dev = await deviceId();
    final b = _fs.batch();
    b.update(sales.doc(v.id), {
      'status': 'annulee',
      'cancelReason': reason,
      'cancelledBy': s.uid,
      'cancelledByName': s.me.name,
      'cancelledAt': FieldValue.serverTimestamp(),
    });
    for (final l in v.lines) {
      if (!l.trackStock) continue;
      _move(b, s, v.shopId, l.productId, l.name, l.qty, 'retour',
          'Annulation ${v.number}', dev, ref: v.id, refNumber: v.number);
    }
    _log(b, s, v.shopId, 'annulation_vente', 'sale', v.id, dev,
        {'numero': v.number, 'motif': reason});
    _commit(b);
  }

  // ---------- Clients et paiements ----------
  static Stream<List<Customer>> customersOf(String shopId) => customers
      .where('shopId', isEqualTo: shopId)
      .limit(3000)
      .snapshots(includeMetadataChanges: true)
      .map((q) => q.docs.map(Customer.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  static Stream<Customer?> customerStream(String id) => customers
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? Customer.fromDoc(d) : null);

  static Future<void> saveCustomer(Session s, Customer c) async {
    final dev = await deviceId();
    final b = _fs.batch();
    upsertCustomer(b, c.shopId, c.name, c.phone, {
      'address': c.address,
      'city': c.city,
      'company': c.company,
      'email': c.email,
      'notes': c.notes,
    });
    _log(b, s, c.shopId, 'fiche_client', 'customer', customerIdFor(c.shopId, c.phone), dev,
        {'name': c.name});
    _commit(b);
  }

  static Stream<List<Sale>> creditSales(String shopId) => sales
      .where('shopId', isEqualTo: shopId)
      .where('hasCredit', isEqualTo: true)
      .snapshots(includeMetadataChanges: true)
      .map((x) => x.docs.map(Sale.fromDoc).where((v) => !v.cancelled).toList()
        ..sort((a, b) => b.at.compareTo(a.at)));

  static Stream<List<Sale>> salesOfCustomer(String shopId, String customerId) => sales
      .where('shopId', isEqualTo: shopId)
      .where('customerId', isEqualTo: customerId)
      .snapshots(includeMetadataChanges: true)
      .map((x) => x.docs.map(Sale.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));

  static Stream<List<Payment>> paymentsWhere(String shopId, String field, String value) => payments
      .where('shopId', isEqualTo: shopId)
      .where(field, isEqualTo: value)
      .snapshots(includeMetadataChanges: true)
      .map((x) => x.docs.map(Payment.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));

  /// Paiements reçus pendant une journée de caisse (comptés dans la clôture).
  static Stream<List<Payment>> paymentsOfSession(CashSession c, {required bool mine}) {
    Query<Map<String, dynamic>> q = payments.where('sessionId', isEqualTo: c.id);
    q = mine ? q.where('userId', isEqualTo: c.agentId) : q.where('shopId', isEqualTo: c.shopId);
    return q
        .snapshots(includeMetadataChanges: true)
        .map((x) => x.docs.map(Payment.fromDoc).toList());
  }

  /// Ma journée de caisse ouverte aujourd'hui (lue sur le téléphone), sinon ''.
  static Future<String> myOpenSessionId(Session s, String shopId) async {
    final id = sessionId(shopId, s.uid, dayKey(DateTime.now()));
    try {
      final d = await sessions.doc(id).get(const GetOptions(source: Source.cache));
      if (d.exists && d.data()?['status'] == 'ouverte') return id;
    } catch (_) {}
    try {
      final d = await sessions.doc(id).get().timeout(const Duration(seconds: 4));
      if (d.exists && d.data()?['status'] == 'ouverte') return id;
    } catch (_) {}
    return '';
  }

  static Future<void> recordPayment({
    required Session s,
    required String shopId,
    required String customerId,
    required String targetType,
    required String targetId,
    required String targetNumber,
    required int amount,
    required String method,
  }) async {
    final dev = await deviceId();
    final sid = await myOpenSessionId(s, shopId);
    final b = _fs.batch();
    final ref = payments.doc();
    b.set(ref, {
      'shopId': shopId,
      'customerId': customerId,
      'targetType': targetType,
      'targetId': targetId,
      'targetNumber': targetNumber,
      'amount': amount,
      'method': method,
      'sessionId': sid,
      'day': dayKey(DateTime.now()),
      'userId': s.uid,
      'userName': s.me.name,
      'deviceId': dev,
      'createdAt': FieldValue.serverTimestamp(),
      'localAt': DateTime.now().millisecondsSinceEpoch,
    });
    _log(b, s, shopId, 'paiement', targetType, targetId, dev,
        {'numero': targetNumber, 'montant': amount, 'moyen': method});
    _commit(b);
  }

  // ---------- Rapports (par période) ----------
  /// Jours d'une période (« 2026-11-01 » …), du plus ancien au plus récent.
  static List<String> daysBetween(DateTime from, DateTime to) {
    final out = <String>[];
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end) && out.length < 400) {
      out.add(dayKey(d));
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  /// Lit une collection pour une liste de jours (par paquets de 30 jours).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _byDays(
      CollectionReference<Map<String, dynamic>> col, String shopId, List<String> days) async {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < days.length; i += 30) {
      final chunk = days.sublist(i, i + 30 > days.length ? days.length : i + 30);
      final q = await col
          .where('shopId', isEqualTo: shopId)
          .where('day', whereIn: chunk)
          .get();
      out.addAll(q.docs);
    }
    return out;
  }

  static Future<List<Sale>> salesOfDays(String shopId, List<String> days) async =>
      (await _byDays(sales, shopId, days)).map(Sale.fromDoc).toList();

  static Future<List<StockMove>> movesOfDays(String shopId, List<String> days) async =>
      (await _byDays(moves, shopId, days)).map(StockMove.fromDoc).toList();

  static Future<List<CashSession>> sessionsOfDays(String shopId, List<String> days) async =>
      (await _byDays(sessions, shopId, days)).map(CashSession.fromDoc).toList();

  static Future<List<Payment>> paymentsOfDays(String shopId, List<String> days) async =>
      (await _byDays(payments, shopId, days)).map(Payment.fromDoc).toList();

  static Future<List<Map<String, dynamic>>> logsOfDays(String shopId, List<String> days) async =>
      (await _byDays(logs, shopId, days)).map((d) => d.data()).toList()
        ..sort((a, b) => ((b['localAt'] as num?) ?? 0).compareTo((a['localAt'] as num?) ?? 0));
}
