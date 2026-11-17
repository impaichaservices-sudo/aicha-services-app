import 'package:cloud_firestore/cloud_firestore.dart';

const orderStatusLabels = {
  'nouvelle': 'Nouvelle',
  'confirmee': 'Confirmée',
  'en_cours': 'En cours',
  'prete': 'Prête',
  'livree': 'Livrée / retirée',
  'annulee': 'Annulée',
};

const paymentMethodLabels = {
  'especes': 'Espèces (à la livraison ou au retrait)',
  'orange': 'Orange Money',
  'moov': 'Moov Money',
  'carte': 'Carte bancaire',
};

const paymentStatusLabels = {
  'en_attente': 'Paiement en attente',
  'paye': 'Payé',
  'echec': 'Paiement échoué',
};

class OrderItem {
  final String itemId;
  final String type;
  final String name;
  final int price;
  final String unit;
  final int qty;
  final String fileUrl;
  final String fileName;
  final String note;

  const OrderItem({
    required this.itemId,
    required this.type,
    required this.name,
    required this.price,
    required this.unit,
    required this.qty,
    this.fileUrl = '',
    this.fileName = '',
    this.note = '',
  });

  bool get onQuote => price <= 0;

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'type': type,
        'name': name,
        'price': price,
        'unit': unit,
        'qty': qty,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'note': note,
      };

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        itemId: (m['itemId'] ?? '') as String,
        type: (m['type'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        price: (m['price'] as num?)?.toInt() ?? 0,
        unit: (m['unit'] ?? '') as String,
        qty: (m['qty'] as num?)?.toInt() ?? 1,
        fileUrl: (m['fileUrl'] ?? '') as String,
        fileName: (m['fileName'] ?? '') as String,
        note: (m['note'] ?? '') as String,
      );
}

class ShopOrder {
  final String id;
  final String buyerId;
  final String buyerName;
  final String phone;
  final String delivery; // 'livraison' | 'retrait'
  final String city;
  final String address;
  final List<OrderItem> items;
  final int subtotal;
  final int deliveryFee;
  final int total;
  final bool quoteNeeded;
  final int? quotedTotal; // prix final fixé par le patron (devis)
  final String adminNote;
  final String paymentMethod;
  final String paymentStatus;
  final String status;
  final DateTime? createdAt;

  const ShopOrder({
    this.id = '',
    required this.buyerId,
    required this.buyerName,
    required this.phone,
    required this.delivery,
    required this.city,
    required this.address,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.quoteNeeded,
    this.quotedTotal,
    this.adminNote = '',
    required this.paymentMethod,
    this.paymentStatus = 'en_attente',
    this.status = 'nouvelle',
    this.createdAt,
  });

  bool get isOnlinePayment => paymentMethod != 'especes';
  bool get isDelivery => delivery == 'livraison';
  bool get isClosed => status == 'livree' || status == 'annulee';

  /// Montant à payer, ou null si le devis n'est pas encore prêt.
  int? get amountDue => quotedTotal ?? (quoteNeeded ? null : total);

  bool get canPay =>
      isOnlinePayment &&
      paymentStatus != 'paye' &&
      status != 'annulee' &&
      amountDue != null;

  String get shortId => id.length >= 6 ? id.substring(0, 6).toUpperCase() : id;

  Map<String, dynamic> toNewMap() => {
        'buyerId': buyerId,
        'buyerName': buyerName,
        'phone': phone,
        'delivery': delivery,
        'city': city,
        'address': address,
        'items': items.map((i) => i.toMap()).toList(),
        'subtotal': subtotal,
        'deliveryFee': deliveryFee,
        'total': total,
        'quoteNeeded': quoteNeeded,
        'adminNote': '',
        'paymentMethod': paymentMethod,
        'paymentStatus': 'en_attente',
        'status': 'nouvelle',
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory ShopOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final rawItems = (d['items'] as List?) ?? const [];
    return ShopOrder(
      id: doc.id,
      buyerId: (d['buyerId'] ?? '') as String,
      buyerName: (d['buyerName'] ?? '') as String,
      phone: (d['phone'] ?? '') as String,
      delivery: (d['delivery'] ?? 'retrait') as String,
      city: (d['city'] ?? '') as String,
      address: (d['address'] ?? '') as String,
      items: rawItems
          .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subtotal: (d['subtotal'] as num?)?.toInt() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toInt() ?? 0,
      total: (d['total'] as num?)?.toInt() ?? 0,
      quoteNeeded: (d['quoteNeeded'] ?? false) as bool,
      quotedTotal: (d['quotedTotal'] as num?)?.toInt(),
      adminNote: (d['adminNote'] ?? '') as String,
      paymentMethod: (d['paymentMethod'] ?? 'especes') as String,
      paymentStatus: (d['paymentStatus'] ?? 'en_attente') as String,
      status: (d['status'] ?? 'nouvelle') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
