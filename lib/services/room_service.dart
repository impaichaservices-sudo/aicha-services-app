import 'dart:async';

import 'package:aicha_media/aicha_media.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config.dart';
import '../models/team_chat.dart';
import '../nav.dart';
import '../screens/team/group_call_screen.dart';
import 'call_service.dart';
import 'db.dart';
import 'notify_service.dart';
import 'session.dart';
import 'team_service.dart';

/// Réunions de l'équipe (vocales ou vidéo), chaque téléphone relié à chacun
/// des autres. Conseillé : 6 personnes maximum en vidéo.
///   rooms/{id}                     : réunion (organisateur, membres, état)
///   rooms/{id}/peers/{uid}         : qui est présent
///   rooms/{id}/links/{from_to_t}   : mise en relation de deux téléphones
///   rooms/{id}/links/{…}/cands/{c} : chemins réseau
class RoomService {
  static final _fs = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get rooms => _fs.collection('rooms');

  static GroupCall? current;
  static StreamSubscription? _sub;
  static String _key = '';
  static final Set<String> _shown = {};
  static String _me = '';
  static String _myName = '';

  /// Lance une réunion avec les membres d'une discussion d'équipe.
  static Future<String> create({
    required Session s,
    required TeamChat chat,
    required bool video,
  }) async {
    final members = <String>{s.uid, ...chat.members};
    final names = <String, String>{...chat.memberNames, s.uid: s.me.name};
    if (chat.isShop) {
      final staff = await Db.allStaff(shopId: chat.shopId).first;
      for (final m in staff) {
        if (!m.active) continue;
        members.add(m.uid);
        names[m.uid] = m.name;
      }
      for (final u in AppConfig.adminUids) {
        members.add(u);
        names.putIfAbsent(u, () => 'Super Admin');
      }
    }
    final ref = rooms.doc();
    await ref.set({
      'hostId': s.uid,
      'hostName': s.me.name,
      'title': chat.titleFor(s.uid),
      'chatId': chat.id,
      'shopId': chat.shopId,
      'video': video,
      'members': members.take(30).toList(),
      'memberNames': names,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      await TeamService.chats
          .doc(chat.id)
          .update({'activeRoom': ref.id, 'activeRoomVideo': video});
    } catch (_) {}
    NotifyService.roomCall(roomId: ref.id);
    return ref.id;
  }

  /// Ouvre l'écran de réunion (rejoindre tout de suite).
  static void open(String roomId, {bool incoming = false}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (current != null && current!.roomId == roomId) return;
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GroupCallScreen(roomId: roomId, incoming: incoming),
    ));
  }

  /// « Répondre » touché sur l'écran d'appel d'Android.
  static void answer(String roomId) {
    _shown.add(roomId);
    if (current != null) return;
    open(roomId);
  }

  /// Sonnerie quand une réunion commence (application ouverte).
  static void watch(Session s) {
    if (!s.canManage) return;
    final key = s.uid;
    _me = s.uid;
    _myName = s.me.name;
    if (key == _key) return;
    _key = key;
    _sub?.cancel();
    _sub = rooms.where('members', arrayContains: s.uid).snapshots().listen((q) {
      for (final c in q.docChanges) {
        final d = c.doc.data();
        if (d == null) continue;
        final id = c.doc.id;
        if (d['status'] != 'active' || d['hostId'] == _me) continue;
        final at = d['createdAt'];
        if (at is! Timestamp ||
            DateTime.now().difference(at.toDate()) > const Duration(seconds: 60)) {
          continue;
        }
        if (_shown.contains(id) || current != null || CallService.current != null) continue;
        _shown.add(id);
        final answered = CallService.pendingAnswer.value == 'room:$id';
        final visible =
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (answered) {
          open(id);
        } else if (visible) {
          open(id, incoming: true);
        }
        // Sinon : c'est Android qui sonne (écran d'appel natif).
      }
    }, onError: (_) {});
  }

  static String get myUid => _me;
  static String get myName => _myName;
}

/// Un participant distant.
class RoomPeer {
  final String uid;
  final String linkId;
  final bool outgoing;
  RTCPeerConnection? pc;
  final renderer = RTCVideoRenderer();
  bool rendererReady = false;
  bool hasVideo = false;
  bool connected = false;
  bool remoteSet = false;
  final List<RTCIceCandidate> pendingIn = [];
  StreamSubscription? linkSub;
  StreamSubscription? candSub;
  RoomPeer(this.uid, this.linkId, this.outgoing);
}

/// Réunion en cours sur ce téléphone.
class GroupCall {
  final String roomId;
  final String me;
  final String myName;
  final DocumentReference<Map<String, dynamic>> ref;
  bool video;

