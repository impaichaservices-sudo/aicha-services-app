import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _d(Object? v) => v is Timestamp ? v.toDate() : null;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Moyens de paiement de la caisse.
const payMethods = {
  'especes': 'Espèces',
  'orange': 'Orange Money',
  'moov': 'Moov Money',
  'wave': 'Wave',
  'autre': 'Autre',
  'credit': 'Crédit',
};

/// Types de mouvements de stock (+ entre, − sort).
const moveTypes = {
  'entree': 'Entrée',
  'sortie': 'Sortie',
  'vente': 'Vente',
  'retour': 'Retour',
  'correction_plus': 'Correction +',
  'correction_moins': 'Correction −',
  'inventaire': 'Inventaire',
};

const productUnits = [
  'pièce', 'unité', 'paquet', 'carton', 'mètre', 'kilogramme', 'litre', 'prestation',
];

/// Jour de travail : « 2026-11-25 ».
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dayLabel(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
}

/// Produit en stock (liste interne, séparée du catalogue des clients).
class Product {
  final String id;
  final String shopId;
  final String name;
  final String ref;
  final String category;
  final String description;
  final String unit;
  final int buyPrice;
  final int sellPrice;
  final int stock;
  final int minStock;
  final String location;
  final String supplier;
  final String barcode;
  final bool active;
  final bool trackStock; // false pour une prestation

  const Product({
    required this.id,
    required this.shopId,
    required this.name,
    this.ref = '',
    this.category = '',
    this.description = '',
    this.unit = 'pièce',
    this.buyPrice = 0,
    this.sellPrice = 0,
    this.stock = 0,
    this.minStock = 0,
    this.location = '',
    this.supplier = '',
    this.barcode = '',
    this.active = true,
    this.trackStock = true,
  });

  bool get lowStock => trackStock && active && stock <= minStock;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Product(
      id: d.id,
      shopId: (m['shopId'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      ref: (m['ref'] ?? '') as String,
      category: (m['category'] ?? '') as String,
      description: (m['description'] ?? '') as String,
      unit: (m['unit'] ?? 'pièce') as String,
      buyPrice: _i(m['buyPrice']),
      sellPrice: _i(m['sellPrice']),
      stock: _i(m['stock']),
      minStock: _i(m['minStock']),
      location: (m['location'] ?? '') as String,
      supplier: (m['supplier'] ?? '') as String,
      barcode: (m['barcode'] ?? '') as String,
      active: m['active'] != false,
      trackStock: m['trackStock'] != false,
    );
  }

  /// Champs modifiables (le stock ne change QUE par des mouvements).
  Map<String, dynamic> editableFields() => {
        'name': name,
        'ref': ref,
        'category': category,
        'description': description,
        'unit': unit,
        'buyPrice': buyPrice,
        'sellPrice': sellPrice,
        'minStock': minStock,
        'location': location,
        'supplier': supplier,
        'barcode': barcode,
        'active': active,
        'trackStock': trackStock,
      };
}

class StockMove {
  final String id;
  final String productId;
  final String productName;
  final int qty; // + entrée, − sortie
  final String type;
  final String userName;
  final String reason;
  final String refNumber;
  final DateTime at;
  final bool pending;

  const StockMove({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.type,
    required this.userName,
    required this.reason,
    required this.refNumber,
    required this.at,
    required this.pending,
  });

  factory StockMove.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return StockMove(
      id: d.id,
      productId: (m['productId'] ?? '') as String,
      productName: (m['productName'] ?? '') as String,
      qty: _i(m['qty']),
      type: (m['type'] ?? '') as String,
      userName: (m['userName'] ?? '') as String,
      reason: (m['reason'] ?? '') as String,
      refNumber: (m['refNumber'] ?? '') as String,
      at: _d(m['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(_i(m['localAt'])),
      pending: d.metadata.hasPendingWrites,
    );
  }
}

/// Ligne d'une vente.
class SaleLine {
  final String productId;
  final String name;
  final String unit;
  final int price;
  int qty;
  final bool trackStock;

  SaleLine({
    required this.productId,
    required this.name,
    required this.unit,
    required this.price,
    required this.qty,
    required this.trackStock,
  });

