import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../services/db.dart';
import '../state/cart.dart';
import 'admin/admin_screen.dart';
import 'cart_screen.dart';
import 'catalog_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<Cart>().count;
    return StreamBuilder<bool>(
      stream: _admin,
      builder: (context, adminSnap) {
        final isAdmin = adminSnap.data ?? false;
        return StreamBuilder<AppUser?>(
          stream: _user,
          builder: (context, snap) {
            final user = snap.data;
            final pages = <Widget>[
              const CatalogScreen(),
              CartScreen(user: user),
              OrdersScreen(uid: widget.uid),
              if (isAdmin) const AdminScreen(),
              ProfileScreen(user: user),
            ];
            final destinations = <NavigationDestination>[
              const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Accueil'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: cartCount > 0,
                  label: Text('$cartCount'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                selectedIcon: const Icon(Icons.shopping_cart),
                label: 'Panier',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Commandes'),
              if (isAdmin)
                const NavigationDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings),
                    label: 'Gestion'),
              const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profil'),
            ];
            final index = _index < pages.length ? _index : 0;
            return Scaffold(
              body: pages[index],
              bottomNavigationBar: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: destinations,
              ),
            );
          },
        );
      },
    );
  }
}
