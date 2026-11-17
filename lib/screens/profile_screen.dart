import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/shop_settings.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../utils.dart';

class ProfileScreen extends StatelessWidget {
  final AppUser? user;
  const ProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        children: [
          if (u != null) ...[
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(u.name),
              subtitle: Text(u.email),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(u.phone.isEmpty ? '—' : u.phone),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Nous contacter',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          StreamBuilder<ShopSettings>(
            stream: Db.settings(),
            builder: (context, snap) {
              final s = snap.data ?? const ShopSettings();
              return Column(children: [
                ListTile(
                  leading: Image.asset(AppConfig.logo, width: 48),
                  title: const Text(AppConfig.shopName),
                  subtitle: const Text(AppConfig.tagline),
                ),
                if (s.address.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(s.address),
                    subtitle: s.hours.isEmpty ? null : Text(s.hours),
                  ),
                if (s.phone.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.call),
                    title: Text(s.phone),
                    subtitle: const Text('Appeler'),
                    onTap: () => launchUrl(Uri.parse('tel:${s.phone}')),
                  ),
                if (s.whatsapp.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(s.whatsapp),
                    subtitle: const Text('WhatsApp'),
                    onTap: () => launchUrl(whatsappUri(s.whatsapp),
                        mode: LaunchMode.externalApplication),
                  ),
              ]);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () => AuthService.signOut(),
          ),
        ],
      ),
    );
  }
}
