import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/chat.dart';
import '../models/inbox_item.dart';
import '../models/order.dart';
import '../models/shop.dart';
import '../models/shop_settings.dart';
import '../models/staff.dart';
import '../services/db.dart';
import '../services/notify_service.dart';
import '../services/session.dart';
import 'admin/admin_screen.dart';
import 'catalog_screen.dart';
import 'conversations_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'shop_picker_screen.dart';

/// Onglets : Accueil | Commandes | Discussion | Profil (+ Gestion pour l'équipe).
class HomeScreen extends StatefulWidget {
  final String uid;
  const HomeScreen({super.key, required this.uid});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  late final Stream<AppUser?> _user = Db.userStream(widget.uid);
  late final Stream<bool> _admin = Db.isAdmin(widget.uid);
  late final Stream<StaffMember?> _staff = Db.staffStream(widget.uid);
  late final Stream<List<Shop>> _shops = Db.allShops();
  late final Stream<ShopSettings> _settings = Db.settings();
  late final Stream<List<Conversation>> _convs =
      Db.clientConversations(widget.uid);
  late final Stream<List<InboxItem>> _inbox = Db.clientInbox(widget.uid);

  void _goTo(int i) {
    setState(() => _index = i);
    if (i == 1) Db.markSeen(widget.uid, 'ordersSeenAt');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _admin,
      builder: (context, adminSnap) => StreamBuilder<StaffMember?>(
        stream: _staff,
        builder: (context, staffSnap) => StreamBuilder<List<Shop>>(
          stream: _shops,
          builder: (context, shopsSnap) => StreamBuilder<ShopSettings>(
            stream: _settings,
            builder: (context, setSnap) => StreamBuilder<AppUser?>(
              stream: _user,
              builder: (context, userSnap) {
                final session = Session(
                  uid: widget.uid,
                  user: userSnap.data,
                  isSuper: adminSnap.data ?? false,
                  staff: staffSnap.data,
                  shops: (shopsSnap.data ?? const <Shop>[])
                      .where((s) => s.active)
                      .toList(),
                  settings: setSnap.data ?? const ShopSettings(),
                );
                final ready = userSnap.hasData && shopsSnap.hasData;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  context.read<SessionNotifier>().set(session);
                  if (ready) PushService.sync(session);
                });
                return ready && session.needsShopChoice && !session.canManage
                    ? const ShopPickerScreen(firstTime: true)
                    : _tabs(session);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs(Session session) {
    final pages = <Widget>[
      CatalogScreen(onOpenChat: () => _goTo(2)),
      OrdersScreen(uid: widget.uid, user: session.user),
      ConversationsScreen(uid: widget.uid, user: session.user),
      ProfileScreen(onGoTo: _goTo),
      if (session.canManage) const AdminScreen(),
    ];
    final index = _index < pages.length ? _index : 0;
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, cs) => StreamBuilder<List<InboxItem>>(
        stream: _inbox,
        builder: (context, ib) {
          final unread = (cs.data ?? const <Conversation>[])
              .fold<int>(0, (s, c) => s + c.unreadForClient);
          final seen = session.user?.ordersSeenAt;
          final orderNews = index == 1
              ? 0
              : (ib.data ?? const <InboxItem>[])
                  .where((n) => n.type == 'order' && n.isNewerThan(seen))
                  .length;
          return NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _goTo,
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Accueil'),
              NavigationDestination(
                  icon: Badge(
                    isLabelVisible: orderNews > 0,
                    label: Text('$orderNews'),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                  selectedIcon: const Icon(Icons.receipt_long_rounded),
                  label: 'Commandes'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                selectedIcon: const Icon(Icons.chat_bubble_rounded),
                label: 'Discussion',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profil'),
              if (session.canManage)
                NavigationDestination(
                    icon: _StaffBadge(shopId: session.managedShopId,
                        child: const Icon(Icons.storefront_outlined)),
                    selectedIcon: _StaffBadge(shopId: session.managedShopId,
                        child: const Icon(Icons.storefront_rounded)),
                    label: 'Gestion'),
            ],
          );
        },
      ),
      ),
    );
  }
}

/// Pastille de l'onglet Gestion : nouvelles commandes + messages non lus.
class _StaffBadge extends StatefulWidget {
  final String? shopId;
  final Widget child;
  const _StaffBadge({required this.shopId, required this.child});

  @override
  State<_StaffBadge> createState() => _StaffBadgeState();
}

class _StaffBadgeState extends State<_StaffBadge> {
  late Stream<List<ShopOrder>> _orders = Db.allOrders(shopId: widget.shopId);
  late Stream<List<Conversation>> _convs =
      Db.allConversations(shopId: widget.shopId);

  @override
  void didUpdateWidget(covariant _StaffBadge old) {
    super.didUpdateWidget(old);
    if (old.shopId != widget.shopId) {
      _orders = Db.allOrders(shopId: widget.shopId);
      _convs = Db.allConversations(shopId: widget.shopId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopOrder>>(
      stream: _orders,
      builder: (context, os) => StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, cs) {
          final n = (os.data ?? const <ShopOrder>[])
                  .where((o) => o.status == 'nouvelle')
                  .length +
              (cs.data ?? const <Conversation>[])
                  .fold<int>(0, (a, c) => a + c.unreadForShop);
          return Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            backgroundColor: const Color(0xFFD32F2F),
            child: widget.child,
          );
        },
      ),
    );
  }
}
