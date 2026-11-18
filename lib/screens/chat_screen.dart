import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/catalog_item.dart';
import '../models/chat.dart';
import '../services/db.dart';
import '../services/file_service.dart';
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
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  late final Stream<List<ChatMessage>> _messages =
      Db.messages(widget.conversationId);
  final _scroll = ScrollController();
  String _lastSeen = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    Db.markRead(widget.conversationId, asShop: widget.asShop);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({
    String type = 'text',
    String? text,
    CatalogItem? item,
  }) async {
    final body = (text ?? _text.text).trim();
    if (type == 'text' && body.isEmpty) return;
    setState(() => _sending = true);
    try {
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
      );
      if (type == 'text') _text.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Envoi impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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

  Future<void> _uploadFile() async {
    setState(() => _sending = true);
    try {
      final up = await FileService.pickAndUpload(
          folder: 'aicha/${widget.shopId}');
      if (up == null) return;
      await Db.sendMessage(
        conversationId: widget.conversationId,
        createIfMissing: widget.createIfMissing,
        senderId: widget.me.uid,
        senderRole: widget.asShop ? 'shop' : 'client',
        senderName: widget.asShop
            ? sessionOf(context, listen: false).teamName(widget.shopId)
            : widget.me.name,
        text: '',
        type: 'file',
        fileUrl: up.url,
        fileName: up.name,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fichier envoyé : ${up.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_err(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final filesOn = await FileService.enabled();
    if (!mounted) return;
    if (widget.asShop) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (filesOn)
              ListTile(
                leading: const Icon(Icons.upload_file, color: AppConfig.green),
                title: const Text('Envoyer un fichier'),
                subtitle: const Text('Photo, PDF, Word…'),
                onTap: () {
                  Navigator.pop(ctx);
                  _uploadFile();
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
      );
      return;
    }
    // Côté client : fichier dans l'appli (si activé) ou par WhatsApp.
    final contact = sessionOf(context, listen: false).shopById(widget.shopId).contact;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file, color: AppConfig.green),
            title: const Text('Envoyer un fichier'),
            subtitle: Text(filesOn
                ? 'Photo, PDF, Word… (10 Mo max.)'
                : 'Bientôt disponible : utilisez WhatsApp'),
            enabled: filesOn,
            onTap: () {
              Navigator.pop(ctx);
              _uploadFile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat, color: AppConfig.green),
            title: const Text('Envoyer un fichier par WhatsApp'),
            subtitle: const Text('Photo, logo, PDF, Word…'),
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
    );
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
                Text(widget.subtitle ?? (widget.asShop ? 'Client' : 'Nous vous répondons rapidement'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
                return Center(child: Text('Erreur : ${snap.error}'));
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
            child: Row(children: [
              IconButton(
                onPressed: _attach,
                icon: Icon(widget.asShop ? Icons.add_circle_outline : Icons.attach_file,
                    color: AppConfig.green),
              ),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Votre message…',
                    isDense: true,
                    fillColor: const Color(0xFFF2F4F0),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _sending ? null : () => _send(),
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
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
                child: Text(m.senderName,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppConfig.green)),
              ),
            if (m.text.isNotEmpty)
              Text(m.text, style: TextStyle(color: fg, fontSize: 15, height: 1.3)),
            if (m.type == 'service' && m.itemId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mine ? Colors.white24 : AppConfig.paleGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.design_services, color: mine ? Colors.white : AppConfig.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m.itemName,
                        style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                  ),
                ]),
              ),
              if (!widget.asShop) ...[
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _openService(m.itemId),
                  child: const Text('Commander ce service'),
                ),
              ],
            ],
            if (m.type == 'file' && m.fileName.isNotEmpty)
              InkWell(
                onTap: m.fileUrl.isEmpty
                    ? null
                    : () => launchUrl(Uri.parse(m.fileUrl),
                        mode: LaunchMode.externalApplication),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.insert_drive_file, color: fg, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text('Fichier envoyé : ${m.fileName}',
                          style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 2),
            Text(timeLabel(m.createdAt),
                style: TextStyle(
                    fontSize: 10.5, color: mine ? Colors.white70 : Colors.black45)),
          ],
        ),
      ),
    );
  }
}
