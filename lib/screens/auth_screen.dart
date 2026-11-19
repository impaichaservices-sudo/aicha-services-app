import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/shop_settings.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../utils.dart';

/// Connexion / inscription par NUMÉRO DE TÉLÉPHONE + mot de passe.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _password, _password2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await AuthService.register(
          name: _name.text,
          phone: _phone.text,
          password: _password.text,
        );
      } else {
        await AuthService.signIn(_phone.text, _password.text);
      }
    } catch (e) {
      setState(() => _error = AuthService.message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mot de passe oublié : demande de réinitialisation envoyée au Super Admin
  /// (ou message WhatsApp à la boutique).
  Future<void> _forgot() async {
    final phone = TextEditingController(text: _phone.text.trim());
    final name = TextEditingController();
    final msg = TextEditingController();
    final key = GlobalKey<FormState>();
    final send = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mot de passe oublié'),
        content: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Envoyez une demande : l\'équipe vous donnera un nouveau '
                  'mot de passe, par exemple sur WhatsApp.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Votre numéro *'),
                validator: (v) => AuthService.isValidPhone(v ?? '')
                    ? null
                    : 'Numéro invalide (8 chiffres)',
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Votre nom *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: msg,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Message (facultatif)'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'wa'), child: const Text('WhatsApp')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(c, 'request');
            },
            child: const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
    if (!mounted || send == null) return;
    if (send == 'request') {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await Db.addResetRequest(
          phone: AuthService.displayPhone(phone.text.trim()),
          name: name.text.trim(),
          message: msg.text.trim(),
        ).timeout(const Duration(seconds: 15));
        messenger.showSnackBar(const SnackBar(
            duration: Duration(seconds: 6),
            content: Text('Demande envoyée ✅ L\'équipe vous contactera avec un nouveau mot de passe.')));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Envoi impossible. Vérifiez votre connexion Internet.')));
      }
      return;
    }
    ShopSettings s = const ShopSettings();
    try {
      s = ShopSettings.fromDoc(await Db.settingsDoc.get());
    } catch (_) {}
    final contact = s.whatsapp.isNotEmpty ? s.whatsapp : s.phone;
    if (!mounted) return;
    if (contact.isEmpty) {
      setState(() => _error =
          'Contactez ${AppConfig.shopName} pour réinitialiser votre mot de passe.');
      return;
    }
    await launchUrl(
      whatsappUri(contact,
          'Bonjour, j\'ai oublié mon mot de passe. Mon numéro : ${phone.text.trim()}'),
      mode: LaunchMode.externalApplication,
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(AppConfig.logo, height: 200),
                  const SizedBox(height: 4),
                  Text(AppConfig.slogan,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline)),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Numéro de téléphone',
                      hintText: '70 00 00 00',
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                    validator: (v) => AuthService.isValidPhone(v ?? '')
                        ? null
                        : 'Numéro invalide (8 chiffres)',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _hide,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? '6 caractères minimum'
                        : null,
                  ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password2,
                      obscureText: _hide,
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le mot de passe',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => v != _password.text
                          ? 'Les mots de passe ne correspondent pas'
                          : null,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Créer mon compte' : 'Se connecter'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
                    child: Text(_register
                        ? 'J\'ai déjà un compte'
                        : 'Pas de compte ? S\'inscrire'),
                  ),
                  if (!_register)
                    TextButton(
                      onPressed: _forgot,
                      child: const Text('Mot de passe oublié ?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
