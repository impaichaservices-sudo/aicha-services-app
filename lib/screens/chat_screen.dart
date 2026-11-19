import 'dart:async';
import 'dart:io';

import 'package:aicha_media/aicha_media.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/catalog_item.dart';
import '../models/chat.dart';
import '../services/call_service.dart';
import '../services/db.dart';
import '../services/file_service.dart';
import '../services/mic.dart';
import '../services/session.dart';
import '../utils.dart';
import '../widgets/item_card.dart';
import '../widgets/product_image.dart';

/// Discussion entre un client et l'équipe (même écran des deux côtés).
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic> createIfMissing;
  final String title;
  final String? subtitle;
  final bool asShop; // true = l'équipe AÏCHA SERVICES écrit
  final AppUser me;
  final String initialText;
  final String clientPhone; // côté équipe : pour appeler / WhatsApp
  final String shopId;
  final String orderId;
  final CatalogItem? aboutItem; // article joint au premier message du client

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.createIfMissing,
    required this.title,
    this.subtitle,
    required this.asShop,
    required this.me,
    this.initialText = '',
    this.clientPhone = '',
    this.shopId = 'main',
    this.orderId = '',
    this.aboutItem,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  late final Stream<List<ChatMessage>> _messages =
      Db.messages(widget.conversationId);
  late final Stream<Conversation?> _conv =
      Db.conversationStream(widget.conversationId);
  final _scroll = ScrollController();
  String _lastSeen = '';
  bool _sending = false;
  late CatalogItem? _about = widget.aboutItem;

  // Message vocal en cours d'enregistrement
  bool _recording = false;
  String _recPath = '';
  DateTime _recStart = DateTime.now();
  Timer? _recTimer;
  static const _maxRecord = Duration(minutes: 3);
  // Aperçu du vocal avant envoi (écouter / supprimer / envoyer)
  String _previewPath = '';
  Duration _previewLen = Duration.zero;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    Db.markRead(widget.conversationId, asShop: widget.asShop);
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    if (_recording) AichaMedia.stop();
    if (_previewPath.isNotEmpty) {
      try {
        final f = File(_previewPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    AichaMedia.stopPlay();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({
    String type = 'text',
    String? text,
    CatalogItem? item,
  }) async {
    var body = (text ?? _text.text).trim();
    final about = _about;
    if (type == 'text' && body.isEmpty && about == null) return;
    if (type == 'text') _text.clear();
    if (type == 'text' && about != null) {
      // Le message part avec la fiche de l'article (photo, nom, prix).
      type = 'service';
      item = about;
      if (body.isEmpty) body = 'Je voudrais des informations sur cet article.';
      setState(() => _about = null);
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Hors connexion, le message s'affiche avec 🕓 et part tout seul ensuite.
      await Db.sendMessage(
        conversationId: widget.conversationId,
        createIfMissing: widget.createIfMissing,
        senderId: widget.me.uid,
        senderRole: widget.asShop ? 'shop' : 'client',
        senderName: widget.asShop
            ? sessionOf(context, listen: false).teamName(widget.shopId)
            : widget.me.name,
        text: body,
        type: type,
        itemId: item?.id ?? '',
        itemName: item?.name ?? '',
        agentName: widget.me.name,
      );
    } catch (e) {
      if (type == 'text' && _text.text.isEmpty) _text.text = body;
      messenger.showSnackBar(SnackBar(
          content: Text('Message non envoyé. Vérifiez votre connexion Internet. (${_err(e)})')));
    }
  }

  void _onNewMessages(List<ChatMessage> list) {
    if (list.isEmpty || list.last.id == _lastSeen) return;
    _lastSeen = list.last.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
    final fromOther = widget.asShop ? !list.last.fromShop : list.last.fromShop;
    if (fromOther) Db.markRead(widget.conversationId, asShop: widget.asShop);
  }

  String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// Envoie un fichier déjà prêt (document, photo, vidéo, vocal).
  Future<void> _sendUpload(Future<PickedUpload?> Function() make,
      {String label = ''}) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final up = await make();
      if (up == null) return;
      if (!mounted) return;
      await Db.sendMessage(
        conversationId: widget.conversationId,
        createIfMissing: widget.createIfMissing,
        senderId: widget.me.uid,
        senderRole: widget.asShop ? 'shop' : 'client',
        senderName: widget.asShop
            ? sessionOf(context, listen: false).teamName(widget.shopId)
            : widget.me.name,
        text: label,
        type: 'file',
        fileUrl: up.url,
        fileName: up.name,
        agentName: widget.me.name,
      );
      await Db.addFile({
        'ownerId': widget.me.uid,
        'shopId': widget.shopId,
        'conversationId': widget.conversationId,
        'orderId': widget.orderId,
        'name': up.name,
        'url': up.url,
        'size': up.size,
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_err(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _uploadFile() => _sendUpload(() => FileService.pickAndUpload(
      shopId: widget.shopId, conversationId: widget.conversationId));

  String get _stamp => DateTime.now().millisecondsSinceEpoch.toString();

  /// Photo ou vidéo : appareil photo ou galerie.
  void _media({required bool video, required ImageSource source}) {
    _sendUpload(() async {
      final picker = ImagePicker();
      final x = video
          ? await picker.pickVideo(
              source: source, maxDuration: const Duration(seconds: 30))
          : await picker.pickImage(
              source: source, imageQuality: 70, maxWidth: 1600, maxHeight: 1600);
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      var ext = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : '';
      if (ext.isEmpty) ext = video ? 'mp4' : 'jpg';
      return FileService.uploadBytes(
        bytes: bytes,
        name: '${video ? 'video' : 'photo'}_$_stamp.$ext',
        shopId: widget.shopId,
        conversationId: widget.conversationId,
      );
    }, label: video ? '🎬 Vidéo' : '📷 Photo');
  }

  // ---------- Message vocal ----------
  String _dur(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _startRecording() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await ensureMic(context, usage: 'enregistrer un message vocal')) {
        return;
      }
      final dir = await getTemporaryDirectory();
      _recPath = '${dir.path}/vocal_$_stamp.m4a';
      await AichaMedia.stopPlay();
      await AichaMedia.start(_recPath);
      _recStart = DateTime.now();
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        if (DateTime.now().difference(_recStart) >= _maxRecord) {
          _stopRecording(send: true);
        } else {
          setState(() {});
        }
      });
      setState(() => _recording = true);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Micro indisponible : ${_err(e)}')));
    }
  }

  /// mode : 'send' (envoyer tout de suite), 'preview' (écouter avant),
  /// 'cancel' (supprimer).
  Future<void> _stopRecording({required bool send, bool preview = false}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    final length = DateTime.now().difference(_recStart);
    setState(() => _recording = false);
    final ok = await AichaMedia.stop();
    final file = File(_recPath);
    if ((!send && !preview) || !ok || length < const Duration(seconds: 1)) {
      if (await file.exists()) await file.delete();
      if ((send || preview) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Message trop court : appuyez sur 🎤 et parlez.')));
      }
      return;
    }
    if (preview) {
      setState(() {
        _previewPath = _recPath;
        _previewLen = length;
      });
      return;
    }
    await _sendVoice(_recPath, length);
  }

  Future<void> _sendVoice(String path, Duration length) async {
    final file = File(path);
    await _sendUpload(() async {
      final bytes = await file.readAsBytes();
      final up = await FileService.uploadBytes(
        bytes: bytes,
        name: 'vocal_$_stamp.m4a',
        shopId: widget.shopId,
        conversationId: widget.conversationId,
      );
      if (await file.exists()) await file.delete();
      return up;
    }, label: '🎤 Message vocal (${_dur(length)})');
  }

  Future<void> _togglePreview() async {
    if (_previewPlaying) {
      await AichaMedia.stopPlay();
      return;
    }
    await AichaMedia.play(_previewPath, onDone: () {
      if (mounted) setState(() => _previewPlaying = false);
    });
    setState(() => _previewPlaying = true);
  }

  Future<void> _closePreview({required bool send}) async {
    final path = _previewPath;
    final len = _previewLen;
    await AichaMedia.stopPlay();
    setState(() {
      _previewPath = '';
      _previewPlaying = false;
    });
    if (send) {
      await _sendVoice(path, len);
    } else {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> _openFile(ChatMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2), content: Text('Téléchargement…')));
    try {
      await FileService.open(m.fileUrl, m.fileName);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  List<Widget> _mediaTiles(BuildContext ctx) {
    Widget tile(IconData icon, String title, String? sub, VoidCallback go) =>
        ListTile(
          leading: Icon(icon, color: AppConfig.green),
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          onTap: () {
            Navigator.pop(ctx);
            go();
          },
        );
    return [
      tile(Icons.photo_camera, 'Prendre une photo', null,
          () => _media(video: false, source: ImageSource.camera)),
      tile(Icons.videocam, 'Filmer une vidéo', '30 secondes maximum',
          () => _media(video: true, source: ImageSource.camera)),
      tile(Icons.photo_library, 'Photo de la galerie', null,
          () => _media(video: false, source: ImageSource.gallery)),
      tile(Icons.video_library, 'Vidéo de la galerie', '15 Mo maximum',
          () => _media(video: true, source: ImageSource.gallery)),
      tile(Icons.upload_file, 'Document', 'PDF, Word, Excel… (15 Mo max.)',
          _uploadFile),
    ];
  }

  Future<void> _attach() async {
    if (_recording) return;
    final filesOn = await FileService.enabled();
    if (!mounted) return;
    if (widget.asShop) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
           child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (filesOn) ..._mediaTiles(ctx),
            ListTile(
              leading: const Icon(Icons.forward_to_inbox, color: AppConfig.green),
              title: const Text('Transférer la discussion'),
              subtitle: const Text('À un collègue ou au superviseur'),
              onTap: () {
                Navigator.pop(ctx);
                _transfer();
              },
            ),
            ListTile(
              leading: const Icon(Icons.design_services, color: AppConfig.green),
              title: const Text('Proposer un service'),
              subtitle: const Text('Le client pourra le commander en un clic'),
              onTap: () {
                Navigator.pop(ctx);
                _pickService();
              },
            ),
            if (widget.clientPhone.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.call, color: AppConfig.green),
                title: const Text('Appeler le client'),
                onTap: () => launchUrl(Uri.parse('tel:${widget.clientPhone}')),
              ),
              ListTile(
                leading: const Icon(Icons.chat, color: AppConfig.green),
                title: const Text('Écrire sur WhatsApp'),
                onTap: () => launchUrl(whatsappUri(widget.clientPhone),
                    mode: LaunchMode.externalApplication),
              ),
            ],
           ]),
          ),
        ),
      );
      return;
    }
    // Côté client : fichier dans l'appli (si activé) ou par WhatsApp.
    final contact = sessionOf(context, listen: false).shopById(widget.shopId).contact;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
         child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (filesOn) ..._mediaTiles(ctx),
          ListTile(
            leading: const Icon(Icons.chat, color: AppConfig.green),
            title: const Text('Envoyer par WhatsApp'),
            subtitle: const Text('Pour les fichiers plus lourds'),
            enabled: contact.isNotEmpty,
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(
                whatsappUri(contact,
                    'Bonjour ${AppConfig.shopName}, voici mon fichier (${widget.title}).'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
         ]),
        ),
      ),
    );
  }

  /// Appel audio par internet.
  void _startCall() {
    final session = sessionOf(context, listen: false);
    CallService.openCall(
      context,
      conversationId: widget.conversationId,
      createIfMissing: widget.createIfMissing,
      asShop: widget.asShop,
      shopId: widget.shopId,
      otherName: widget.asShop ? widget.title : session.teamName(widget.shopId),
      me: widget.me,
    );
  }

  /// Transférer la discussion à un collègue ou au superviseur.
  Future<void> _transfer() async {
    final session = sessionOf(context, listen: false);
    final team = await Db.allStaff(shopId: widget.shopId).first;
    if (!mounted) return;
    final targets = <MapEntry<String, String>>[
      for (final m in team)
        if (m.active && m.uid != widget.me.uid)
          MapEntry(m.uid,
              '${m.name} (${m.role == 'manager' ? 'Responsable' : 'Agent'})'),
      if (!session.isSuper && AppConfig.adminUids.isNotEmpty)
        MapEntry(AppConfig.adminUids.first, 'Superviseur (Super Admin)'),
    ];
    final picked = await showModalBottomSheet<MapEntry<String, String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Transférer la discussion à…',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if (targets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun autre membre dans cette boutique.'),
              ),
            for (final t in targets)
              ListTile(
                leading: Icon(
                    t.value.startsWith('Superviseur')
                        ? Icons.admin_panel_settings
                        : Icons.person,
                    color: AppConfig.green),
                title: Text(t.value),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final toName = picked.value.split(' (').first;
    try {
      await Db.transferConversation(
        conversationId: widget.conversationId,
        toUid: picked.key,
        toName: toName,
        byUid: widget.me.uid,
        byName: widget.me.name,
        teamName: session.teamName(widget.shopId),
      );
      messenger.showSnackBar(
          SnackBar(content: Text('Discussion transférée à $toName ✅')));
      if (session.agentUid != null) nav.pop(); // l'agent n'y a plus accès
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Transfert impossible : ${_err(e)}')));
    }
  }

  Future<void> _pickService() async {
    final items = await Db.catalogItems().first;
    if (!mounted) return;
    final item = await showModalBottomSheet<CatalogItem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Choisir un service à proposer',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final i in items)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ProductImage(i.imageUrl, size: 48),
                ),
                title: Text(i.name),
                subtitle: Text(i.priceLabel),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (item != null) {
      await _send(
          type: 'service',
          text: _text.text.trim().isEmpty
              ? 'Nous vous proposons : ${item.name}'
              : _text.text.trim(),
          item: item);
      _text.clear();
    }
  }

  Future<void> _openService(String itemId) async {
    final item = await Db.catalogItem(itemId);
    if (!mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce service n\'est plus disponible.')));
      return;
    }
    openItem(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          if (widget.asShop)
            IconButton(
              tooltip: 'Transférer',
              onPressed: _transfer,
              icon: const Icon(Icons.forward_to_inbox, color: AppConfig.green),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: _startCall,
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Appeler'),
            ),
          ),
        ],
        title: Row(children: [
          CircleAvatar(
            backgroundColor: AppConfig.paleGreen,
            child: widget.asShop
                ? const Icon(Icons.person, color: AppConfig.green)
                : ClipOval(child: Image.asset(AppConfig.logo, width: 36, height: 36)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                StreamBuilder<Conversation?>(
                  stream: _conv,
                  builder: (_, cs) {
                    final who = cs.data?.assignedName ?? '';
                    final text = widget.asShop
                        ? (widget.subtitle ?? 'Client') +
                            (who.isNotEmpty ? ' • suivi par $who' : '')
                        : who.isNotEmpty
                            ? 'Votre conseiller : $who'
                            : (widget.subtitle ?? 'Nous vous répondons rapidement');
                    return Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.black54));
                  },
                ),
              ],
            ),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _messages,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text(friendlyError(snap.error), textAlign: TextAlign.center));
              }
              final list = snap.data ?? const <ChatMessage>[];
              _onNewMessages(list);
              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.asShop
                          ? 'Aucun message pour l\'instant.'
                          : 'Écrivez votre message : notre équipe vous répond ici.\n\nExemple : « Bonjour, je voudrais imprimer 100 cartes de visite. Quel est le prix ? »',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: list.length,
                itemBuilder: (_, i) => _bubble(list[i]),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            color: Colors.white,
            child: _recording
                ? _recordBar()
                : _about != null && _previewPath.isEmpty
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        _aboutBar(_about!),
                        _inputBar(),
                      ])
                : _previewPath.isNotEmpty
                    ? _previewBar()
                    : _inputBar(),
          ),
        ),
      ]),
    );
  }

  Widget _recordBar() {
    final d = DateTime.now().difference(_recStart);
    return Row(children: [
      IconButton(
        tooltip: 'Supprimer',
        onPressed: () => _stopRecording(send: false),
        icon: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
      const SizedBox(width: 6),
      Expanded(
        child: Text('Enregistrement… ${_dur(d)} / 3:00',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      IconButton(
        tooltip: 'Arrêter et écouter',
        onPressed: () => _stopRecording(send: false, preview: true),
        icon: const Icon(Icons.stop_circle_outlined, color: AppConfig.green, size: 30),
      ),
      IconButton.filled(
        tooltip: 'Envoyer',
        onPressed: () => _stopRecording(send: true),
        icon: const Icon(Icons.send_rounded),
      ),
    ]);
  }

  Widget _previewBar() {
    return Row(children: [
      IconButton(
        tooltip: 'Supprimer',
        onPressed: () => _closePreview(send: false),
        icon: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      IconButton(
        tooltip: _previewPlaying ? 'Arrêter' : 'Écouter',
        onPressed: _togglePreview,
        icon: Icon(_previewPlaying ? Icons.stop_circle : Icons.play_circle_fill,
            color: AppConfig.green, size: 34),
      ),
      Expanded(
        child: Text('Message vocal • ${_dur(_previewLen)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      IconButton.filled(
        tooltip: 'Envoyer',
        onPressed: _sending ? null : () => _closePreview(send: true),
        icon: const Icon(Icons.send_rounded),
      ),
    ]);
  }

  /// Article joint (affiché au-dessus de la zone d'écriture).
  Widget _aboutBar(CatalogItem it) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppConfig.paleGreen,
          borderRadius: BorderRadius.circular(14),
          border: const Border(left: BorderSide(color: AppConfig.green, width: 4)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ProductImage(it.imageUrl, size: 48),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Article joint',
                  style: TextStyle(
                      fontSize: 11.5, color: AppConfig.green, fontWeight: FontWeight.w800)),
              Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(it.priceLabel,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ]),
          ),
          IconButton(
            tooltip: 'Retirer l\'article',
            onPressed: () => setState(() => _about = null),
            icon: const Icon(Icons.close),
          ),
        ]),
      );

  Widget _inputBar() {
    return Row(children: [
      if (widget.asShop)
        IconButton(
          tooltip: 'Plus d\'actions',
          onPressed: _sending ? null : _attach,
          icon: const Icon(Icons.add_circle_outline, color: AppConfig.green),
        ),
      Expanded(
        child: TextField(
          controller: _text,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Écrire un message…',
            isDense: true,
            fillColor: const Color(0xFFF2F4F0),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.fromLTRB(16, 12, 4, 12),
            suffixIcon: IconButton(
              tooltip: 'Photo, vidéo, document',
              onPressed: _sending ? null : _attach,
              icon: const Icon(Icons.attach_file, color: AppConfig.green),
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      if (_sending)
        const Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
        )
      else
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (_, v, __) => v.text.trim().isEmpty
              ? IconButton.filled(
                  tooltip: 'Message vocal',
                  onPressed: _startRecording,
                  icon: const Icon(Icons.mic),
                )
              : IconButton.filled(
                  tooltip: 'Envoyer',
                  onPressed: () => _send(),
                  icon: const Icon(Icons.send_rounded),
                ),
        ),
    ]);
  }

  Widget _bubble(ChatMessage m) {
    if (m.type == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppConfig.paleGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(m.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppConfig.green,
                  fontWeight: FontWeight.w600)),
        ),
      );
    }
    final mine = widget.asShop ? m.fromShop : !m.fromShop;
    final bg = mine ? AppConfig.green : Colors.white;
    final fg = mine ? Colors.white : AppConfig.black;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          border: mine ? null : Border.all(color: const Color(0xFFE3E8E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                    m.agentName.isNotEmpty && !widget.asShop
                        ? '${m.agentName} • ${m.senderName}'
                        : m.agentName.isNotEmpty
                            ? m.agentName
                            : m.senderName,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppConfig.green)),
              ),
            if (m.text.isNotEmpty && !_isMedia(m))
              Text(m.text, style: TextStyle(color: fg, fontSize: 15, height: 1.3)),
            if (m.type == 'service' && m.itemId.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ServiceCard(
                itemId: m.itemId,
                itemName: m.itemName,
                mine: mine,
                fg: fg,
                onOpen: () => _openService(m.itemId),
                buttonLabel: !widget.asShop && m.fromShop
                    ? 'Commander ce service'
                    : 'Voir l\'article',
              ),
            ],
            if (m.type == 'file' && m.fileName.isNotEmpty) _fileContent(m, fg, mine),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(timeLabel(m.createdAt),
                  style: TextStyle(
                      fontSize: 10.5, color: mine ? Colors.white70 : Colors.black45)),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(m.pending ? Icons.schedule : Icons.done_all,
                    size: 13, color: Colors.white70,
                    semanticLabel: m.pending ? 'En attente d\'envoi' : 'Envoyé'),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  bool _isMedia(ChatMessage m) =>
      m.type == 'file' &&
      m.fileName.isNotEmpty &&
      FileService.kindOf(m.fileName) != 'doc';

  Widget _fileContent(ChatMessage m, Color fg, bool mine) {
    final kind = FileService.kindOf(m.fileName);
    if (m.fileUrl.isEmpty) return const SizedBox.shrink();
    switch (kind) {
      case 'image':
        return GestureDetector(
          onTap: () => _openFile(m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder(
              future: FileService.load(m.fileUrl),
              builder: (_, snap) {
                final b = snap.data;
                if (b != null && b.isNotEmpty) {
                  return Image.memory(b,
                      width: 220, height: 220, fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _photoBox(fg, Icons.broken_image));
                }
                return _photoBox(
                    fg, snap.hasError ? Icons.broken_image : Icons.photo);
              },
            ),
          ),
        );
      case 'audio':
        return VoiceMessage(
            url: m.fileUrl, name: m.fileName, label: m.text, color: fg);
      case 'video':
        return InkWell(
          onTap: () => _openFile(m),
          child: Container(
            width: 220,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
                SizedBox(height: 4),
                Text('Vidéo • toucher pour regarder',
                    style: TextStyle(color: Colors.white, fontSize: 12.5)),
              ],
            ),
          ),
        );
      default:
        return InkWell(
          onTap: () => _openFile(m),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insert_drive_file, color: fg, size: 18),
            const SizedBox(width: 6),
            Flexible(
                child: Text('${m.fileName}\nToucher pour télécharger',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
            const SizedBox(width: 6),
            Icon(Icons.download_rounded, color: fg, size: 20),
          ]),
        );
    }
  }

  Widget _photoBox(Color fg, IconData icon) => Container(
        width: 220,
        height: 160,
        color: Colors.black12,
        alignment: Alignment.center,
        child: icon == Icons.photo
            ? const SizedBox(
                width: 26, height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(icon, color: fg),
      );
}

