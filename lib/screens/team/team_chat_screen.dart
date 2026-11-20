import 'dart:async';
import 'dart:io';

import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../config.dart';
import '../../models/team_chat.dart';
import '../../services/call_service.dart';
import '../../services/file_service.dart';
import '../../services/mic.dart';
import '../../services/notify_service.dart';
import '../../services/room_service.dart';
import '../../services/session.dart';
import '../../services/team_service.dart';
import '../../utils.dart';
import '../chat_screen.dart' show VoiceMessage;

/// Discussion interne de l'équipe (texte, photos, fichiers, vocaux).
class TeamChatScreen extends StatefulWidget {
  final String chatId;
  const TeamChatScreen({super.key, required this.chatId});

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  late final Stream<TeamChat?> _chat = TeamService.chatStream(widget.chatId);
  late final Stream<List<TeamMessage>> _messages = TeamService.messages(widget.chatId);
  final _text = TextEditingController();
  bool _sending = false;
  bool _recording = false;
  String _recPath = '';
  DateTime _recStart = DateTime.now();
  Timer? _recTimer;
  TeamChat? _current;

  @override
  void initState() {
    super.initState();
    NotifyService.openTeamChat = widget.chatId;
  }

  @override
  void dispose() {
    if (NotifyService.openTeamChat == widget.chatId) NotifyService.openTeamChat = '';
    _recTimer?.cancel();
    if (_recording) AichaMedia.stop();
    _text.dispose();
    super.dispose();
  }

  String get _stamp => DateTime.now().millisecondsSinceEpoch.toString();

