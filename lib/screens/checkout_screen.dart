import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/order.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../services/session.dart';
import '../state/cart.dart';
import '../utils.dart';
import 'order_detail_screen.dart';

/// Commande : coordonnées, retrait ou livraison, récapitulatif, confirmation.
class CheckoutScreen extends StatefulWidget {
  final AppUser? user;
  const CheckoutScreen({super.key, required this.user});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.name ?? '');
  late final _phone = TextEditingController(text: widget.user?.phone ?? '');
  final _city = TextEditingController(text: 'Bamako');
  final _address = TextEditingController();
  final _info = TextEditingController();
  String _delivery = 'retrait';
  final String _method = 'especes';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _city, _address, _info]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  Future<void> _confirm(Shop shop) async {
    if (!_form.currentState!.validate()) return;
    final cart = context.read<Cart>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final fee = _delivery == 'livraison' ? shop.deliveryFee : 0;
    final order = ShopOrder(
      shopId: shop.id,
      buyerId: AuthService.current!.uid,
      buyerName: _name.text.trim(),
      phone: _phone.text.trim(),
      delivery: _delivery,
      city: _delivery == 'livraison' ? _city.text.trim() : '',
      address: _delivery == 'livraison' ? _address.text.trim() : '',
      deliveryInfo: _delivery == 'livraison' ? _info.text.trim() : '',
      items: cart.lines
          .map((l) => OrderItem(
                itemId: l.item.id,
                type: l.item.type,
                name: l.item.name,
                price: l.item.price,
                unit: l.item.unit,
                qty: l.qty,
                note: l.note,
              ))
          .toList(),
      subtotal: cart.subtotal,
      deliveryFee: fee,
      total: cart.subtotal + fee,
      quoteNeeded: cart.needsQuote,
      paymentMethod: _method,
    );

    setState(() => _busy = true);
    try {
      final id = await Db.createOrder(order,
          bookings: cart.bookings, shopCode: shop.code);
      cart.clear();
      navigator.popUntil((r) => r.isFirst);
      navigator.push(MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: id, justCreated: true)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final shop = sessionOf(context).myShop;
    return Builder(
      builder: (context) {
        final s = shop;
        final fee = _delivery == 'livraison' ? s.deliveryFee : 0;
        final total = cart.subtotal + fee;
        return Scaffold(
          appBar: AppBar(title: const Text('Ma commande')),
          body: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('Vos coordonnées', [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'Nom complet',
                        prefixIcon: Icon(Icons.person_outline)),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Téléphone',
                        prefixIcon: Icon(Icons.phone_outlined)),
                    validator: _required,
                  ),
                ]),
                _section('Réception', [
                  _choice('retrait', Icons.storefront_rounded,
                      'Retrait en boutique', 'Gratuit'),
                  const SizedBox(height: 8),
                  _choice('livraison', Icons.delivery_dining_rounded,
                      'Livraison', fcfa(s.deliveryFee)),
                  const SizedBox(height: 12),
                  if (_delivery == 'retrait')
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConfig.paleGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.id == 'main' ? AppConfig.shopName : s.name,
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (s.address.isNotEmpty) Text('📍 ${s.address}'),
                          if (s.hours.isNotEmpty) Text('🕒 ${s.hours}'),
                          if (s.address.isEmpty)
                            const Text(
                                'Nous vous appellerons quand votre commande sera prête.'),
                        ],
                      ),
                    )
                  else ...[
                    TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'Ville'),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(
                          labelText: 'Adresse / quartier'),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _info,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Informations complémentaires',
                          hintText: 'Repère, porte, heure préférée…'),
                    ),
                  ],
                ]),
                _section('Récapitulatif', [
                  for (final l in cart.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Expanded(child: Text('${l.qty} × ${l.item.name}')),
                        Text(l.item.onQuote ? 'Sur devis' : fcfa(l.subtotal),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  const Divider(height: 20),
                  _line('Sous-total', fcfa(cart.subtotal)),
                  _line('Livraison', _delivery == 'livraison' ? fcfa(fee) : 'Gratuit'),
                  const SizedBox(height: 4),
                  _line(cart.needsQuote ? 'Total (hors devis)' : 'Total', fcfa(total),
                      bold: true),
                  const SizedBox(height: 8),
                  _line('Paiement', 'Espèces (livraison ou retrait)'),
                  if (cart.needsQuote)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Le prix final des services sur devis vous sera envoyé dans l\'application.',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                ]),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _busy || cart.isEmpty ? null : () => _confirm(shop),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Confirmer ma commande'),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _choice(String value, IconData icon, String title, String trailing) {
    final selected = _delivery == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _delivery = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppConfig.paleGreen : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppConfig.green : const Color(0xFFDDE3DA),
              width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: AppConfig.green),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(trailing, style: const TextStyle(color: Colors.black54)),
          const SizedBox(width: 8),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppConfig.green : Colors.black38),
        ]),
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: bold ? 17 : 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 18 : 14,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? AppConfig.green : null)),
        ]),
      );
}
