import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/staff.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../services/notify_service.dart';
import '../services/session.dart';
import '../utils.dart';
import 'my_files_screen.dart';
import 'orders_screen.dart';
import 'shop_picker_screen.dart';

/// Profil : mes infos, raccourcis, notifications, contact, à propos.
class ProfileScreen extends StatelessWidget {
  final void Function(int tab) onGoTo;
  const ProfileScreen({super.key, required this.onGoTo});

  Future<void> _editName(BuildContext context, AppUser? u) async {
    if (u == null) return;
    final ctrl = TextEditingController(text: u.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mon nom'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await Db.updateProfile(u.uid, {'name': name});
    }
  }

  void _about(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset(AppConfig.logo, height: 110),
          const SizedBox(height: 8),
          const Text(AppConfig.slogan,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AppConfig.green, fontSize: 16)),
          const SizedBox(height: 12),
          const Text(AppConfig.about, textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, String uid) async {
    final notifier = context.read<SessionNotifier>();
    await PushService.signOut(uid);
    notifier.clear();
    await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionOf(context);
    final u = session.user;
    final isAdmin = session.canManage;
    final roleLabel = session.isSuper
        ? 'Super Admin'
        : session.isStaff
            ? '${staffRoleLabels[session.staff!.role] ?? ''} • ${session.shopById(session.staff!.shopId).name}'
            : null;
    final shop = session.myShop;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppConfig.green,
                  child: Text(
                    (u?.name.isNotEmpty ?? false) ? u!.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u?.name ?? '…',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(u?.phone ?? '',
                          style: const TextStyle(color: Colors.black54)),
                      if (roleLabel != null)
                        Text(roleLabel,
                            style: const TextStyle(
                                color: AppConfig.green,
                                fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier mon nom',
                  onPressed: () => _editName(context, u),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _group([
            _tile(Icons.receipt_long_rounded, 'Mes commandes', () => onGoTo(1)),
            _tile(Icons.request_quote_rounded, 'Mes devis', () {
              if (u == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OrdersScreen(
                    uid: u.uid, user: u, initialFilter: 'devis', standalone: true),
              ));
            }),
            _tile(Icons.folder_rounded, 'Mes fichiers', () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MyFilesScreen(uid: session.uid)));
            }),
            _tile(Icons.chat_bubble_rounded, 'Mes discussions', () => onGoTo(2)),
            if (session.shops.isNotEmpty)
              _tile(
                  Icons.storefront_rounded,
                  'Ma boutique : ${session.clientShopId.isEmpty ? 'à choisir' : shop.name}',
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ShopPickerScreen()))),
            _tile(Icons.notifications_rounded, 'Notifications', () {
              if (u == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NotificationSettingsScreen(user: u)));
            }),
          ]),
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final s = shop;
              return _group([
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text('Nous contacter',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (s.address.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.place_rounded, color: AppConfig.green),
                    title: Text(s.address),
                    subtitle: s.hours.isEmpty ? null : Text(s.hours),
                  ),
                if (s.phone.isNotEmpty)
                  _tile(Icons.call_rounded, 'Appeler : ${s.phone}',
                      () => launchUrl(Uri.parse('tel:${s.phone}'))),
                if (s.whatsapp.isNotEmpty)
                  _tile(Icons.chat_rounded, 'WhatsApp : ${s.whatsapp}',
                      () => launchUrl(whatsappUri(s.whatsapp),
                          mode: LaunchMode.externalApplication)),
                _tile(Icons.info_outline_rounded, 'À propos d\'${AppConfig.shortName}',
                    () => _about(context)),
              ]);
            },
          ),
          const SizedBox(height: 16),
          _group([
            if (isAdmin)
              _tile(Icons.storefront_rounded, 'Espace Gestion', () => onGoTo(4)),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Color(0xFFC62828)),
              title: const Text('Se déconnecter',
                  style: TextStyle(color: Color(0xFFC62828))),
              onTap: () => _signOut(context, session.uid),
            ),
          ]),
          const SizedBox(height: 24),
          const Center(
            child: Text(AppConfig.slogan,
                style: TextStyle(color: Colors.black45, fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _group(List<Widget> children) => Card(
        child: Column(children: children),
      );

  Widget _tile(IconData icon, String title, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: AppConfig.green),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

/// Profil → Notifications : Commandes / Messages / Nouveautés et promotions.
class NotificationSettingsScreen extends StatefulWidget {
  final AppUser user;
  const NotificationSettingsScreen({super.key, required this.user});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late NotifPrefs _p = widget.user.notif;

  Future<void> _save(NotifPrefs p) async {
    setState(() => _p = p);
    await Db.updateProfile(widget.user.uid, {'notif': p.toMap()});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.receipt_long, color: AppConfig.green),
                title: const Text('Commandes'),
                subtitle: const Text('Confirmation, commande prête, livraison…'),
                value: _p.orders,
                onChanged: (v) => _save(NotifPrefs(
                    orders: v, messages: _p.messages, promos: _p.promos)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.chat_bubble, color: AppConfig.green),
                title: const Text('Messages'),
                subtitle: const Text('Réponses de notre équipe'),
                value: _p.messages,
                onChanged: (v) => _save(NotifPrefs(
                    orders: _p.orders, messages: v, promos: _p.promos)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.local_offer, color: AppConfig.green),
                title: const Text('Nouveautés et promotions'),
                subtitle: const Text('Nouveaux services, formations, offres'),
                value: _p.promos,
                onChanged: (v) => _save(NotifPrefs(
                    orders: _p.orders, messages: _p.messages, promos: v)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Text(
            'Les informations importantes concernant une commande en cours restent toujours visibles dans « Commandes » et « Discussion ».',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
