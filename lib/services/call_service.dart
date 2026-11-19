import 'dart:async';

import 'package:aicha_media/aicha_media.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/app_user.dart';
import '../nav.dart';
import '../screens/call_screen.dart';
import 'db.dart';
import 'notify_service.dart';
import 'session.dart';

/// Appels audio par internet entre un client et l'équipe d'une boutique.
///
/// calls/{id} : callerId, callerName, callerRole ('client' | 'shop'),
///   clientId, clientName, shopId, conversationId, status
///   ('ringing' | 'accepted' | 'ended' | 'declined' | 'missed'),
///   answeredBy, answeredByName, offer, answer, createdAt
/// calls/{id}/candidates/{x} : from ('caller' | 'callee'), candidate…
class CallService {
  static final _fs = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get calls =>
      _fs.collection('calls');

  /// L'appel en cours (un seul à la fois).
  static ActiveCall? current;

  // ---------- Appels entrants ----------
  static StreamSubscription? _incomingSub;
  static String _watchKey = '';
  static final Set<String> _shown = {};

  // ---------- Présence de l'équipe (en ligne / hors ligne) ----------
  static CollectionReference<Map<String, dynamic>> get presence =>
      _fs.collection('presence');
  static Timer? _presenceTimer;
  static String _presenceUid = '';
  static _Lifecycle? _life;

  static void _startPresence(Session s) {
    if (!s.canManage || _presenceUid == s.uid) return;
    _presenceUid = s.uid;
    final shopId = s.staff?.shopId ?? 'main';
    void beat(bool online) {
      presence.doc(s.uid).set({
        'online': online,
        'shopId': shopId,
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }
    beat(true);
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) => beat(true));
    _life ??= _Lifecycle((fg) => beat(fg));
    WidgetsBinding.instance.addObserver(_life!);
  }

  /// L'agent a-t-il eu l'application ouverte il y a moins de 2 minutes ?
  static Future<bool> _isOnline(String uid) async {
    try {
      final d = (await presence.doc(uid).get().timeout(const Duration(seconds: 4))).data();
      if (d == null || d['online'] != true) return false;
      final at = d['lastSeen'];
      return at is Timestamp &&
          DateTime.now().difference(at.toDate()) < const Duration(minutes: 2);
    } catch (_) {
      return true; // dans le doute, on fait sonner l'agent d'abord
    }
  }

  /// À appeler à chaque mise à jour de la session.
  static void watch(Session s) {
    _startPresence(s);
    final String key;
    Query<Map<String, dynamic>> q;
    if (s.isSuper) {
      key = 'super_${s.uid}';
      q = calls
          .where('status', isEqualTo: 'ringing')
          .where('callerRole', isEqualTo: 'client');
    } else if (s.isStaff) {
      key = 'staff_${s.uid}_${s.staff!.shopId}';
      q = calls
          .where('shopId', isEqualTo: s.staff!.shopId)
          .where('status', isEqualTo: 'ringing')
          .where('callerRole', isEqualTo: 'client');
    } else {
      key = 'client_${s.uid}';
      q = calls
          .where('clientId', isEqualTo: s.uid)
          .where('status', isEqualTo: 'ringing')
          .where('callerRole', isEqualTo: 'shop');
    }
    if (key == _watchKey) return;
    _watchKey = key;
    _incomingSub?.cancel();
    final me = s.me;
    final myName = s.canManage ? s.teamName(s.staff?.shopId ?? 'main') : me.name;
    _incomingSub = q.snapshots().listen((snap) {
      for (final d in snap.docs) {
        final data = d.data();
        if (data['callerId'] == s.uid) continue;
        // Discussion attribuée à un agent : seul lui (et le responsable) sonne.
        final callee = (data['calleeId'] ?? '') as String;
        // Le Super Admin (qui fait aussi office de responsable) sonne pour tous.
        if (s.canManage && !s.isSuper && callee.isNotEmpty && callee != s.uid) {
          final manager = s.agentUid == null;
          if (!manager) continue;
        }
        if (_shown.contains(d.id)) continue;
        if (current != null) {
          // Déjà en communication : l'appelant entend « occupé ».
          final forMe = !s.canManage || callee == s.uid;
          if (forMe) {
            _shown.add(d.id);
            d.reference.update({'status': 'busy'}).catchError((_) {});
          }
          continue;
        }
        final at = data['createdAt'];
        if (at is Timestamp &&
            DateTime.now().difference(at.toDate()) > const Duration(seconds: 60)) {
          continue;
        }
        _shown.add(d.id);
        _showIncoming(d.id, data, me.uid, myName, me.name);
      }
    }, onError: (_) {});
  }

