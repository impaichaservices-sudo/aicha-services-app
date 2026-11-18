import 'package:cloud_firestore/cloud_firestore.dart';

/// Permissions d'un agent (un responsable a toutes les permissions
/// de sa boutique).
const staffPermLabels = {
  'status': 'Modifier les statuts des commandes',
  'quotes': 'Gérer les devis (fixer les prix)',
  'catalog': 'Gérer le catalogue',
  'promos': 'Publier des nouveautés',
  'clients': 'Voir les clients',
};

const staffRoleLabels = {
  'manager': 'Responsable',
  'agent': 'Agent',
};

/// Membre de l'équipe d'une boutique : responsable ou agent.
/// Document staff/{uid} ; le Super Admin n'en a pas besoin.
class StaffMember {
  final String uid;
  final String shopId;
  final String role; // 'manager' | 'agent'
  final String name;
  final String phone;
  final Map<String, bool> perms;
  final bool active;

  const StaffMember({
    required this.uid,
    required this.shopId,
    required this.role,
    required this.name,
    required this.phone,
    required this.perms,
    required this.active,
  });

  bool get isManager => role == 'manager';

  /// Répondre aux clients et voir les commandes : toujours autorisé.
  bool can(String perm) => isManager || (perms[perm] ?? false);

  factory StaffMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final p = d['perms'];
    return StaffMember(
      uid: doc.id,
      shopId: (d['shopId'] ?? '') as String,
      role: (d['role'] ?? 'agent') as String,
      name: (d['name'] ?? '') as String,
      phone: (d['phone'] ?? '') as String,
      perms: p is Map
          ? p.map((k, v) => MapEntry(k.toString(), v == true))
          : <String, bool>{},
      active: (d['active'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'shopId': shopId,
        'role': role,
        'name': name,
        'phone': phone,
        'perms': perms,
        'active': active,
      };
}
