import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/chat.dart';
import '../models/inbox_item.dart';
import '../models/order.dart';
import '../models/shop.dart';
import '../models/shop_settings.dart';
import '../models/staff.dart';
import '../services/badge_service.dart';
import '../services/call_service.dart';
import '../services/db.dart';
import '../services/offline_queue.dart';
import '../services/notify_service.dart';
import '../services/update_service.dart';
import '../services/session.dart';
import 'admin/admin_conversations_screen.dart';
import 'admin/admin_orders_screen.dart';
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
  bool _cleaned = false;

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
                  if (ready) UpdateService.checkOnStart();
                  if (ready) CallService.watch(session);
                  if (ready) OfflineQueue.start();
                  BadgeService.start();
                  if (ready && !_cleaned) {
                    _cleaned = true;
                    Db.cleanOldInbox(widget.uid);
                  }
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

  /// Espace équipe (agents, responsables, Super Admin) : interface à part.
  Widget _staffTabs(Session session) {
    final me = session.me;
    final shopId = session.managedShopId;
    final pages = <Widget>[
      const AdminScreen(),
      AdminConversationsScreen(me: me, shopId: shopId),
      AdminOrdersScreen(me: me, shopId: shopId),
      ProfileScreen(onGoTo: _goTo),
    ];
    final index = _index < pages.length ? _index : 0;
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: const Color(0xFF13261A),
          foregroundColor: Colors.white,
          titleTextStyle: const TextStyle(
              color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F4F1),
      ),
      child: Scaffold(
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const SyncBanner(),
          _StaffNav(
            index: index,
            onTap: (i) => setState(() => _index = i),
            shopId: shopId,
            agentUid: session.agentUid,
          ),
        ]),
      ),
    );
  }

  Widget _tabs(Session session) {
    if (session.canManage) return _staffTabs(session);
    final pages = <Widget>[
      CatalogScreen(onOpenChat: () => _goTo(2)),
      OrdersScreen(uid: widget.uid, user: session.user, onExplore: () => _goTo(0)),
      ConversationsScreen(uid: widget.uid, user: session.user),
      ProfileScreen(onGoTo: _goTo),
      if (session.canManage) const AdminScreen(),
    ];
    final index = _index < pages.length ? _index : 0;
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const SyncBanner(),
        StreamBuilder<List<Conversation>>(
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
          // Chiffre sur l'icône de l'application (quand elle est en arrière-plan)
          final inboxSeen = session.user?.inboxSeenAt;
          BadgeService.update(
            messages: unread,
            orders: (ib.data ?? const <InboxItem>[])
                .where((n) => n.type == 'order' && n.isNewerThan(seen))
                .length,
            other: (ib.data ?? const <InboxItem>[])
                .where((n) =>
                    n.type != 'order' && n.type != 'chat' && n.isNewerThan(inboxSeen))
                .length,
          );
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
                        agentUid: session.agentUid,
                        child: const Icon(Icons.storefront_outlined)),
                    selectedIcon: _StaffBadge(shopId: session.managedShopId,
                        agentUid: session.agentUid,
                        child: const Icon(Icons.storefront_rounded)),
                    label: 'Gestion'),
            ],
          );
        },
      ),
      ),
      ]),
    );
  }
}

/// Pastille de l'onglet Gestion : nouvelles commandes + messages non lus.
class _StaffBadge extends StatefulWidget {
  final String? shopId;
  final String? agentUid;
  final Widget child;
  const _StaffBadge(
      {required this.shopId, this.agentUid, required this.child});

  @override
  State<_StaffBadge> createState() => _StaffBadgeState();
}

class _StaffBadgeState extends State<_StaffBadge> {
  late Stream<List<ShopOrder>> _orders = Db.allOrders(shopId: widget.shopId);
  late Stream<List<Conversation>> _convs =
      Db.allConversations(shopId: widget.shopId, agentUid: widget.agentUid);

  @override
  void didUpdateWidget(covariant _StaffBadge old) {
    super.didUpdateWidget(old);
    if (old.shopId != widget.shopId || old.agentUid != widget.agentUid) {
      _orders = Db.allOrders(shopId: widget.shopId);
      _convs =
          Db.allConversations(shopId: widget.shopId, agentUid: widget.agentUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopOrder>>(
      stream: _orders,
      builder: (context, os) => StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, cs) {
          final newOrders = (os.data ?? const <ShopOrder>[])
              .where((o) => o.status == 'nouvelle')
              .length;
          final unreadShop = (cs.data ?? const <Conversation>[])
              .fold<int>(0, (a, c) => a + c.unreadForShop);
          final n = newOrders + unreadShop;
          BadgeService.update(staffMessages: unreadShop, staffOrders: newOrders);
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

/// Barre du bas de l'espace équipe (fond sombre, compteurs).
class _StaffNav extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;
  final String? shopId;
  final String? agentUid;
  const _StaffNav(
      {required this.index, required this.onTap, required this.shopId, this.agentUid});

  @override
  State<_StaffNav> createState() => _StaffNavState();
}

class _StaffNavState extends State<_StaffNav> {
  late Stream<List<ShopOrder>> _orders = Db.allOrders(shopId: widget.shopId);
  late Stream<List<Conversation>> _convs =
      Db.allConversations(shopId: widget.shopId, agentUid: widget.agentUid);

  @override
  void didUpdateWidget(covariant _StaffNav old) {
    super.didUpdateWidget(old);
    if (old.shopId != widget.shopId || old.agentUid != widget.agentUid) {
      _orders = Db.allOrders(shopId: widget.shopId);
      _convs =
          Db.allConversations(shopId: widget.shopId, agentUid: widget.agentUid);
    }
  }

  Widget _badge(int n, Widget child) => Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        backgroundColor: const Color(0xFFD32F2F),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopOrder>>(
      stream: _orders,
      builder: (context, os) => StreamBuilder<List<Conversation>>(
        stream: _convs,
        builder: (context, cs) {
          final newOrders = (os.data ?? const <ShopOrder>[])
              .where((o) => o.status == 'nouvelle')
              .length;
          final unread = (cs.data ?? const <Conversation>[])
              .fold<int>(0, (a, c) => a + c.unreadForShop);
          BadgeService.update(staffMessages: unread, staffOrders: newOrders);
          const fg = Colors.white70;
          return NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: const Color(0xFF13261A),
              indicatorColor: const Color(0xFF1E8B09),
              iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
                  color: st.contains(WidgetState.selected) ? Colors.white : fg)),
              labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
                  color: st.contains(WidgetState.selected) ? Colors.white : fg,
                  fontWeight: st.contains(WidgetState.selected)
                      ? FontWeight.w800
                      : FontWeight.w500,
                  fontSize: 12.5)),
            ),
            child: NavigationBar(
              selectedIndex: widget.index,
              onDestinationSelected: widget.onTap,
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    selectedIcon: Icon(Icons.space_dashboard_rounded),
                    label: 'Tableau de bord'),
                NavigationDestination(
                    icon: _badge(unread, const Icon(Icons.forum_outlined)),
                    selectedIcon: _badge(unread, const Icon(Icons.forum_rounded)),
                    label: 'Discussions'),
                NavigationDestination(
                    icon: _badge(newOrders, const Icon(Icons.receipt_long_outlined)),
                    selectedIcon:
                        _badge(newOrders, const Icon(Icons.receipt_long_rounded)),
                    label: 'Commandes'),
                const NavigationDestination(
                    icon: Icon(Icons.badge_outlined),
                    selectedIcon: Icon(Icons.badge_rounded),
                    label: 'Mon compte'),
              ],
            ),
          );
        },
      ),
    );
  }
}