  static void stopWatching() {
    _incomingSub?.cancel();
    _incomingSub = null;
    _watchKey = '';
  }

  static void _showIncoming(String id, Map<String, dynamic> data,
      String myUid, String myName, String personName) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    AichaMedia.cancelIncomingCall().catchError((_) {});
    AichaMedia.showOnLock(true).catchError((_) {});
    AichaMedia.ring();
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen.incoming(
        callId: id,
        otherName: (data['callerName'] ?? 'Appel') as String,
        myUid: myUid,
        myName: myName,
        personName: personName,
        teamCall: data['callerRole'] == 'client',
      ),
    ));
  }

  /// Ouvre l'écran d'appel sortant (client → équipe ou équipe → client).
  static void openCall(
    BuildContext context, {
    required String conversationId,
    required Map<String, dynamic> createIfMissing,
    required bool asShop,
    required String shopId,
    required String otherName,
    required AppUser me,
  }) {
    if (current != null) return;
    final session = sessionOf(context, listen: false);
    final myName = asShop ? session.teamName(shopId) : me.name;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen.outgoing(
        otherName: otherName,
        myUid: me.uid,
        myName: myName,
        startCall: () => start(
          myUid: me.uid,
          myName: myName,
          personName: me.name,
          asShop: asShop,
          shopId: shopId,
          conversationId: conversationId,
          createIfMissing: createIfMissing,
          otherName: otherName,
        ),
      ),
    ));
  }

  // ---------- Lancer un appel ----------
  static Future<ActiveCall> start({
    required String myUid,
    required String myName,
    String personName = '',
    required bool asShop,
    required String shopId,
    required String conversationId,
    required Map<String, dynamic> createIfMissing,
    required String otherName,
  }) async {
    var clientId = asShop ? (createIfMissing['clientId'] ?? '') as String : myUid;
    var clientName = asShop ? otherName : myName;
    if (asShop && clientId.isEmpty) {
      final c = await Db.conversations.doc(conversationId).get();
      clientId = (c.data()?['clientId'] ?? '') as String;
      clientName = (c.data()?['clientName'] ?? otherName) as String;
    }
    if (clientId.isEmpty) throw Exception('Client introuvable.');
    // Agent responsable de la discussion (c'est lui qui sonne en premier).
    // S'il n'est pas en ligne, l'appel va directement à toute l'équipe.
    var calleeId = '';
    if (!asShop) {
      try {
        final c = await Db.conversations.doc(conversationId).get();
        calleeId = (c.data()?['assignedTo'] ?? '') as String;
      } catch (_) {}
      if (calleeId.isNotEmpty && !await _isOnline(calleeId)) calleeId = '';
    }
    final ref = calls.doc();
    final call = ActiveCall._(ref, isCaller: true, myUid: myUid, myName: myName)
      ..otherName = otherName
      ..conversationId = conversationId
      ..createIfMissing = createIfMissing
      ..asShop = asShop;
    current = call;
    try {
      await call._open();
      final offer = lowBandwidth(
          await call._pc!.createOffer({'offerToReceiveAudio': true}));
      await call._pc!.setLocalDescription(offer);
      await ref.set({
        'callerId': myUid,
        'callerName': myName,
        'callerRole': asShop ? 'shop' : 'client',
        'clientId': clientId,
        'clientName': clientName,
        'shopId': shopId,
        'conversationId': conversationId,
        'calleeId': calleeId,
        'callerPerson': personName,
        'status': 'ringing',
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'createdAt': FieldValue.serverTimestamp(),
      });
      call._docReady();
      call._listen();
      // Faire sonner le téléphone appelé même si l'application y est fermée.
      NotifyService.incomingCall(callId: ref.id);
      // Pas de réponse de l'agent en 15 s : l'appel passe à toute l'équipe.
      if (calleeId.isNotEmpty) {
        call._escalate = Timer(const Duration(seconds: 15), () {
          if (call.state.value == CallState.ringing) {
            ref.update({'calleeId': '', 'escalated': true}).then((_) {
              NotifyService.incomingCall(callId: ref.id);
            }).catchError((_) {});
          }
        });
      }
      call._timeout = Timer(const Duration(seconds: 50), () {
        if (call.state.value == CallState.ringing) {
          call._finish('missed', reason: 'Pas de réponse');
        }
      });
    } catch (e) {
      await call._cleanup();
      rethrow;
    }
    return call;
  }

  /// Décrocher un appel entrant.
  static Future<ActiveCall?> answer(String callId, String myUid, String myName,
      {String personName = ''}) async {
    final ref = calls.doc(callId);
    final ok = await _fs.runTransaction<bool>((t) async {
      final d = await t.get(ref);
      if (d.data()?['status'] != 'ringing') return false;
      t.update(ref, {
        'status': 'accepted',
        'answeredBy': myUid,
        'answeredByName': myName,
        'answeredAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!ok) return null;
    final snap = await ref.get();
    final data = snap.data() ?? {};
    // L'agent qui décroche prend la discussion si elle est encore libre.
    final convId = (data['conversationId'] ?? '') as String;
    if (data['callerRole'] == 'client' && convId.isNotEmpty) {
      try {
        final cref = Db.conversations.doc(convId);
        final c = await cref.get();
        if (c.exists && ((c.data()?['assignedTo'] ?? '') as String).isEmpty) {
          await cref.update({
            'assignedTo': myUid,
            'assignedName': personName.isEmpty ? myName : personName,
          });
        }
      } catch (_) {}
    }
    final call = ActiveCall._(ref, isCaller: false, myUid: myUid, myName: myName)
      ..otherName = (data['callerName'] ?? '') as String;
    current = call;
    try {
      await call._open();
      final offer = data['offer'] as Map<String, dynamic>;
      await call._pc!.setRemoteDescription(
          RTCSessionDescription(offer['sdp'] as String, offer['type'] as String));
      final answer = lowBandwidth(
          await call._pc!.createAnswer({'offerToReceiveAudio': true}));
      await call._pc!.setLocalDescription(answer);
      await ref.update({'answer': {'sdp': answer.sdp, 'type': answer.type}});
      call._docReady();
      call._listen();
      call.state.value = CallState.connecting;
      call._watchConnect();
      // Arrêter la sonnerie chez les collègues.
      NotifyService.callEnded(callId: callId);
    } catch (e) {
      await call._finish('ended');
      rethrow;
    }
    return call;
  }

  static Future<void> decline(String callId) async {
    await AichaMedia.stopRing();
    AichaMedia.cancelIncomingCall().catchError((_) {});
    try {
      // Refus seulement si personne n'a encore décroché.
      final ok = await _fs.runTransaction<bool>((t) async {
        final d = await t.get(calls.doc(callId));
        if (d.data()?['status'] != 'ringing') return false;
        t.update(calls.doc(callId), {'status': 'declined'});
        return true;
      });
      if (ok) NotifyService.callEnded(callId: callId);
    } catch (_) {}
  }

  /// Réglages audio pour les connexions faibles : débit réduit (24 kb/s),
  /// correction des pertes (FEC) et silence non transmis (DTX).
  static RTCSessionDescription lowBandwidth(RTCSessionDescription d) {
    var sdp = d.sdp ?? '';
    final m = RegExp(r'a=rtpmap:(\d+) opus/48000[^\r\n]*').firstMatch(sdp);
    if (m != null) {
      final pt = m.group(1)!;
      final fmtp = RegExp('a=fmtp:$pt ([^\r\n]*)');
      const extra = 'useinbandfec=1;usedtx=1;maxaveragebitrate=24000';
      if (fmtp.hasMatch(sdp)) {
        sdp = sdp.replaceFirstMapped(fmtp, (x) {
          final params = x.group(1)!
              .split(';')
              .where((p) =>
                  !p.startsWith('useinbandfec') &&
                  !p.startsWith('usedtx') &&
                  !p.startsWith('maxaveragebitrate'))
              .join(';');
          return 'a=fmtp:$pt ${params.isEmpty ? '' : '$params;'}$extra';
        });
      } else {
        sdp = sdp.replaceFirst(m.group(0)!, '${m.group(0)}\r\na=fmtp:$pt $extra');
      }
    }
    return RTCSessionDescription(sdp, d.type);
  }

  /// Serveurs pour traverser les réseaux (STUN gratuit de Google + TURN
  /// optionnel enregistré dans settings/shop : turnUrl, turnUser, turnPass).
  static Future<List<Map<String, dynamic>>> _iceServers() async {
    final servers = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
    ];
    try {
      final s = (await Db.settingsDoc.get()).data() ?? {};
      final url = (s['turnUrl'] ?? '') as String;
      if (url.isNotEmpty) {
        servers.add({
          'urls': url.split(',').map((e) => e.trim()).toList(),
          'username': (s['turnUser'] ?? '') as String,
          'credential': (s['turnPass'] ?? '') as String,
        });
      }
    } catch (_) {}
    return servers;
  }
}

enum CallState { ringing, connecting, connected, ended }

class ActiveCall {
  final DocumentReference<Map<String, dynamic>> ref;
  final bool isCaller;
  final String myUid;
  final String myName;
  String otherName = '';
  String conversationId = '';
  Map<String, dynamic> createIfMissing = const {};
  bool asShop = false;

  final state = ValueNotifier<CallState>(CallState.ringing);
  final ended = ValueNotifier<String>(''); // raison de fin
  DateTime? connectedAt;
  bool muted = false;
  bool speaker = false;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  StreamSubscription? _docSub;
  StreamSubscription? _candSub;
  Timer? _timeout;
  Timer? _escalate;
  bool _ready = false;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pendingOut = [];
  final List<RTCIceCandidate> _pendingIn = [];
  bool _closed = false;

  ActiveCall._(this.ref,
      {required this.isCaller, required this.myUid, required this.myName});

  String get _side => isCaller ? 'caller' : 'callee';

  Future<void> _open() async {
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    _pc = await createPeerConnection({
      'iceServers': await CallService._iceServers(),
      'sdpSemantics': 'unified-plan',
    });
    for (final t in _local!.getAudioTracks()) {
      await _pc!.addTrack(t, _local!);
    }
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      if (_ready) {
        _sendCandidate(c);
      } else {
        _pendingOut.add(c);
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        connectedAt ??= DateTime.now();
        state.value = CallState.connected;
        Helper.setSpeakerphoneOn(speaker);
        _lostTimer?.cancel();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _finish('failed', reason: _failText);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // Coupure réseau : on laisse 12 s pour que la connexion revienne.
        _lostTimer?.cancel();
        _lostTimer = Timer(const Duration(seconds: 20), () {
          if (state.value != CallState.ended) {
            _finish(connectedAt == null ? 'failed' : 'ended',
                reason: 'Connexion perdue. Vérifiez votre connexion Internet.');
          }
        });
      }
    };
  }

  static const _failText =
      'Impossible de connecter l\'appel. Vérifiez votre connexion Internet.';
  Timer? _connectTimer;
  Timer? _lostTimer;

  /// Décroché mais pas connecté au bout de 30 s : appel impossible.
  void _watchConnect() {
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 45), () {
      if (state.value != CallState.connected && state.value != CallState.ended) {
        _finish('failed', reason: _failText);
      }
    });
  }

  void _docReady() {
    _ready = true;
    for (final c in _pendingOut) {
      _sendCandidate(c);
    }
    _pendingOut.clear();
  }

  void _sendCandidate(RTCIceCandidate c) {
    ref.collection('candidates').add({
      'from': _side,
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    }).catchError((_) => ref);
  }

  void _listen() {
    _docSub = ref.snapshots().listen((d) async {
      final data = d.data();
      if (data == null) return;
      final status = data['status'];
      if (isCaller && status == 'accepted' && !_remoteSet && data['answer'] != null) {
        final a = data['answer'] as Map<String, dynamic>;
        _remoteSet = true;
        _timeout?.cancel();
        _escalate?.cancel();
        otherName = (data['answeredByName'] ?? otherName) as String;
        state.value = CallState.connecting;
        _watchConnect();
        await _pc?.setRemoteDescription(
            RTCSessionDescription(a['sdp'] as String, a['type'] as String));
        for (final c in _pendingIn) {
          await _pc?.addCandidate(c);
        }
        _pendingIn.clear();
      }
      if (!isCaller && !_remoteSet) {
        _remoteSet = true;
      }
      if (status == 'declined') {
        _finish('declined', reason: 'Appel refusé', write: false);
      } else if (status == 'busy') {
        _finish('busy',
            reason: 'Votre correspondant est déjà en communication.', write: false);
      } else if (status == 'ended' ||
          status == 'missed' ||
          status == 'cancelled' ||
          status == 'failed') {
        _finish(status as String,
            reason: status == 'missed'
                ? 'Pas de réponse'
                : status == 'cancelled'
                    ? 'Appel annulé'
                    : status == 'failed'
                        ? _failText
                        : 'Appel terminé',
            write: false);
      }
    });
    _candSub = ref
        .collection('candidates')
        .where('from', isEqualTo: isCaller ? 'callee' : 'caller')
        .snapshots()
        .listen((snap) async {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final m = ch.doc.data() ?? {};
        final c = RTCIceCandidate(m['candidate'] as String?,
            m['sdpMid'] as String?, (m['sdpMLineIndex'] as num?)?.toInt());
        if (_remoteSet || !isCaller) {
          try {
            await _pc?.addCandidate(c);
          } catch (_) {}
        } else {
          _pendingIn.add(c);
        }
      }
    });
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  void toggleSpeaker() {
    speaker = !speaker;
    Helper.setSpeakerphoneOn(speaker);
  }

  Future<void> hangUp() => state.value == CallState.ringing && isCaller
      ? _finish('cancelled', reason: 'Appel annulé')
      : _finish('ended', reason: 'Appel terminé');

  Future<void> _finish(String status, {String reason = '', bool write = true}) async {
    if (_closed) return;
    _closed = true;
    _timeout?.cancel();
    _escalate?.cancel();
    _connectTimer?.cancel();
    _lostTimer?.cancel();
    final d = connectedAt == null ? null : DateTime.now().difference(connectedAt!);
    if (write) {
      try {
        await ref.update({'status': status, 'endedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
    // Arrêter les sonneries restantes (téléphones fermés).
    if (write) NotifyService.callEnded(callId: ref.id);
    // Trace dans la discussion (écrite par l'appelant, visible des deux côtés).
    if (isCaller && conversationId.isNotEmpty) {
      final text = d != null
          ? '📞 Appel terminé · ${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}'
          : switch (status) {
              'declined' => '📞 Appel refusé',
              'cancelled' => '📞 Appel annulé',
              'failed' => '📞 Appel impossible',
              'busy' => '📞 Correspondant occupé',
              _ => '📞 Appel manqué',
            };
      try {
        await Db.sendMessage(
          conversationId: conversationId,
          createIfMissing: createIfMissing,
          senderId: myUid,
          senderRole: asShop ? 'shop' : 'client',
          senderName: myName,
          text: text,
          type: 'system',
          notify: d == null,
        );
      } catch (_) {}
    }
    ended.value = reason.isEmpty ? 'Appel terminé' : reason;
    state.value = CallState.ended;
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _closed = true;
    _timeout?.cancel();
    _connectTimer?.cancel();
    _lostTimer?.cancel();
    AichaMedia.showOnLock(false).catchError((_) {});
    await _docSub?.cancel();
    await _candSub?.cancel();
    try {
      for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _local?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _local = null;
    if (CallService.current == this) CallService.current = null;
  }
}

/// Suit l'ouverture / la fermeture de l'application (présence de l'équipe).
class _Lifecycle with WidgetsBindingObserver {
  final void Function(bool foreground) onChange;
  _Lifecycle(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onChange(true);
    if (state == AppLifecycleState.paused) onChange(false);
  }
}