  int get total => price * qty;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'unit': unit,
        'price': price,
        'qty': qty,
        'total': total,
        'trackStock': trackStock,
      };

  factory SaleLine.fromMap(Map m) => SaleLine(
        productId: (m['productId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        unit: (m['unit'] ?? '') as String,
        price: _i(m['price']),
        qty: _i(m['qty']),
        trackStock: m['trackStock'] != false,
      );
}

class Sale {
  final String id;
  final String shopId;
  final String number;
  final String sessionId;
  final String day;
  final String agentId;
  final String agentName;
  final String customerName;
  final String customerPhone;
  final List<SaleLine> lines;
  final int subtotal;
  final int discount;
  final int total;
  final int paid;
  final int due;
  final String payMethod;
  final String status; // validee | annulee
  final String cancelReason;
  final DateTime at;
  final bool pending;

  const Sale({
    required this.id,
    required this.shopId,
    required this.number,
    required this.sessionId,
    required this.day,
    required this.agentId,
    required this.agentName,
    required this.customerName,
    required this.customerPhone,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paid,
    required this.due,
    required this.payMethod,
    required this.status,
    required this.cancelReason,
    required this.at,
    required this.pending,
  });

  bool get cancelled => status == 'annulee';

  factory Sale.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Sale(
      id: d.id,
      shopId: (m['shopId'] ?? '') as String,
      number: (m['number'] ?? '') as String,
      sessionId: (m['sessionId'] ?? '') as String,
      day: (m['day'] ?? '') as String,
      agentId: (m['agentId'] ?? '') as String,
      agentName: (m['agentName'] ?? '') as String,
      customerName: (m['customerName'] ?? '') as String,
      customerPhone: (m['customerPhone'] ?? '') as String,
      lines: [for (final l in (m['lines'] as List? ?? const [])) SaleLine.fromMap(l as Map)],
      subtotal: _i(m['subtotal']),
      discount: _i(m['discount']),
      total: _i(m['total']),
      paid: _i(m['paid']),
      due: _i(m['due']),
      payMethod: (m['payMethod'] ?? 'especes') as String,
      status: (m['status'] ?? 'validee') as String,
      cancelReason: (m['cancelReason'] ?? '') as String,
      at: _d(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(_i(m['localAt'])),
      pending: d.metadata.hasPendingWrites,
    );
  }
}

/// Journée de caisse d'un vendeur (ouverture → clôture).
class CashSession {
  final String id;
  final String shopId;
  final String agentId;
  final String agentName;
  final String day;
  final int openingFloat;
  final String status; // ouverte | cloturee
  final Map<String, int> totals;
  final int salesCount;
  final int cashOut;
  final int expectedCash;
  final int countedCash;
  final int gap;
  final String closedByName;
  final DateTime? closedAt;
  final bool pending;

  const CashSession({
    required this.id,
    required this.shopId,
    required this.agentId,
    required this.agentName,
    required this.day,
    required this.openingFloat,
    required this.status,
    required this.totals,
    required this.salesCount,
    required this.cashOut,
    required this.expectedCash,
    required this.countedCash,
    required this.gap,
    required this.closedByName,
    required this.closedAt,
    required this.pending,
  });

  bool get closed => status == 'cloturee';

  factory CashSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final t = <String, int>{};
    (m['totals'] as Map? ?? const {}).forEach((k, v) => t['$k'] = _i(v));
    return CashSession(
      id: d.id,
      shopId: (m['shopId'] ?? '') as String,
      agentId: (m['agentId'] ?? '') as String,
      agentName: (m['agentName'] ?? '') as String,
      day: (m['day'] ?? '') as String,
      openingFloat: _i(m['openingFloat']),
      status: (m['status'] ?? 'ouverte') as String,
      totals: t,
      salesCount: _i(m['salesCount']),
      cashOut: _i(m['cashOut']),
      expectedCash: _i(m['expectedCash']),
      countedCash: _i(m['countedCash']),
      gap: _i(m['gap']),
      closedByName: (m['closedByName'] ?? '') as String,
      closedAt: _d(m['closedAt']),
      pending: d.metadata.hasPendingWrites,
    );
  }
}

class CashOut {
  final String id;
  final int amount;
  final String reason;
  final String userName;
  final DateTime at;
  const CashOut(this.id, this.amount, this.reason, this.userName, this.at);