  MediaStream? local;
  final localRenderer = RTCVideoRenderer();
  final peers = <String, RoomPeer>{};
  final names = <String, String>{};
  final changed = ValueNotifier<int>(0);
  final ended = ValueNotifier<String>('');
  String hostId = '';
  String title = '';
  bool muted = false;
  bool cameraOff = false;
  bool speaker = true;
  int joinedAt = 0;
  DateTime? startedAt;
  bool _closed = false;
  StreamSubscription? _roomSub;
  StreamSubscription? _peersSub;
  StreamSubscription? _linksSub;
  List<Map<String, dynamic>> _ice = const [];

  GroupCall(this.roomId, {required this.me, required this.myName, required this.video})
      : ref = RoomService.rooms.doc(roomId);

  bool get isHost => me == hostId;
  void _bump() => changed.value++;

  Future<void> join() async {
    RoomService.current = this;
    joinedAt = DateTime.now().millisecondsSinceEpoch;
    final room = (await ref.get()).data() ?? const <String, dynamic>{};
    if (room['status'] != 'active') throw Exception('Cette réunion est terminée.');
    hostId = (room['hostId'] ?? '') as String;
    title = (room['title'] ?? 'Réunion') as String;
    (room['memberNames'] as Map? ?? const {}).forEach((k, v) => names['$k'] = '$v');
    await localRenderer.initialize();
    const audio = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };
    if (video) {
      try {
        local = await navigator.mediaDevices.getUserMedia({
          'audio': audio,
          'video': {
            'facingMode': 'user',
            'width': {'ideal': 320},
            'height': {'ideal': 240},
            'frameRate': {'ideal': 12},
          },
        });
      } catch (_) {
        video = false;
        cameraOff = true;
      }
    }
    local ??= await navigator.mediaDevices.getUserMedia({'audio': audio, 'video': false});
    localRenderer.srcObject = local;
    Helper.setSpeakerphoneOn(speaker);
    _ice = await CallService.iceServers();
    startedAt = DateTime.now();

    _roomSub = ref.snapshots().listen((d) {
      final data = d.data();
      if (data == null || data['status'] != 'active') {
        leave(reason: 'Réunion terminée');
      }
    }, onError: (_) {});

    await ref.collection('peers').doc(me).set({
      'name': myName,
      'active': true,
      'at': joinedAt,
    });

    // Se relier aux personnes déjà présentes.
    final present = await ref.collection('peers').where('active', isEqualTo: true).get();
    for (final d in present.docs) {
      if (d.id == me) continue;
      names[d.id] = (d.data()['name'] ?? names[d.id] ?? 'Participant') as String;
      await _offerTo(d.id);
    }

    _peersSub = ref.collection('peers').snapshots().listen((q) {
      for (final c in q.docChanges) {
        final id = c.doc.id;
        if (id == me) continue;
        final data = c.doc.data() ?? const <String, dynamic>{};
        names[id] = (data['name'] ?? names[id] ?? 'Participant') as String;
        if (data['active'] != true) _closePeer(id);
      }
      _bump();
    }, onError: (_) {});

