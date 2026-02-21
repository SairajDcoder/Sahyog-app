import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'features/auth/auth_gate.dart';
import 'theme/app_theme.dart';

const clerkPublishableKey =
    'pk_test_ZGlyZWN0LWhlcm1pdC04NC5jbGVyay5hY2NvdW50cy5kZXYk';

class SahyogApp extends StatelessWidget {
  const SahyogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ClerkAuth(
      config: ClerkAuthConfig(publishableKey: clerkPublishableKey),
      child: MaterialApp(
        title: 'Sahyog',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: ClerkAuthBuilder(
          signedOutBuilder: (_, __) => const _SignedOutScreen(),
          signedInBuilder: (_, authState) => AuthGate(authState: authState),
        ),
      ),
    );
  }
}

class _SignedOutScreen extends StatelessWidget {
  const _SignedOutScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sahyog Login')),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: ClerkAuthentication()),
        ),
      ),
    );
  }
}
