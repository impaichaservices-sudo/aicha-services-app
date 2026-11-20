import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/team_chat.dart';
import '../../services/call_service.dart';
import '../../services/session.dart';
import '../../services/team_service.dart';
import '../../utils.dart';
import 'team_chat_screen.dart';

/// Onglet « Équipe » : discussions internes et contacts des collègues.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  Stream<List<TeamChat>>? _chats;
  String _key = '';

  void _setup(Session s) {
    final key = '${s.uid}_${s.isSuper}_${s.staff?.shopId}_${s.shops.length}';
    if (key == _key) return;
    _key = key;
    _chats = TeamService.myChats(s);
    TeamService.ensureShopChats(s);
  }

  void _open(String id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => TeamChatScreen(chatId: id)));

  /// Liste des collègues : écrire ou appeler.
  void _contacts(Session s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => StreamBuilder<List<TeamPerson>>(
          stream: TeamService.people(s),
          builder: (_, snap) {
            final people = snap.data ?? const <TeamPerson>[];
            return ListView(controller: scroll, children: [
              const ListTile(
                title: Text('Contacter un collègue',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              if (snap.connectionState == ConnectionState.waiting && people.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              for (final p in people)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppConfig.green,
                    child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(p.name),
                  subtitle: Text(p.role),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Message',
                      icon: const Icon(Icons.chat_rounded, color: AppConfig.green),
                      onPressed: () async {
                        Navigator.pop(sheet);
                        final id = await TeamService.openDirect(
                            me: s.uid, myName: s.me.name, other: p);
                        if (mounted) _open(id);
                      },
                    ),
                    IconButton(
                      tooltip: 'Appeler',
                      icon: const Icon(Icons.call_rounded, color: AppConfig.green),
                      onPressed: () {
                        Navigator.pop(sheet);
                        CallService.openTeamCall(context,
                            calleeUid: p.uid,
                            calleeName: p.name,
                            shopId: p.shopId,
                            me: s.me);
                      },
                    ),
                  ]),
                ),
            ]);
          },
        ),
      ),
    );
  }

  /// Nouveau groupe (réunion, projet…) : Super Admin ou responsable.
  Future<void> _newGroup(Session s) async {
    final name = TextEditingController();
    final picked = <String>{};
    final people = await TeamService.people(s).first;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Nouveau groupe'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Nom du groupe', hintText: 'Ex : Réunion du lundi'),
              ),
              const SizedBox(height: 12),
              const Text('Membres', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final p in people)
                CheckboxListTile(
                  value: picked.contains(p.uid),
                  title: Text(p.name),
                  subtitle: Text(p.role),
                  onChanged: (v) => set(() => v == true ? picked.add(p.uid) : picked.remove(p.uid)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    if (name.text.trim().isEmpty || picked.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Donnez un nom au groupe et choisissez au moins un membre.')));
      return;
    }
    final members = people.where((p) => picked.contains(p.uid)).toList();
    final shopId = s.isSuper
        ? (members.firstWhere((m) => m.shopId.isNotEmpty,
                orElse: () => const TeamPerson('', '', '', 'main')))
            .shopId
        : (s.staff?.shopId ?? 'main');
    try {
      final id = await TeamService.createGroup(
        me: s.uid,
        myName: s.me.name,
        name: name.text.trim(),
        shopId: shopId,
        members: members,
      );
      if (mounted) _open(id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context);
    _setup(s);
    final canGroup = s.isSuper || (s.staff?.isManager ?? false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Équipe'),
        actions: [
          if (canGroup)
            IconButton(
              tooltip: 'Nouveau groupe',
              icon: const Icon(Icons.group_add_rounded),
              onPressed: () => _newGroup(s),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _contacts(s),
        icon: const Icon(Icons.contacts_rounded),
        label: const Text('Collègues'),
      ),
      body: StreamBuilder<List<TeamChat>>(
        stream: _chats,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error)));
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ici, l\'équipe discute entre elle (les clients ne voient rien).\n\n'
                  'Touchez « Collègues » pour écrire ou appeler un collègue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = list[i];
              final unread = c.unreadFor(s.uid);
              final title = c.titleFor(s.uid);
              return ListTile(
                tileColor: Colors.white,
                leading: CircleAvatar(
                  backgroundColor: c.isDirect ? AppConfig.green : const Color(0xFF1565C0),
                  child: c.isDirect
                      ? Text(title.isEmpty ? '?' : title[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white))
                      : Icon(c.isShop ? Icons.groups_rounded : Icons.group_rounded,
                          color: Colors.white),
                ),
                title: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w600)),
                subtitle: Text(
                  c.lastMessage.isEmpty ? 'Aucun message' : c.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: unread ? Colors.black87 : Colors.black54,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.normal),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(c.lastMessage.isEmpty ? '' : timeLabel(c.lastAt),
                        style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                    if (unread)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                            color: Color(0xFFD32F2F), shape: BoxShape.circle),
                      ),
                  ],
                ),
                onTap: () => _open(c.id),
              );
            },
          );
        },
      ),
    );
  }
}
