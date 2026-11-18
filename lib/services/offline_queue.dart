import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../nav.dart';
import 'db.dart';

/// État de synchronisation affiché en haut de l'application.
class SyncStatus {
  /// Nombre d'envois en attente (messages + commandes).
  static final pending = ValueNotifier<int>(0);

  /// true pendant 3 s après la fin d'une synchronisation (« Synchronisé »).
  static final justSynced = ValueNotifier<bool>(false);

  static int _writes = 0;

  /// Un envoi Firestore a été lancé : attendre qu'il parte vers le serveur.
  static void trackWrite(Future<void> commit) {
    _writes++;
    _refresh();
    commit.whenComplete(() {
      _writes = _writes > 0 ? _writes - 1 : 0;
      _refresh(done: true);
    }).catchError((_) {});
  }

  static void _refresh({bool done = false}) {
    final before = pending.value;
    pending.value = _writes + OfflineQueue.count;
    if (done && before > 0 && pending.value == 0) {
      justSynced.value = true;
      Timer(const Duration(seconds: 3), () => justSynced.value = false);
    }
  }

  static void refresh() => _refresh(done: true);
}

/// Commandes préparées sans connexion : enregistrées sur le téléphone,
/// envoyées automatiquement dès que la connexion revient.
class OfflineQueue {
  static List<Map<String, dynamic>> _orders = [];
  static bool _loaded = false;
  static bool _flushing = false;
  static Timer? _timer;

  static int get count => _orders.length;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/commandes_en_attente.json');
  }

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _orders = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      _orders = [];
    }
    SyncStatus.refresh();
  }

  static Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_orders), flush: true);
    } catch (_) {}
  }

  /// Ne garde que des valeurs simples (texte, nombres, listes, cartes).
  static dynamic _plain(dynamic v) {
    if (v is Map) {
      final out = <String, dynamic>{};
      v.forEach((k, x) {
        if (x is FieldValue) return;
        out[k.toString()] = _plain(x);
      });
      return out;
    }
    if (v is List) return v.map(_plain).toList();
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    return v;
  }

  static Future<void> addOrder({
    required String orderId,
    required Map<String, dynamic> data,
    required Map<String, int> bookings,
    required String shopCode,
  }) async {
    await _load();
    _orders.add({
      'orderId': orderId,
      'data': _plain(data),
      'bookings': bookings,
      'shopCode': shopCode,
      'savedAt': DateTime.now().toIso8601String(),
    });
    await _save();
    SyncStatus.refresh();
    start();
  }

  /// Relance l'envoi toutes les 30 s tant qu'il reste des commandes.
  static void start() {
    _load().then((_) {
      flush();
      _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => flush());
    });
  }

  static Future<void> flush() async {
    await _load();
    if (_flushing || _orders.isEmpty) return;
    _flushing = true;
    try {
      for (final q in List<Map<String, dynamic>>.from(_orders)) {
        try {
          final number = await Db.createOrderFromMap(
            orderId: q['orderId'] as String,
            data: Map<String, dynamic>.from(q['data'] as Map),
            bookings: Map<String, int>.from(
                (q['bookings'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()))),
            shopCode: (q['shopCode'] ?? '') as String,
          ).timeout(const Duration(seconds: 20));
          _orders.remove(q);
          await _save();
          messengerKey.currentState?.showSnackBar(SnackBar(
              content: Text('Commande $number envoyée ✅ (synchronisée)')));
        } catch (_) {
          break; // toujours pas de connexion : on réessaiera
        }
      }
    } finally {
      _flushing = false;
      SyncStatus.refresh();
    }
  }
}

/// Bandeau « Synchronisation en attente » / « Synchronisé ».
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SyncStatus.pending,
      builder: (_, n, __) => ValueListenableBuilder<bool>(
        valueListenable: SyncStatus.justSynced,
        builder: (_, synced, __) {
          if (n == 0 && !synced) return const SizedBox.shrink();
          final waiting = n > 0;
          return Material(
            color: waiting ? const Color(0xFFFFF4E5) : const Color(0xFFEAF6E5),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  Icon(waiting ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                      size: 18,
                      color: waiting ? const Color(0xFFB26A00) : const Color(0xFF1E8B09)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      waiting
                          ? 'Synchronisation en attente ($n)… vérifiez votre connexion Internet.'
                          : 'Synchronisé ✅',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