  factory CashOut.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return CashOut(d.id, _i(m['amount']), (m['reason'] ?? '') as String,
        (m['userName'] ?? '') as String,
        _d(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(_i(m['localAt'])));
  }
}

/// Récapitulatif calculé d'une journée (avant clôture).
class DaySummary {
  int count = 0;
  int total = 0;
  int discount = 0;
  int credit = 0;
  int cancelled = 0;
  int creditPaid = 0; // crédits remboursés pendant la journée
  final byMethod = <String, int>{for (final k in payMethods.keys) k: 0};

  /// Encaissé = ventes payées + crédits remboursés.
  int get collected => total - credit + creditPaid;

  /// Ajoute les paiements de crédits / factures reçus pendant la journée.
  DaySummary addPayments(Iterable<Payment> list) {
    for (final p in list) {
      creditPaid += p.amount;
      byMethod[p.method] = (byMethod[p.method] ?? 0) + p.amount;
    }
    return this;
  }

  static DaySummary of(Iterable<Sale> sales) {
    final s = DaySummary();
    for (final v in sales) {
      if (v.cancelled) {
        s.cancelled++;
        continue;
      }
      s.count++;
      s.total += v.total;
      s.discount += v.discount;
      s.credit += v.due;
      // Une vente à crédit partiellement payée : la part payée compte en espèces.
      if (v.payMethod == 'credit') {
        s.byMethod['credit'] = (s.byMethod['credit'] ?? 0) + v.due;
        s.byMethod['especes'] = (s.byMethod['especes'] ?? 0) + v.paid;
      } else {
        s.byMethod[v.payMethod] = (s.byMethod[v.payMethod] ?? 0) + v.total;
      }
    }
    return s;
  }
}

// ======================= ÉTAPE 2 =======================

/// Identifiant client sans doublon : boutique + numéro de téléphone.
String customerIdFor(String shopId, String phone) {
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 8) d = '223$d';
  return d.isEmpty ? '' : '${shopId}_$d';
}

class Customer {
  final String id;
  final String shopId;
  final String name;
  final String phone;
  final String address;
  final String city;
  final String company;
  final String email;
  final String notes;

  const Customer({
    required this.id,
    required this.shopId,
    required this.name,
    required this.phone,
    this.address = '',
    this.city = '',
    this.company = '',
    this.email = '',
    this.notes = '',
  });

  factory Customer.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Customer.fromMap(d.id, m);
  }

