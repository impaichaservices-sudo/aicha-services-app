import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Signature au doigt. Renvoie l'image PNG en base64 (ou null).
class SignatureScreen extends StatefulWidget {
  final String title;
  const SignatureScreen({super.key, this.title = 'Signature'});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _strokes = <List<Offset>>[];
  Size _size = Size.zero;

  Future<void> _done() async {
    if (_strokes.every((s) => s.length < 2)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Signez dans le cadre blanc.')));
      return;
    }
    const w = 600.0, h = 220.0;
    final sx = w / _size.width, sy = h / _size.height;
    final k = sx < sy ? sx : sy;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
    final paint = Paint()
      ..color = const Color(0xFF0D1B4C)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx * k, s.first.dy * k);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx * k, p.dy * k);
      }
      c.drawPath(path, paint);
    }
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || data == null) return;
    Navigator.of(context).pop(base64Encode(data.buffer.asUint8List()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Signez avec le doigt dans le cadre. Signature interne à l\'application '
            '(ce n\'est pas une signature électronique certifiée).',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AspectRatio(
              aspectRatio: 600 / 220,
              child: LayoutBuilder(builder: (_, box) {
                _size = Size(box.maxWidth, box.maxHeight);
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black26, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: GestureDetector(
                    onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                    onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                    child: CustomPaint(
                      painter: _Painter(_strokes),
                      size: Size.infinite,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(_strokes.clear),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Effacer'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _done,
                  icon: const Icon(Icons.check),
                  label: const Text('Valider'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Painter extends CustomPainter {
  final List<List<Offset>> strokes;
  _Painter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF0D1B4C)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
