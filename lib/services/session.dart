import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/shop.dart';
import '../models/shop_settings.dart';
import '../models/staff.dart';

/// Qui est connecté et dans quelle boutique : partagé à tous les écrans.
class Session {
  final String uid;
  final AppUser? user;
  final bool isSuper; // Super Admin AÏCHA SERVICES
  final StaffMember? staff; // responsable ou agent d'une boutique
  final List<Shop> shops; // boutiques actives
  final ShopSettings settings;

  const Session({
    required this.uid,
    required this.user,
    required this.isSuper,
    required this.staff,
    required this.shops,
    required this.settings,
  });

  bool get isStaff => staff != null && staff!.active;
  bool get canManage => isSuper || isStaff;

  /// La boutique de l'équipe (null pour le Super Admin = toutes).
  String? get managedShopId => isSuper ? null : (isStaff ? staff!.shopId : null);

  /// Agent simple (pas responsable) : ne voit que ses discussions.
  String? get agentUid =>
      (!isSuper && isStaff && staff!.role != 'manager') ? uid : null;

  bool can(String perm) => isSuper || (isStaff && staff!.can(perm));

  /// Boutique choisie par le client (ou boutique par défaut).
  String get clientShopId {
    final id = user?.shopId ?? '';
    if (shops.any((s) => s.id == id)) return id;
    return shops.isEmpty ? 'main' : '';
  }

  bool get needsShopChoice => shops.isNotEmpty && clientShopId.isEmpty;

  Shop shopById(String id) {
    for (final s in shops) {
      if (s.id == id) return s;
    }
    return Shop.fromSettings(settings);
  }

  /// Infos de contact de la boutique du client.
  Shop get myShop => shopById(clientShopId);

  AppUser get me =>
      user ?? AppUser(uid: uid, name: 'Client', phone: '', email: '');

  /// Nom affiché quand l'équipe écrit dans une discussion.
  String teamName(String shopId) {
    final s = shopById(shopId);
    return s.id == 'main' ? 'AÏCHA SERVICES' : s.name;
  }
}

/// Session partagée à toute l'application (y compris les écrans ouverts
/// par-dessus l'écran principal). Mise à jour par HomeScreen.
class SessionNotifier extends ChangeNotifier {
  Session? _value;
  Session? get value => _value;

  void set(Session s) {
    _value = s;
    notifyListeners();
  }

  void clear() {
    _value = null;
    notifyListeners();
  }
}

/// La session courante (ou une session vide le temps du chargement).
Session sessionOf(BuildContext context, {bool listen = true}) {
  final n = listen
      ? context.watch<SessionNotifier>()
      : context.read<SessionNotifier>();
  return n.value ??
      Session(
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        user: null,
        isSuper: false,
        staff: null,
        shops: const [],
        settings: const ShopSettings(),
      );
}
