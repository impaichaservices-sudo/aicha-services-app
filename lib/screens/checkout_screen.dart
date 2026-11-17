import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/order.dart';
import '../models/shop_settings.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../services/payment_service.dart';
import '../state/cart.dart';
import '../utils.dart';

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
  late final Stream<ShopSettings> _settings = Db.settings();
  String _delivery = 'retrait';
  String _method = 'especes';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _city, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  Future<void> _confirm(ShopSettings settings) async {
    if (!_form.currentState!.validate()) return;
    final cart = context.read<Cart>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final fee = _delivery == 'livraison' ? settings.deliveryFee : 0;
    final order = ShopOrder(
      buyerId: AuthService.current!.uid,
      buyerName: _name.text.trim(),
      phone: _phone.text.trim(),
      delivery: _delivery,
      city: _delivery == 'livraison' ? _city.text.trim() : '',
      address: _delivery == 'livraison' ? _address.text.trim() : '',
      items: cart.lines
          .map((l) => OrderItem(
                itemId: l.item.id,
                type: l.item.type,
                name: l.item.name,
                price: l.item.price,
                unit: l.item.unit,
                qty: l.qty,
                fileUrl: l.fileUrl,
                fileName: l.fileName,
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
      final id = await Db.createOrder(order);
      cart.clear();
      if (order.isOnlinePayment && !order.quoteNeeded) {
        try {
          await PaymentService.pay(orderIds: [id], method: _method);
        } catch (e) {
          messenger.showSnackBar(SnackBar(
            content: Text('${PaymentService.message(e)}\n'
                'Vous pourrez payer depuis « Commandes ».'),
          ));
          navigator.pop();
          return;
        }
      }
      messenger.showSnackBar(SnackBar(
        content: Text(order.quoteNeeded
            ? 'Demande envoyée ! Nous vous enverrons le prix final.'
            : 'Commande envoyée ! Merci.'),
      ));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final t = Theme.of(context).textTheme;

    return StreamBuilder<ShopSettings>(
      stream: _settings,
      builder: (context, snap) {
        final settings = snap.data ?? const ShopSettings();
        final fee = _delivery == 'livraison' ? settings.deliveryFee : 0;
        final total = cart.subtotal + fee;

        return Scaffold(
          appBar: AppBar(title: const Text('Finaliser la commande')),
          body: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Vos coordonnées', style: t.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom complet'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                  validator: _required,
                ),
                const SizedBox(height: 24),
                Text('Réception', style: t.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'retrait',
                        icon: Icon(Icons.store),
                        label: Text('Retrait en boutique')),
                    ButtonSegment(
                        value: 'livraison',
                        icon: Icon(Icons.delivery_dining),
                        label: Text('Livraison')),
                  ],
                  selected: {_delivery},
                  onSelectionChanged: (s) => setState(() => _delivery = s.first),
                ),
                const SizedBox(height: 12),
                if (_delivery == 'retrait')
                  Text(settings.address.isEmpty
                      ? 'Nous vous appellerons quand votre commande sera prête.'
                      : '📍 ${settings.address}'
                          '${settings.hours.isEmpty ? '' : '\n🕒 ${settings.hours}'}')
                else ...[
                  TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'Ville'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Adresse / quartier / repère',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 8),
                  Text('Frais de livraison : ${fcfa(settings.deliveryFee)}'),
                ],
                const SizedBox(height: 24),
                Text('Paiement', style: t.titleMedium),
                for (final m in paymentMethodLabels.entries)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: m.key,
                    groupValue: _method,
                    title: Text(m.value),
                    onChanged: (v) => setState(() => _method = v!),
                  ),
                if (cart.needsQuote && _method != 'especes')
                  Text(
                    'Votre commande contient des articles sur devis : vous '
                    'pourrez payer dans « Commandes » dès que le prix final '
                    'sera fixé.',
                    style: t.bodySmall,
                  ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed:
                    _busy || cart.isEmpty ? null : () => _confirm(settings),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(cart.needsQuote
                          ? 'Envoyer ma demande'
                          : 'Confirmer • ${fcfa(total)}'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
