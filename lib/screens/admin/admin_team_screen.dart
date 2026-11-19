import 'package:flutter/material.dart';
import '../../utils.dart';

import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/staff.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../services/session.dart';
import '../../widgets/common.dart';

/// Équipe : responsables et agents.
/// - Super Admin : toutes les boutiques, peut nommer des responsables.
/// - Responsable : ses agents uniquement.
class AdminTeamScreen extends StatefulWidget {
  final String? shopId;
  const AdminTeamScreen({super.key, this.shopId});

  @override
  State<AdminTeamScreen> createState() => _AdminTeamScreenState();
}

class _AdminTeamScreenState extends State<AdminTeamScreen> {
  late final Stream<List<StaffMember>> _staff = Db.allStaff(shopId: widget.shopId);

  void _open([StaffMember? m]) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StaffFormScreen(member: m, shopId: widget.shopId)));

  @override
  Widget build(BuildContext context) {
    final session = sessionOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Équipe')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: session.isSuper && session.shops.isEmpty
            ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Créez d\'abord une boutique.')))
            : () => _open(),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(session.isSuper ? 'Ajouter un membre' : 'Ajouter un agent'),
      ),
      body: StreamBuilder<List<StaffMember>>(
        stream: _staff,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error), textAlign: TextAlign.center));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Card(
                color: AppConfig.paleGreen,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Comment ajouter quelqu\'un : la personne installe l\'application '
                    'et crée son compte avec son numéro. Ensuite, touchez « Ajouter », '
                    'tapez son numéro et choisissez son rôle.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(icon: Icons.badge_outlined, title: 'Aucun membre'),
              for (final m in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            m.isManager ? AppConfig.black : AppConfig.green,
                        child: Icon(m.isManager ? Icons.star : Icons.person,
                            color: Colors.white),
                      ),
                      title: Text(m.name.isEmpty ? m.phone : m.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${staffRoleLabels[m.role] ?? m.role} • ${session.shopById(m.shopId).name}'
                          '${m.active ? '' : ' • suspendu'}\n${m.phone}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: (!session.isSuper && m.isManager)
                          ? null
                          : () => _open(m),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class StaffFormScreen extends StatefulWidget {
  final StaffMember? member;
  final String? shopId; // fixé pour un responsable
  const StaffFormScreen({super.key, this.member, this.shopId});

  @override
  State<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends State<StaffFormScreen> {
  final _phone = TextEditingController();
  AppUser? _found;
  bool _searching = false;
  String? _error;
  late String _role = widget.member?.role ?? 'agent';
  late String _shopId = widget.member?.shopId ?? widget.shopId ?? '';
  late final Map<String, bool> _perms = {
    for (final k in staffPermLabels.keys)
      k: widget.member?.perms[k] ?? (k == 'status'),
  };
  late bool _active = widget.member?.active ?? true;
  bool _busy = false;

  bool get _editing => widget.member != null;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!AuthService.isValidPhone(_phone.text)) {
      setState(() => _error = 'Numéro invalide');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final u = await Db.userByPhone(AuthService.displayPhone(_phone.text));
      setState(() {
        _found = u;
        if (u == null) {
          _error = 'Aucun compte avec ce numéro. La personne doit d\'abord '
              'installer l\'application et s\'inscrire.';
        }
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final session = sessionOf(context, listen: false);
    final uid = widget.member?.uid ?? _found?.uid;
    if (uid == null) return;
    if (_shopId.isEmpty) {
      setState(() => _error = 'Choisissez une boutique');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await Db.saveStaff(StaffMember(
        uid: uid,
        shopId: _shopId,
        role: session.isSuper ? _role : 'agent',
        name: widget.member?.name ?? _found?.name ?? '',
        phone: widget.member?.phone ?? _found?.phone ?? '',
        perms: _perms,
        active: _active,
      ));
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Membre enregistré')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce membre de l\'équipe ?'),
        content: const Text('Son compte client reste actif.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.removeStaff(widget.member!.uid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionOf(context);
    final ready = _editing || _found != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifier le membre' : 'Ajouter un membre'),
        actions: [
          if (_editing)
            IconButton(
                onPressed: _remove, icon: const Icon(Icons.person_remove_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_editing) ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de la personne',
                    hintText: '70 00 00 00',
                    prefixIcon: Icon(Icons.phone_android),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _search,
                child: const Text('Chercher'),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFC62828))),
          if (ready) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                    backgroundColor: AppConfig.green,
                    child: Icon(Icons.person, color: Colors.white)),
                title: Text(widget.member?.name ?? _found?.name ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(widget.member?.phone ?? _found?.phone ?? ''),
              ),
            ),
            const SizedBox(height: 16),
            if (session.isSuper) ...[
              DropdownButtonFormField<String>(
                value: session.shops.any((x) => x.id == _shopId) ? _shopId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Boutique'),
                items: [
                  for (final sh in session.shops)
                    DropdownMenuItem(value: sh.id, child: Text(sh.name)),
                ],
                onChanged: (v) => setState(() => _shopId = v ?? ''),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'manager', label: Text('Responsable')),
                  ButtonSegment(value: 'agent', label: Text('Agent')),
                ],
                selected: {_role},
                onSelectionChanged: (v) => setState(() => _role = v.first),
              ),
              const SizedBox(height: 12),
            ],
            if (_role == 'agent' || !session.isSuper) ...[
              const Text('Permissions de l\'agent',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const Text(
                  'Voir les commandes et répondre aux clients : toujours autorisé.',
                  style: TextStyle(color: Colors.black54, fontSize: 12.5)),
              for (final e in staffPermLabels.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: _perms[e.key] ?? false,
                  onChanged: (v) => setState(() => _perms[e.key] = v ?? false),
                ),
            ] else
              const Text(
                'Un responsable gère toute sa boutique : commandes, discussions, '
                'catalogue, nouveautés, clients, agents et réglages.',
                style: TextStyle(color: Colors.black54),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compte actif'),
              subtitle: const Text('Désactivez pour suspendre l\'accès à la Gestion'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ],
      ),
      bottomNavigationBar: ready
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Enregistrer'),
                ),
              ),
            )
          : null,
    );
  }
}
