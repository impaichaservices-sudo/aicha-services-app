import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/chat.dart';
import '../services/db.dart';
import 'admin/admin_screen.dart';
import 'catalog_screen.dart';
import 'conversations_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

/// Onglets : Accueil | Commandes | Discussion | Profil (+ Gestion pour l'admin).
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
  late final Stream<List<Conversation>> _convs =
      Db.clientConversations(widget.uid);

  void _goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _admin,
      builder: (context, adminSnap) {
        final isAdmin = adminSnap.data ?? false;
        return StreamBuilder<AppUser?>(
          stream: _user,
          builder: (context, snap) {
            final user = snap.data;
            final pages = <Widget>[
              CatalogScreen(user: user, onOpenChat: () => _goTo(2)),
              OrdersScreen(uid: widget.uid, user: user),
              ConversationsScreen(uid: widget.uid, user: user),
              ProfileScreen(user: user, isAdmin: isAdmin, onGoTo: _goTo),
              if (isAdmin) AdminScreen(uid: widget.uid, user: user),
            ];
            final index = _index < pages.length ? _index : 0;
            return Scaffold(
              body: IndexedStack(index: index, children: pages),
              bottomNavigationBar: StreamBuilder<List<Conversation>>(
                stream: _convs,
                builder: (context, cs) {
                  final unread = (cs.data ?? const <Conversation>[])
                      .fold<int>(0, (s, c) => s + c.unreadForClient);
                  return NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: _goTo,
                    destinations: [
                      const NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: 'Accueil'),
                      const NavigationDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          selectedIcon: Icon(Icons.receipt_long_rounded),
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
                      if (isAdmin)
                        const NavigationDestination(
                            icon: Icon(Icons.storefront_outlined),
                            selectedIcon: Icon(Icons.storefront_rounded),
                            label: 'Gestion'),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