/// Bulle « message vocal » avec bouton lecture / arrêt.
class VoiceMessage extends StatefulWidget {
  final String url;
  final String name;
  final String label;
  final Color color;
  const VoiceMessage({
    super.key,
    required this.url,
    required this.name,
    required this.label,
    required this.color,
  });

  @override
  State<VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage> {
  bool _playing = false;
  bool _loading = false;
  int _pos = 0; // ms
  int _len = 0; // ms
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  Future<void> _toggle() async {
    if (_playing) {
      await AichaMedia.stopPlay();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      final path = await FileService.localPath(widget.url, widget.name);
      final d = await AichaMedia.play(path, onDone: () {
        _stopTick();
        if (mounted) setState(() {
          _playing = false;
          _pos = 0;
        });
      });
      if (!mounted) return;
      setState(() {
        _playing = true;
        _len = d;
        _pos = 0;
      });
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        if (!mounted || !_playing) {
          _stopTick();
          return;
        }
        final (p, l) = await AichaMedia.position();
        if (mounted && _playing) {
          setState(() {
            _pos = p;
            if (l > 0) _len = l;
          });
        }
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Lecture impossible : '
              '${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label.replaceFirst('🎤 ', '');
    return SizedBox(
      width: 230,
      child: Row(children: [
        SizedBox(
          width: 44,
          height: 44,
          child: _loading
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: widget.color),
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: _playing ? 'Arrêter' : 'Écouter',
                  onPressed: _toggle,
                  icon: Icon(
                      _playing ? Icons.stop_circle : Icons.play_circle_fill,
                      color: widget.color,
                      size: 40),
                ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _len > 0 ? (_pos / _len).clamp(0.0, 1.0) : 0,
                  minHeight: 4,
                  color: widget.color,
                  backgroundColor: widget.color.withOpacity(0.25),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _playing
                    ? '${_fmt(_pos)} / ${_fmt(_len)}'
                    : (label.isEmpty ? 'Message vocal' : label),
                style: TextStyle(
                    color: widget.color, fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.mic, color: widget.color, size: 18),
      ]),
    );
  }
}

/// Fiche d'un article dans une bulle : photo, nom, prix et bouton.
class _ServiceCard extends StatelessWidget {
  final String itemId;
  final String itemName;
  final bool mine;
  final Color fg;
  final VoidCallback onOpen;
  final String buttonLabel;
  const _ServiceCard({
    required this.itemId,
    required this.itemName,
    required this.mine,
    required this.fg,
    required this.onOpen,
    required this.buttonLabel,
  });

  static final Map<String, Future<CatalogItem?>> _cache = {};

  @override
  Widget build(BuildContext context) {
    final f = _cache[itemId] ??= Db.catalogItem(itemId);
    return FutureBuilder<CatalogItem?>(
      future: f,
      builder: (_, snap) {
        final it = snap.data;
        return Container(
          width: 250,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: mine ? Colors.white : AppConfig.paleGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ProductImage(it?.imageUrl ?? '', size: 56),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it?.name ?? itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: AppConfig.black)),
                  if (it != null)
                    Text(it.priceLabel,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppConfig.green,
                            fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              onPressed: onOpen,
              child: Text(buttonLabel),
            ),
          ]),
        );
      },
    );
  }
}
