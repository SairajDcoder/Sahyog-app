import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      brightness: Brightness.light,
      primary: AppColors.primaryGreen,
      surface: AppColors.neutralLight,
      onSurface: AppColors.neutralDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.neutralLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.neutralLight,
        foregroundColor: AppColors.neutralDark,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      brightness: Brightness.dark,
      primary: AppColors.primaryGreen,
      surface: AppColors.neutralDark,
      onSurface: AppColors.neutralLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B1013),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B1013),
        foregroundColor: AppColors.neutralLight,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF151D23),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
