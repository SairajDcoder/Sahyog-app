import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'features/auth/auth_gate.dart';
import 'theme/app_colors.dart';
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryGreen.withValues(alpha: 0.05),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Hero(
                    tag: 'app_logo',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryGreen.withValues(
                              alpha: 0.1,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'lib/assets/favicon.png',
                        height: 60,
                        width: 60,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sahyog',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  Text(
                    'Disaster Response Network',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: const ClerkAuthentication(),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
