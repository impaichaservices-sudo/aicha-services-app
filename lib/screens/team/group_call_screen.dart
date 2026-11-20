import 'dart:async';

import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../services/mic.dart';
import '../../services/room_service.dart';
import '../../utils.dart';

/// Réunion de l'équipe (vocale ou vidéo).
class GroupCallScreen extends StatefulWidget {
  final String roomId;
  final bool incoming; // sonne d'abord (Rejoindre / Ignorer)
  const GroupCallScreen({super.key, required this.roomId, this.incoming = false});

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  GroupCall? _call;
  bool _ringing = false;
  bool _joining = false;
  String _status = '';
  String _title = 'Réunion';
  bool _video = false;
  String _host = '';
  StreamSubscription? _roomSub;
  Timer? _tick;
  Timer? _ringTimeout;

  @override
  void initState() {
    super.initState();
    AichaMedia.showOnLock(true).catchError((_) {});
    _roomSub = RoomService.rooms.doc(widget.roomId).snapshots().listen((d) {
      final data = d.data();
      if (!mounted) return;
      if (data == null || data['status'] != 'active') {
        if (_call == null) _close('Réunion terminée');
        return;
      }
      setState(() {
        _title = (data['title'] ?? 'Réunion') as String;
        _video = data['video'] == true;
        _host = (data['hostName'] ?? '') as String;
      });
    }, onError: (_) {});
    if (widget.incoming) {
      _ringing = true;
      AichaMedia.ring();
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (_ringing) _close('Réunion manquée');
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _tick?.cancel();
    _ringTimeout?.cancel();
    AichaMedia.stopRing();
    AichaMedia.showOnLock(false).catchError((_) {});
    _call?.leave();
    super.dispose();
  }

  void _close(String message) {
    AichaMedia.stopRing();
    if (mounted) setState(() => _status = message);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _join() async {
    if (_joining || _call != null) return;
    _ringing = false;
    _ringTimeout?.cancel();
    await AichaMedia.stopRing();
    if (!mounted) return;
    if (!await ensureMic(context, usage: 'participer à la réunion')) {
      _close('Micro refusé');
      return;
    }
    setState(() {
      _joining = true;
      _status = 'Connexion…';
    });
    final room = (await RoomService.rooms.doc(widget.roomId).get()).data();
    final video = room?['video'] == true;
    final call = GroupCall(widget.roomId,
        me: RoomService.myUid, myName: RoomService.myName, video: video);
    try {
      await call.join();
      call.changed.addListener(_refresh);
      call.ended.addListener(() {
        if (call.ended.value.isEmpty) return;
        if (mounted) setState(() => _call = null);
        _close(call.ended.value);
      });
      if (mounted) {
        setState(() {
          _call = call;
          _status = '';
        });
      }
    } catch (e) {
      await call.leave(reason: '');
      _close(friendlyError(e));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _elapsed() {
    final s = _call?.startedAt;
    if (s == null) return '';
    final d = DateTime.now().difference(s);
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _tile({
    required String name,
    RTCVideoRenderer? renderer,
    bool showVideo = false,
    bool mirror = false,
    String note = '',
  }) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2B20),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (showVideo && renderer != null)
          RTCVideoView(renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        else
          Center(
            child: CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFF2E7D32),
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 28)),
            ),
          ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Text(
            note.isEmpty ? name : '$name · $note',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
          ),
        ),
      ]),
    );
  }

  Widget _grid(GroupCall c) {
    final tiles = <Widget>[
      _tile(
        name: 'Moi',
        renderer: c.localRenderer,
        showVideo: c.video && !c.cameraOff,
        mirror: true,
        note: c.muted ? 'micro coupé' : '',
      ),
      for (final p in c.peers.values)
        _tile(
          name: c.names[p.uid] ?? 'Participant',
          renderer: p.renderer,
          showVideo: p.hasVideo && p.connected,
          note: p.connected ? '' : 'connexion…',
        ),
    ];
    final cols = tiles.length <= 2 ? 1 : 2;
    return LayoutBuilder(builder: (_, box) {
      final rows = (tiles.length / cols).ceil();
      final h = box.maxHeight / (rows < 1 ? 1 : rows);
      final w = box.maxWidth / cols;
      return GridView.count(
        crossAxisCount: cols,
        childAspectRatio: rows <= 3 ? w / h : 0.9,
        physics: rows <= 3 ? const NeverScrollableScrollPhysics() : null,
        children: tiles,
      );
    });
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {Color color = const Color(0xFF2C3E30), bool on = false}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      RawMaterialButton(
        onPressed: onTap,
        shape: const CircleBorder(),
        fillColor: on ? Colors.white : color,
        constraints: const BoxConstraints.tightFor(width: 58, height: 58),
        child: Icon(icon, color: on ? Colors.black : Colors.white),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _call;
    return PopScope(
      canPop: c == null,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1A12),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Icon(_video ? Icons.videocam_rounded : Icons.groups_rounded,
                    color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(
                      c != null
                          ? '${c.peers.length + 1} participant${c.peers.isEmpty ? '' : 's'} · ${_elapsed()}'
                          : (_host.isEmpty ? 'Réunion de l\'équipe' : 'Organisée par $_host'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: c != null
                  ? (c.peers.isEmpty
                      ? Stack(children: [
                          _grid(c),
                          const Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text('En attente des participants…',
                                  style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                        ])
                      : _grid(c))
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_video ? Icons.videocam_rounded : Icons.groups_rounded,
                            color: Colors.white, size: 72),
                        const SizedBox(height: 16),
                        Text(
                          _status.isNotEmpty
                              ? _status
                              : (_ringing
                                  ? (_video ? 'Réunion vidéo…' : 'Réunion vocale…')
                                  : 'Connexion…'),
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              child: c == null
                  ? (_ringing
                      ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          _btn(Icons.close_rounded, 'Ignorer',
                              () => _close('Réunion ignorée'),
                              color: const Color(0xFFD32F2F)),
                          _btn(Icons.call_rounded, 'Rejoindre', _join,
                              color: const Color(0xFF2E7D32)),
                        ])
                      : const SizedBox(height: 70))
                  : Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        _btn(c.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            c.muted ? 'Micro coupé' : 'Micro', c.toggleMute,
                            on: c.muted),
                        if (c.video)
                          _btn(c.cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                              'Caméra', c.toggleCamera,
                              on: c.cameraOff),
                        if (c.video)
                          _btn(Icons.cameraswitch_rounded, 'Retourner', c.switchCamera),
                        _btn(c.speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
                            c.speaker ? 'Haut-parleur' : 'Écouteur', c.toggleSpeaker,
                            on: c.speaker),
                        _btn(Icons.call_end_rounded, c.isHost ? 'Terminer' : 'Quitter',
                            () async {
                          await c.leave(
                              reason: c.isHost ? 'Réunion terminée' : 'Vous avez quitté');
                        }, color: const Color(0xFFD32F2F)),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
