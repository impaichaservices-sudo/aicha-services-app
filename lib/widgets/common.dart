import 'package:flutter/material.dart';

import '../config.dart';
import '../models/order.dart';

/// Titre de section : « Services populaires », « Nos offres »…
class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppConfig.black)),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

/// Petite pastille colorée (statut, « Promo », « Disponible »…).
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'nouvelle':
      return const Color(0xFF1565C0);
    case 'confirmee':
      return const Color(0xFF6A1B9A);
    case 'en_cours':
      return const Color(0xFFEF6C00);
    case 'prete':
      return AppConfig.green;
    case 'livree':
      return const Color(0xFF455A64);
    case 'annulee':
      return const Color(0xFFC62828);
  }
  return Colors.grey;
}

/// Progression : Nouvelle → Confirmée → En cours → Prête → Livrée/Retirée.
class StatusProgress extends StatelessWidget {
  final String status;
  final bool compact;
  const StatusProgress({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (status == 'annulee') {
      return const Pill('Commande annulée',
          color: Color(0xFFC62828), icon: Icons.cancel_outlined);
    }
    final current = orderSteps.indexOf(status);
    const short = ['Nouvelle', 'Confirmée', 'En cours', 'Prête', 'Livrée'];
    return Row(
      children: [
        for (var i = 0; i < orderSteps.length; i++) ...[
          Expanded(
            child: Column(children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i <= current ? AppConfig.green : const Color(0xFFE0E5DD),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 6),
                Text(short.elementAt(i),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                      color: i <= current ? AppConfig.black : Colors.black45,
                    )),
              ],
            ]),
          ),
          if (i < orderSteps.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// Écran vide avec icône et message.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState(
      {super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: AppConfig.paleGreen, shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppConfig.green),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Pastille de compteur (messages non lus…).
class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: AppConfig.green, borderRadius: BorderRadius.circular(12)),
      child: Text('$count',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
