import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/promotion.dart';
import '../screens/announcement_screen.dart';
import 'product_image.dart';

/// Bandeau d'annonce en haut de l'accueil : image horizontale (format 4:1,
/// pas trop haute). Plusieurs annonces défilent toutes les 5 s.
/// Un toucher ouvre l'annonce.
class AnnouncementStrip extends StatefulWidget {
  final List<Promotion> annonces;
  const AnnouncementStrip({super.key, required this.annonces});

  @override
  State<AnnouncementStrip> createState() => _AnnouncementStripState();
}

class _AnnouncementStripState extends State<AnnouncementStrip> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.annonces.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_page.hasClients) return;
        final next = (_index + 1) % widget.annonces.length;
        _page.animateToPage(next,
            duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  Widget _banner(Promotion a) {
    final hasImage = a.imageUrl.isNotEmpty;
    return Material(
      color: AppConfig.green,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => AnnouncementScreen(promo: a))),
        child: Stack(fit: StackFit.expand, children: [
          if (hasImage)
            ProductImage(a.imageUrl)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(children: [
                const Icon(Icons.campaign_rounded, color: Colors.white, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5)),
                      if (a.description.isNotEmpty)
                        Text(a.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
              ]),
            ),
          // Petite étiquette « Annonce »
          Positioned(
            left: 8,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Annonce',
                  style: TextStyle(
                      color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.annonces;
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(children: [
        AspectRatio(
          aspectRatio: 4 / 1,
          child: PageView.builder(
            controller: _page,
            itemCount: list.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _banner(list[i]),
            ),
          ),
        ),
        if (list.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < list.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index ? AppConfig.green : Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
