import 'dart:async';

import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/call_service.dart';
import '../services/mic.dart';

/// Écran d'appel (sortant ou entrant), plein écran.
class CallScreen extends StatefulWidget {
  final String otherName;
  final String myUid;
  final String myName;
  final String personName;
  final bool teamCall; // appel d'un client vers l'équipe (plusieurs téléphones sonnent)
  final bool autoAnswer; // « Répondre » touché sur l'écran d'appel d'Android
  // Appel sortant
  final Future<ActiveCall> Function()? startCall;
  // Appel entrant
  final String callId;

  const CallScreen.outgoing({
    super.key,
    required this.otherName,
    required this.myUid,
    required this.myName,
    required Future<ActiveCall> Function() this.startCall,
  })  : callId = '',
        personName = '',
        teamCall = false,
        autoAnswer = false;

  const CallScreen.incoming({
    super.key,
    required this.callId,
    required this.otherName,
    required this.myUid,
    required this.myName,
    this.personName = '',
    this.teamCall = false,
    this.autoAnswer = false,
  }) : startCall = null;

  bool get isIncoming => startCall == null;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  ActiveCall? _call;
  String _status = '';
  bool _waitingAnswer = false; // appel entrant pas encore décroché
  bool _busy = false;
  bool _answering = false;
  Timer? _tick;
  StreamSubscription? _incomingSub;