    // Ceux qui arrivent après moi se relient à moi.
    _linksSub = ref.collection('links').where('to', isEqualTo: me).snapshots().listen((q) {
      for (final c in q.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final d = c.doc.data();
        if (d == null) continue;
        final at = (d['at'] as num?)?.toInt() ?? 0;
        if (at < joinedAt - 3000) continue;
        _answer(c.doc.id, d);
      }
    }, onError: (_) {});
    _bump();
  }

  Future<RTCPeerConnection> _newPc(RoomPeer p) async {
    final pc = await createPeerConnection({'iceServers': _ice, 'sdpSemantics': 'unified-plan'});
    p.pc = pc;
    if (!p.rendererReady) {
      await p.renderer.initialize();
      p.rendererReady = true;
    }
    for (final t in local!.getTracks()) {
      await pc.addTrack(t, local!);
    }
    final link = ref.collection('links').doc(p.linkId);
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      link.collection('cands').add({
        'from': me,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      }).catchError((_) => link);
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) p.renderer.srcObject = e.streams.first;
      if (e.track.kind == 'video') p.hasVideo = true;
      _bump();
    };
    pc.onConnectionState = (s) {
      p.connected = s == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      _bump();
    };
    p.candSub = link.collection('cands').snapshots().listen((q) {
      for (final c in q.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final d = c.doc.data();
        if (d == null || d['from'] == me) continue;
        final cand = RTCIceCandidate(d['candidate'] as String?, d['sdpMid'] as String?,
            (d['sdpMLineIndex'] as num?)?.toInt());
        if (p.remoteSet) {
          pc.addCandidate(cand).catchError((_) {});
        } else {
          p.pendingIn.add(cand);
        }
      }
    }, onError: (_) {});
    return pc;
  }

  Future<void> _remoteReady(RoomPeer p) async {
    p.remoteSet = true;
    for (final c in p.pendingIn) {
      await p.pc?.addCandidate(c).catchError((_) {});
    }
    p.pendingIn.clear();
    _limitVideo(p.pc);
  }

  /// Vidéo légère (connexions faibles) : 150 kb/s, 12 images/s.
  Future<void> _limitVideo(RTCPeerConnection? pc) async {
    if (pc == null) return;
    try {
      for (final s in await pc.getSenders()) {
        if (s.track?.kind != 'video') continue;
        final params = s.parameters;
        final enc = params.encodings;
        if (enc == null || enc.isEmpty) continue;
        enc.first.maxBitrate = 150000;
        enc.first.maxFramerate = 12;
        await s.setParameters(params);
      }
    } catch (_) {}
  }

  Future<void> _offerTo(String uid) async {
    if (_closed) return;
    final p = RoomPeer(uid, '${me}_${uid}_$joinedAt', true);
    peers[uid] = p;
    try {
      final pc = await _newPc(p);
      final offer = CallService.lowBandwidth(await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      }));
      await pc.setLocalDescription(offer);
      final link = ref.collection('links').doc(p.linkId);
      await link.set({
        'from': me,
        'to': uid,
        'at': DateTime.now().millisecondsSinceEpoch,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
      p.linkSub = link.snapshots().listen((d) async {
        final a = d.data()?['answer'];
        if (a is Map && !p.remoteSet && p.pc != null) {
          await p.pc!.setRemoteDescription(
              RTCSessionDescription(a['sdp'] as String?, a['type'] as String?));
          await _remoteReady(p);
        }
      }, onError: (_) {});
    } catch (_) {
      _closePeer(uid);
    }
    _bump();
  }

  Future<void> _answer(String linkId, Map<String, dynamic> d) async {
    if (_closed) return;
    final from = (d['from'] ?? '') as String;
    if (from.isEmpty || from == me) return;
    final existing = peers[from];
    // Deux personnes qui se relient en même temps : un seul lien est gardé.
    if (existing != null && existing.outgoing && me.compareTo(from) < 0) return;
    if (existing != null) _closePeer(from, keepName: true);
    final p = RoomPeer(from, linkId, false);
    peers[from] = p;
    try {
      final pc = await _newPc(p);
      final o = d['offer'] as Map;
      await pc.setRemoteDescription(
          RTCSessionDescription(o['sdp'] as String?, o['type'] as String?));
      await _remoteReady(p);
      final answer = CallService.lowBandwidth(await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      }));
      await pc.setLocalDescription(answer);
      await ref.collection('links').doc(linkId).update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (_) {
      _closePeer(from);
    }
    _bump();
  }

  void _closePeer(String uid, {bool keepName = false}) {
    final p = peers.remove(uid);
    if (p == null) return;
    p.linkSub?.cancel();
    p.candSub?.cancel();
    p.pc?.close();
    if (p.rendererReady) {
      p.renderer.srcObject = null;
      // Laisser l'écran se redessiner avant de libérer l'image.
      Future.delayed(const Duration(milliseconds: 600), p.renderer.dispose);
    }
    _bump();
  }

  void toggleMute() {
    muted = !muted;
    for (final t in local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    _bump();
  }

  void toggleCamera() {
    if (!video) return;
    cameraOff = !cameraOff;
    for (final t in local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !cameraOff;
    }
    _bump();
  }

  Future<void> switchCamera() async {
    final v = local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (v.isEmpty) return;
    try {
      await Helper.switchCamera(v.first);
    } catch (_) {}
  }

  void toggleSpeaker() {
    speaker = !speaker;
    Helper.setSpeakerphoneOn(speaker);
    _bump();
  }

  /// Quitter. L'organisateur qui quitte termine la réunion pour tous.
  Future<void> leave({String reason = 'Vous avez quitté la réunion'}) async {
    if (_closed) return;
    _closed = true;
    _roomSub?.cancel();
    _peersSub?.cancel();
    _linksSub?.cancel();
    try {
      await ref.collection('peers').doc(me).set({'active': false}, SetOptions(merge: true));
    } catch (_) {}
    if (isHost) {
      try {
        await ref.update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
      NotifyService.roomEnded(roomId: roomId);
      try {
        final chatId = ((await ref.get()).data()?['chatId'] ?? '') as String;
        if (chatId.isNotEmpty) {
          await TeamService.chats.doc(chatId).update({'activeRoom': ''});
        }
      } catch (_) {}
    }
    for (final id in peers.keys.toList()) {
      _closePeer(id);
    }
    try {
      for (final t in local?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await local?.dispose();
    } catch (_) {}
    localRenderer.srcObject = null;
    Future.delayed(const Duration(milliseconds: 600), localRenderer.dispose);
    AichaMedia.cancelIncomingCall().catchError((_) {});
    if (RoomService.current == this) RoomService.current = null;
    ended.value = reason;
  }
}