  Future<void> _send(TeamChat chat) async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final s = sessionOf(context, listen: false);
    _text.clear();
    await TeamService.send(chat: chat, me: s.uid, myName: s.me.name, text: t);
  }

  Future<void> _upload(TeamChat chat, Future<PickedUpload?> Function() up,
      {String label = ''}) async {
    final s = sessionOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final f = await up();
      if (f == null) return;
      await TeamService.send(
        chat: chat,
        me: s.uid,
        myName: s.me.name,
        text: label,
        type: 'file',
        fileUrl: f.url,
        fileName: f.name,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach(TeamChat chat) => _upload(
      chat,
      () => FileService.pickAndUpload(
          shopId: chat.shopId, conversationId: 'team:${chat.id}'));

  Future<void> _startRec() async {
    if (!await ensureMic(context, usage: 'enregistrer un message vocal')) return;
    final dir = await getTemporaryDirectory();
    _recPath = '${dir.path}/vocal_$_stamp.m4a';
    await AichaMedia.stopPlay();
    await AichaMedia.start(_recPath);
    _recStart = DateTime.now();
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (DateTime.now().difference(_recStart) > const Duration(minutes: 3)) {
        _stopRec(send: true);
      } else {
        setState(() {});
      }
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRec({required bool send}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    final len = DateTime.now().difference(_recStart);
    setState(() => _recording = false);
    final ok = await AichaMedia.stop();
    final file = File(_recPath);
    final chat = _current;
    if (!send || !ok || len < const Duration(seconds: 1) || chat == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    final d = '${len.inMinutes}:${(len.inSeconds % 60).toString().padLeft(2, '0')}';
    await _upload(chat, () async {
      final up = await FileService.uploadBytes(
        bytes: await file.readAsBytes(),
        name: 'vocal_$_stamp.m4a',
        shopId: chat.shopId,
        conversationId: 'team:${chat.id}',
      );
      if (await file.exists()) await file.delete();
      return up;
    }, label: '🎤 Message vocal ($d)');
  }

  void _call(TeamChat chat) {
    final s = sessionOf(context, listen: false);
    final other = chat.otherUid(s.uid);
    if (other.isEmpty) return;
    CallService.openTeamCall(
      context,
      calleeUid: other,
      calleeName: chat.titleFor(s.uid),
      shopId: chat.shopId,
      me: s.me,
    );
  }

  Future<void> _meeting(TeamChat chat, {required bool video}) async {
    final s = sessionOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    if (RoomService.current != null || CallService.current != null) return;
    if (!chat.isDirect) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(video ? 'Lancer une réunion vidéo ?' : 'Lancer une réunion vocale ?'),
          content: Text(video
              ? 'Tous les membres du groupe vont sonner. Conseil : 6 personnes '
                  'maximum en vidéo ; au-delà, préférez la réunion vocale.'
              : 'Tous les membres du groupe vont sonner.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lancer')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final id = await RoomService.create(s: s, chat: chat, video: video);
      RoomService.open(id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  void _members(TeamChat chat) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(chat.isShop
                ? 'Tous les agents et responsables de la boutique'
                : '${chat.members.length} membres'),
          ),
          for (final u in chat.members)
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(chat.memberNames[u] ?? 'Membre'),
            ),
        ]),
      ),
    );
  }

  Widget _bubble(TeamMessage m, bool mine, bool showName) {
    final fg = mine ? Colors.white : Colors.black87;
    if (m.type == 'system') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(m.text, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
        ),
      );
    }
    Widget content;
    if (m.type == 'file') {
      final kind = FileService.kindOf(m.fileName);
      if (kind == 'audio') {
        content = VoiceMessage(url: m.fileUrl, name: m.fileName, label: m.text, color: fg);
      } else if (kind == 'image') {
        content = GestureDetector(
          onTap: () => FileService.open(m.fileUrl, m.fileName),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder(
              future: FileService.load(m.fileUrl),
              builder: (_, snap) => snap.data != null
                  ? Image.memory(snap.data!, width: 220, height: 220, fit: BoxFit.cover)
                  : Container(
                      width: 220, height: 160, color: Colors.black12,
                      child: Icon(snap.hasError ? Icons.broken_image : Icons.photo)),
            ),
          ),
        );
      } else {
        content = InkWell(
          onTap: () => FileService.open(m.fileUrl, m.fileName),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insert_drive_file, color: fg, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${m.fileName}\nToucher pour ouvrir',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            ),
          ]),
        );
      }
    } else {
      content = Text(m.text, style: TextStyle(color: fg, fontSize: 15.5));
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? AppConfig.green : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showName && !mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(m.senderName,
                    style: const TextStyle(
                        color: Color(0xFF1565C0), fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            content,
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(timeLabel(m.createdAt),
                  style: TextStyle(color: mine ? Colors.white70 : Colors.black45, fontSize: 11)),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(m.pending ? Icons.schedule : Icons.done,
                    size: 13, color: Colors.white70),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _input(TeamChat chat) {
    if (_recording) {
      final len = DateTime.now().difference(_recStart);
      return Row(children: [
        IconButton(
          tooltip: 'Supprimer',
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _stopRec(send: false),
        ),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
              'Enregistrement… ${len.inMinutes}:${(len.inSeconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton.filled(
          tooltip: 'Envoyer',
          icon: const Icon(Icons.send_rounded),
          onPressed: () => _stopRec(send: true),
        ),
      ]);
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _text,
      builder: (_, v, __) => Row(children: [
        Expanded(
          child: TextField(
            controller: _text,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Message à l\'équipe',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                tooltip: 'Joindre une photo ou un fichier',
                icon: const Icon(Icons.attach_file_rounded),
                onPressed: _sending ? null : () => _attach(chat),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        v.text.trim().isEmpty
            ? IconButton.filled(
                tooltip: 'Message vocal',
                icon: const Icon(Icons.mic_rounded),
                onPressed: _sending ? null : _startRec,
              )
            : IconButton.filled(
                tooltip: 'Envoyer',
                icon: const Icon(Icons.send_rounded),
                onPressed: () => _send(chat),
              ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = sessionOf(context, listen: false);
    return StreamBuilder<TeamChat?>(
      stream: _chat,
      builder: (context, cs) {
        final chat = cs.data;
        _current = chat;
        if (chat != null && chat.unreadFor(s.uid)) TeamService.markRead(chat.id, s.uid);
        return Scaffold(
          backgroundColor: const Color(0xFFE9EFE9),
          appBar: AppBar(
            title: Text(chat?.titleFor(s.uid) ?? 'Équipe'),
            actions: [
              if (chat != null && chat.isDirect) ...[
                IconButton(
                  tooltip: 'Appel vidéo',
                  icon: const Icon(Icons.videocam_rounded),
                  onPressed: () => _meeting(chat, video: true),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () => _call(chat),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Appeler'),
                  ),
                ),
              ],
              if (chat != null && !chat.isDirect && (s.isSuper || (s.staff?.isManager ?? false))) ...[
                IconButton(
                  tooltip: 'Réunion vocale',
                  icon: const Icon(Icons.call_rounded),
                  onPressed: () => _meeting(chat, video: false),
                ),
                IconButton(
                  tooltip: 'Réunion vidéo',
                  icon: const Icon(Icons.videocam_rounded),
                  onPressed: () => _meeting(chat, video: true),
                ),
              ],
              if (chat != null && !chat.isDirect)
                IconButton(
                  tooltip: 'Membres',
                  icon: const Icon(Icons.group_rounded),
                  onPressed: () => _members(chat),
                ),
            ],
          ),
          body: chat == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  if (chat.activeRoom.isNotEmpty)
                    Material(
                      color: const Color(0xFF1565C0),
                      child: ListTile(
                        leading: Icon(
                            chat.activeRoomVideo ? Icons.videocam_rounded : Icons.groups_rounded,
                            color: Colors.white),
                        title: Text(
                            chat.activeRoomVideo ? 'Réunion vidéo en cours' : 'Réunion vocale en cours',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800)),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1565C0)),
                          onPressed: () => RoomService.open(chat.activeRoom),
                          child: const Text('Rejoindre'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<TeamMessage>>(
                      stream: _messages,
                      builder: (context, ms) {
                        if (ms.hasError) {
                          return Center(child: Text(friendlyError(ms.error)));
                        }
                        final list = ms.data ?? const <TeamMessage>[];
                        if (list.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Aucun message. Écrivez le premier !',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54)),
                            ),
                          );
                        }
                        return ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final m = list[i];
                            final older = i + 1 < list.length ? list[i + 1] : null;
                            final showName = !chat.isDirect &&
                                (older == null || older.senderId != m.senderId);
                            return _bubble(m, m.senderId == s.uid, showName);
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_sending) const LinearProgressIndicator(),
                        _input(chat),
                      ]),
                    ),
                  ),
                ]),
        );
      },
    );
  }
}
