import 'dart:async';

import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/widgets.dart';

/// Chiffre sur l'icône de l'application : messages non lus, appels manqués,
/// nouvelles commandes et notifications. Affiché quand l'application passe
/// en arrière-plan, effacé quand on la rouvre.
class BadgeService with WidgetsBindingObserver {
  static final BadgeService _i = BadgeService._();
  BadgeService._();

  static int messages = 0; // messages non lus (client ou équipe)
  static int orders = 0; // nouvelles commandes / changements de commande
  static int other = 0; // autres notifications (promotions, devis…)
  static int staffMessages = 0; // équipe : messages clients non lus
  static int staffOrders = 0; // équipe : nouvelles commandes à traiter

  static bool _started = false;
  static bool _background = false;
  static Timer? _debounce;

  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_i);
  }

  /// Mise à jour des compteurs (appelée par l'écran principal).
  static void update(
      {int? messages, int? orders, int? other, int? staffMessages, int? staffOrders}) {
    if (messages != null) BadgeService.messages = messages;
    if (orders != null) BadgeService.orders = orders;
    if (other != null) BadgeService.other = other;
    if (staffMessages != null) BadgeService.staffMessages = staffMessages;
    if (staffOrders != null) BadgeService.staffOrders = staffOrders;
    if (_background) _schedule();
  }

  static int get _msgs => messages + staffMessages;
  static int get _ords => orders + staffOrders;
  static int get total => _msgs + _ords + other;

  static String get _text {
    final parts = <String>[
      if (_msgs > 0) '$_msgs message${_msgs > 1 ? 's' : ''} non lu${_msgs > 1 ? 's' : ''}',
      if (_ords > 0) '$_ords commande${_ords > 1 ? 's' : ''}',
      if (other > 0) '$other notification${other > 1 ? 's' : ''}',
    ];
    return parts.isEmpty ? 'Vous avez des nouveautés' : parts.join(' • ');
  }

  static void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      AichaMedia.setBadge(total, _text).catchError((_) {});
    });
  }

  static void clear() {
    _debounce?.cancel();
    AichaMedia.setBadge(0, '').catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _background = true;
      _schedule();
    } else if (state == AppLifecycleState.resumed) {
      _background = false;
      clear();
    }
  }
}
