import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'state/cart.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!DefaultFirebaseOptions.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    ChangeNotifierProvider(create: (_) => Cart(), child: const ShopApp()),
  );
}

ThemeData _theme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConfig.green,
        primary: AppConfig.green,
        secondary: AppConfig.black,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.shortName,
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: StreamBuilder<User?>(
        stream: AuthService.changes,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final user = snap.data;
          if (user == null) return const AuthScreen();
          return HomeScreen(key: ValueKey(user.uid), uid: user.uid);
        },
      ),
    );
  }
}

class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _theme(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Firebase n\'est pas configuré.\n\n'
              'Ajoutez les secrets FIREBASE_* dans GitHub '
              '(voir le README), puis relancez la compilation.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