  @override
  void initState() {
    super.initState();
    if (widget.isIncoming) {
      _waitingAnswer = true;
      _status = 'Appel entrant…';
      // Si l'appelant raccroche ou qu'un collègue décroche avant nous.
      _incomingSub = CallService.calls.doc(widget.callId).snapshots().listen((d) {
        final s = d.data()?['status'];
        if (_waitingAnswer && !_answering && s != null && s != 'ringing') {
          // Un collègue a décroché (ou l'appelant a raccroché) : on arrête
          // seulement la sonnerie ici, sans rien envoyer.
          _waitingAnswer = false;
          AichaMedia.stopRing();
          _close(s == 'accepted' ? 'Un collègue a répondu' : 'Appel manqué');
        }
      });
      if (widget.autoAnswer || CallService.pendingAnswer.value == widget.callId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _accept();
        });
      }
      // « Répondre » touché plus tard sur l'écran d'appel d'Android.
      CallService.pendingAnswer.addListener(_onPendingAnswer);
    } else {
      _status = 'Appel…';
      _startOutgoing();
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _startOutgoing() async {
    if (!await ensureMic(context)) {
      _close('Microphone non autorisé');
      return;
    }
    if (!mounted) return;
    setState(() => _status = 'Appel…');
    try {
      final c = await widget.startCall!();
      if (!mounted || _closing) {
        c.hangUp();
        return;
      }
      _attach(c);
    } catch (e) {
      _close('Appel impossible : ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _attach(ActiveCall c) {
    _call = c;
    c.state.addListener(_onState);
    _onState();
  }

  void _onState() {
    final c = _call;
    if (c == null || !mounted) return;
    switch (c.state.value) {
      case CallState.ringing:
        _status = 'Sonnerie…';
        if (c.isCaller && !_toneOn) {
          _toneOn = true;
          AichaMedia.ringback().catchError((_) {});
        }
        break;
      case CallState.connecting:
        _status = 'Connexion…';
        _stopTone();
        break;
      case CallState.connected:
        _status = '';
        _stopTone();
        break;
      case CallState.ended:
        _stopTone();
        final r = c.ended.value;
        if (c.isCaller && (r.contains('refusé') || r.contains('communication'))) {
          AichaMedia.busyTone().catchError((_) {});
        }
        _close(r);
        return;
    }
    setState(() {});
  }

  bool _toneOn = false;
  void _stopTone() {
    if (!_toneOn) return;
    _toneOn = false;
    AichaMedia.stopTone().catchError((_) {});
  }

  bool _closing = false;
  void _close(String message) {
    if (_closing) return;
    _closing = true;
    if (mounted) setState(() => _status = message);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _onPendingAnswer() {
    if (CallService.pendingAnswer.value == widget.callId && _waitingAnswer && mounted) {
      _accept();
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    if (CallService.pendingAnswer.value == widget.callId) {
      CallService.pendingAnswer.value = '';
    }
    setState(() => _busy = true);
    await AichaMedia.stopRing();
    if (!await ensureMic(context)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    _answering = true;
    try {
      final c = await CallService.answer(widget.callId, widget.myUid, widget.myName,
          personName: widget.personName);
      if (c == null) {
        _waitingAnswer = false;
        _close('Appel déjà terminé');
        return;
      }
      _waitingAnswer = false;
      _attach(c);
    } catch (e) {
      _close('Appel impossible : ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    _waitingAnswer = false;
    if (widget.teamCall) {
      // Appel adressé à toute l'équipe : seule ma sonnerie s'arrête,
      // l'appel continue de sonner chez mes collègues.
      await AichaMedia.stopRing();
      AichaMedia.cancelIncomingCall().catchError((_) {});
      _close('Vous avez ignoré cet appel');
      return;
    }
    await CallService.decline(widget.callId);
    _close('Appel refusé');
  }

  @override
  void dispose() {
    CallService.pendingAnswer.removeListener(_onPendingAnswer);
    _tick?.cancel();
    _incomingSub?.cancel();
    _call?.state.removeListener(_onState);
    AichaMedia.stopRing();
    if (_toneOn) AichaMedia.stopTone().catchError((_) {});
    AichaMedia.showOnLock(false).catchError((_) {});
    if (_waitingAnswer && !widget.teamCall) CallService.decline(widget.callId);
    final c = _call;
    if (c != null && c.state.value != CallState.ended) c.hangUp();
    super.dispose();
  }

  String get _timer {
    final at = _call?.connectedAt;
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    return '${d.inMinutes.toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _call;
    final name = (c?.otherName.isNotEmpty ?? false) ? c!.otherName : widget.otherName;
    return PopScope(
      canPop: _closing || (_call == null && !_waitingAnswer),
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (!didPop && !_closing) {
          if (_waitingAnswer) {
            _decline();
          } else {
            _call?.hangUp();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F2A0A),
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 60),
            CircleAvatar(
              radius: 56,
              backgroundColor: Colors.white,
              child: ClipOval(
                  child: Image.asset(AppConfig.logo, width: 96, height: 96)),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            Text(_status.isNotEmpty ? _status : _timer,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 17)),
            const SizedBox(height: 6),
            Text(
                _call?.state.value == CallState.connected
                    ? 'Connecté • appel par internet'
                    : 'Appel vocal • Aïcha Services',
                style: TextStyle(color: Colors.white38, fontSize: 12.5)),
            const Spacer(),
            if (_waitingAnswer)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _round(Icons.call_end, Colors.red, 'Refuser', _decline),
                _round(Icons.call, AppConfig.lightGreen, 'Répondre',
                    _busy ? null : _accept),
              ])
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _round(
                    c?.muted ?? false ? Icons.mic_off : Icons.mic,
                    c?.muted ?? false ? Colors.white : Colors.white24,
                    'Micro',
                    c == null
                        ? null
                        : () => setState(() => c.toggleMute()),
                    iconColor: c?.muted ?? false ? Colors.black : Colors.white),
                _round(Icons.call_end, Colors.red, 'Raccrocher',
                    () => c == null ? _close('Appel annulé') : c.hangUp()),
                _round(
                    Icons.volume_up,
                    c?.speaker ?? false ? Colors.white : Colors.white24,
                    'Haut-parleur',
                    c == null
                        ? null
                        : () => setState(() => c.toggleSpeaker()),
                    iconColor: c?.speaker ?? false ? Colors.black : Colors.white),
              ]),
            const SizedBox(height: 56),
          ]),
        ),
      ),
    );
  }

  Widget _round(IconData icon, Color bg, String label, VoidCallback? onTap,
      {Color iconColor = Colors.white}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 72, height: 72, child: Icon(icon, color: iconColor, size: 32)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70)),
    ]);
  }
}