  factory Customer.fromMap(String id, Map m) => Customer(
        id: id,
        shopId: (m['shopId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        company: (m['company'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'shopId': shopId,
        'name': name,
        'phone': phone,
        'address': address,
        'city': city,
        'company': company,
        'email': email,
        'notes': notes,
      };
}

/// Paiement reçu d'un client (vente à crédit ou facture). Jamais modifié.
class Payment {
  final String id;
  final String customerId;
  final String targetType; // sale | invoice
  final String targetId;
  final String targetNumber;
  final int amount;
  final String method;
  final String userName;
  final DateTime at;
  final bool pending;

  const Payment({
    required this.id,
    required this.customerId,
    required this.targetType,
    required this.targetId,
    required this.targetNumber,
    required this.amount,
    required this.method,
    required this.userName,
    required this.at,
    required this.pending,
  });

  factory Payment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Payment(
      id: d.id,
      customerId: (m['customerId'] ?? '') as String,
      targetType: (m['targetType'] ?? '') as String,
      targetId: (m['targetId'] ?? '') as String,
      targetNumber: (m['targetNumber'] ?? '') as String,
      amount: _i(m['amount']),
      method: (m['method'] ?? 'especes') as String,
      userName: (m['userName'] ?? '') as String,
      at: _d(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(_i(m['localAt'])),
      pending: d.metadata.hasPendingWrites,
    );
  }
}

const quoteStatus = {
  'brouillon': 'Brouillon',
  'envoye': 'Envoyé',
  'accepte': 'Accepté',
  'refuse': 'Refusé',
  'expire': 'Expiré',
  'converti': 'Converti en facture',
  'annule': 'Annulé',
};

const invoiceStatus = {
  'brouillon': 'Brouillon',
  'validee': 'Validée',
  'partielle': 'Payée partiellement',
  'payee': 'Payée',
  'impayee': 'Impayée',
  'annulee': 'Annulée',
};

class DocLine {
  String ref;
  String name;
  int qty;
  String unit;
  int price;
  int discount; // remise en FCFA sur la ligne
  String productId;

  DocLine({
    this.ref = '',
    required this.name,
    this.qty = 1,
    this.unit = 'unité',
    this.price = 0,
    this.discount = 0,
    this.productId = '',
  });

  int get total => price * qty - discount;

  Map<String, dynamic> toMap() => {
        'ref': ref,
        'name': name,
        'qty': qty,
        'unit': unit,
        'price': price,
        'discount': discount,
        'total': total,
        'productId': productId,
      };

  factory DocLine.fromMap(Map m) => DocLine(
        ref: (m['ref'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        qty: _i(m['qty']),
        unit: (m['unit'] ?? '') as String,
        price: _i(m['price']),
        discount: _i(m['discount']),
        productId: (m['productId'] ?? '') as String,
      );

  DocLine copy() => DocLine(
      ref: ref, name: name, qty: qty, unit: unit, price: price, discount: discount,
      productId: productId);
}

/// Devis ou facture.
class BizDoc {
  final String id;
  final String kind; // quote | invoice
  final String shopId;
  final String number;
  final String status;
  final Customer customer;
  final List<DocLine> lines;
  final int subtotal;
  final int discount;
  final int taxRate; // en %, 0 = pas de taxe
  final int tax;
  final int total;
  final String dueDate; // yyyy-MM-dd (facture) / validité (devis)
  final String fromQuote; // numéro du devis d'origine
  final String fromQuoteId;
  final String replaces; // facture annulée remplacée
  final String notes;
  final String createdByName;
  final DateTime at;
  final Map<String, dynamic> signature; // png (base64), byName, at
  final String cancelReason;
  final bool pending;

  const BizDoc({
    required this.id,
    required this.kind,
    required this.shopId,
    required this.number,
    required this.status,
    required this.customer,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.taxRate,
    required this.tax,
    required this.total,
    required this.dueDate,
    required this.fromQuote,
    required this.fromQuoteId,
    required this.replaces,
    required this.notes,
    required this.createdByName,
    required this.at,
    required this.signature,
    required this.cancelReason,
    required this.pending,
  });

  bool get isInvoice => kind == 'invoice';
  bool get isDraft => status == 'brouillon';
  bool get signed => (signature['png'] ?? '').toString().isNotEmpty;
  String get title => isInvoice ? 'Facture' : 'Devis';

  /// Statut affiché (une facture validée devient payée / partielle / impayée).
  String displayStatus(int paid) {
    if (!isInvoice) return quoteStatus[status] ?? status;
    if (status != 'validee') return invoiceStatus[status] ?? status;
    if (paid >= total) return invoiceStatus['payee']!;
    if (paid > 0) return invoiceStatus['partielle']!;
    if (dueDate.isNotEmpty && dueDate.compareTo(dayKey(DateTime.now())) < 0) {
      return invoiceStatus['impayee']!;
    }
    return invoiceStatus['validee']!;
  }

  factory BizDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> d, String kind) {
    final m = d.data() ?? const <String, dynamic>{};
    return BizDoc(
      id: d.id,
      kind: kind,
      shopId: (m['shopId'] ?? '') as String,
      number: (m['number'] ?? '') as String,
      status: (m['status'] ?? 'brouillon') as String,
      customer: Customer.fromMap(
          (m['customerId'] ?? '') as String, (m['customer'] as Map?) ?? const {}),
      lines: [for (final l in (m['lines'] as List? ?? const [])) DocLine.fromMap(l as Map)],
      subtotal: _i(m['subtotal']),
      discount: _i(m['discount']),
      taxRate: _i(m['taxRate']),
      tax: _i(m['tax']),
      total: _i(m['total']),
      dueDate: (m['dueDate'] ?? '') as String,
      fromQuote: (m['fromQuote'] ?? '') as String,
      fromQuoteId: (m['fromQuoteId'] ?? '') as String,
      replaces: (m['replaces'] ?? '') as String,
      notes: (m['notes'] ?? '') as String,
      createdByName: (m['createdByName'] ?? '') as String,
      at: _d(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(_i(m['localAt'])),
      signature: Map<String, dynamic>.from((m['signature'] as Map?) ?? const {}),
      cancelReason: (m['cancelReason'] ?? '') as String,
      pending: d.metadata.hasPendingWrites,
    );
  }
}

/// Calcul des totaux d'un devis / d'une facture.
class DocTotals {
  final int subtotal;
  final int discount;
  final int tax;
  final int total;
  const DocTotals(this.subtotal, this.discount, this.tax, this.total);

  static DocTotals of(List<DocLine> lines, int discount, int taxRate) {
    final sub = lines.fold<int>(0, (a, l) => a + l.total);
    final d = discount > sub ? sub : (discount < 0 ? 0 : discount);
    final base = sub - d;
    final tax = (base * taxRate / 100).round();
    return DocTotals(sub, d, tax, base + tax);
  }
}

// ======================= ÉTAPE 3 =======================

const docStyles = {
  'classique': 'Classique',
  'moderne': 'Moderne',
  'professionnel': 'Professionnel',
  'minimaliste': 'Minimaliste',
  'personnalise': 'Personnalisé',
};
const logoPositions = {'gauche': 'À gauche', 'droite': 'À droite', 'centre': 'Au centre', 'aucun': 'Sans logo'};
const tableStyles = {'grille': 'Grille', 'lignes': 'Lignes', 'zebre': 'Lignes alternées'};

/// Modèle des devis / factures et informations légales d'une boutique.
class DocSettings {
  final String style;
  final int color; // 0xFFRRGGBB
  final String logoPos;
  final String tableStyle;
  final String header;
  final String footer;
  final String conditions; // texte proposé par défaut
  final String email;
  final String legal; // NIF, RCCM…
  final bool showSignature;

  const DocSettings({
    this.style = 'classique',
    this.color = 0xFF1E8B09,
    this.logoPos = 'gauche',
    this.tableStyle = 'grille',
    this.header = '',
    this.footer = '',
    this.conditions = '',
    this.email = '',
    this.legal = '',
    this.showSignature = true,
  });

  factory DocSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DocSettings();
    String pick(Object? v, Map<String, String> allowed, String d) =>
        allowed.containsKey(v) ? v as String : d;
    return DocSettings(
      style: pick(m['style'], docStyles, 'classique'),
      color: (m['color'] as num?)?.toInt() ?? 0xFF1E8B09,
      logoPos: pick(m['logoPos'], logoPositions, 'gauche'),
      tableStyle: pick(m['tableStyle'], tableStyles, 'grille'),
      header: (m['header'] ?? '') as String,
      footer: (m['footer'] ?? '') as String,
      conditions: (m['conditions'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      legal: (m['legal'] ?? '') as String,
      showSignature: m['showSignature'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'style': style,
        'color': color,
        'logoPos': logoPos,
        'tableStyle': tableStyle,
        'header': header,
        'footer': footer,
        'conditions': conditions,
        'email': email,
        'legal': legal,
        'showSignature': showSignature,
      };

  DocSettings copyWith({
    String? style,
    int? color,
    String? logoPos,
    String? tableStyle,
    String? header,
    String? footer,
    String? conditions,
    String? email,
    String? legal,
    bool? showSignature,
  }) =>
      DocSettings(
        style: style ?? this.style,
        color: color ?? this.color,
        logoPos: logoPos ?? this.logoPos,
        tableStyle: tableStyle ?? this.tableStyle,
        header: header ?? this.header,
        footer: footer ?? this.footer,
        conditions: conditions ?? this.conditions,
        email: email ?? this.email,
        legal: legal ?? this.legal,
        showSignature: showSignature ?? this.showSignature,
      );
}
