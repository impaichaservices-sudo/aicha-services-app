import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../services/db.dart';
import '../services/file_service.dart';
import '../services/session.dart';
import '../utils.dart';
import 'chat_screen.dart';

/// « Vous ne trouvez pas votre besoin ? » : demande d'un service sur mesure.
/// Envoie la demande (et le fichier) dans la discussion avec l'équipe.
class CustomRequestScreen extends StatefulWidget {
  const CustomRequestScreen({super.key});

  @override
  State<CustomRequestScreen> createState() => _CustomRequestScreenState();
}

class _CustomRequestScreenState extends State<CustomRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _need = TextEditingController();
  final _desc = TextEditingController();
  final _qty = TextEditingController();
  DateTime? _date;
  Uint8List? _fileBytes;
  String _fileName = '';
  bool _busy = false;

  @override
  void dispose() {
    _need.dispose();
    _desc.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, imageQuality: 70, maxWidth: 1600, maxHeight: 1600);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() {
      _fileBytes = b;
      _fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    });
  }

  Future<void> _pickDocument() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: FileService.allowed, withData: true);
    final f = res?.files.single;
    if (f == null) return;
    var b = f.bytes;
    if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
    if (b == null) return;
    setState(() {
      _fileBytes = b;
      _fileName = f.name;
    });
  }

  Future<void> _chooseFile() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, color: AppConfig.green),
            title: const Text('Prendre une photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickPhoto(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppConfig.green),
            title: const Text('Photo de la galerie'),
            onTap: () {
              Navigator.pop(ctx);
              _pickPhoto(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file, color: AppConfig.green),
            title: const Text('Document ou logo'),
            subtitle: const Text('PDF, Word, Excel, JPG, PNG… (15 Mo max.)'),
            onTap: () {
              Navigator.pop(ctx);
              _pickDocument();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final session = sessionOf(context, listen: false);
    final me = session.me;
    final shopId = session.clientShopId.isEmpty ? 'main' : session.clientShopId;
    final convId = Db.generalConversationId(me.uid);
    final create = Db.generalConversationData(me, shopId: shopId);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final lines = <String>[
      '📝 Demande de service personnalisé',
      'Besoin : ${_need.text.trim()}',
      if (_desc.text.trim().isNotEmpty) 'Description : ${_desc.text.trim()}',
      if (_qty.text.trim().isNotEmpty) 'Quantité : ${_qty.text.trim()}',
      if (_date != null) 'Date souhaitée : ${shortDate(_date).split(' ').first}',
      if (_fileBytes != null) 'Fichier joint : $_fileName',
    ];
    setState(() => _busy = true);
    try {
      await Db.sendMessage(
        conversationId: convId,
        createIfMissing: create,
        senderId: me.uid,
        senderRole: 'client',
        senderName: me.name,
        text: lines.join('\n'),
      );
      if (_fileBytes != null) {
        final up = await FileService.uploadBytes(
            bytes: _fileBytes!, name: _fileName, shopId: shopId, conversationId: convId);
        await Db.sendMessage(
          conversationId: convId,
          createIfMissing: create,
          senderId: me.uid,
          senderRole: 'client',
          senderName: me.name,
          text: FileService.kindOf(_fileName) == 'image' ? '📷 Photo' : '',
          type: 'file',
          fileUrl: up.url,
          fileName: up.name,
        );
        await Db.addFile({
          'ownerId': me.uid,
          'shopId': shopId,
          'conversationId': convId,
          'orderId': '',
          'name': up.name,
          'url': up.url,
          'size': up.size,
        });
      }
      messenger.showSnackBar(const SnackBar(
          content: Text('Demande envoyée ✅ L\'équipe vous répond dans la discussion.')));
      nav.pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: convId,
          createIfMissing: create,
          title: 'Équipe ${session.teamName(shopId)}',
          asShop: false,
          me: me,
          shopId: shopId,
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().contains('15 Mo')
              ? 'Votre fichier dépasse 15 Mo.'
              : 'Impossible d\'envoyer la demande. Vérifiez votre connexion Internet.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Service personnalisé')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Décrivez ce dont vous avez besoin : l\'équipe vous répond avec un prix.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _need,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Besoin *', hintText: 'Ex. : 50 T-shirts floqués avec logo'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Indiquez votre besoin' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  hintText: 'Couleurs, tailles, textes, format…'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantité'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? now.add(const Duration(days: 3)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
              icon: const Icon(Icons.event),
              label: Text(_date == null
                  ? 'Date souhaitée'
                  : 'Date souhaitée : ${shortDate(_date).split(' ').first}'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _chooseFile,
              icon: Icon(_fileBytes == null ? Icons.attach_file : Icons.check_circle,
                  color: AppConfig.green),
              label: Text(_fileBytes == null
                  ? 'Ajouter une photo, un document ou un logo'
                  : _fileName),
            ),
            if (_fileBytes != null)
              TextButton(
                onPressed: () => setState(() {
                  _fileBytes = null;
                  _fileName = '';
                }),
                child: const Text('Retirer le fichier'),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: const Text('Envoyer ma demande'),
            ),
          ],
        ),
      ),
    );
  }
}
