import 'package:flutter/material.dart';

class ReaderThemePalette {
  const ReaderThemePalette({
    required this.id,
    required this.name,
    required this.background,
    required this.foreground,
    required this.secondaryText,
    required this.accent,
    required this.card,
    required this.border,
    required this.toolbar,
    required this.shadow,
    required this.brightness,
  });

  final String id;
  final String name;
  final Color background;
  final Color foreground;
  final Color secondaryText;
  final Color accent;
  final Color card;
  final Color border;
  final Color toolbar;
  final Color shadow;
  final Brightness brightness;
}

class AppTheme {
  static const ReaderThemePalette paper = ReaderThemePalette(
    id: 'paper',
    name: '纸白',
    background: Color(0xFFF8F3E8),
    foreground: Color(0xFF26231F),
    secondaryText: Color(0xFF6D6357),
    accent: Color(0xFF8D5E42),
    card: Color(0xFFFDF9F0),
    border: Color(0xFFE5D7C1),
    toolbar: Color(0xEFFFFAF1),
    shadow: Color(0x1A4A331F),
    brightness: Brightness.light,
  );

  static const ReaderThemePalette warm = ReaderThemePalette(
    id: 'warm',
    name: '暖黄',
    background: Color(0xFFF5E6C8),
    foreground: Color(0xFF2B2418),
    secondaryText: Color(0xFF75644F),
    accent: Color(0xFF9C5B2A),
    card: Color(0xFFF9EDD6),
    border: Color(0xFFE0C8A2),
    toolbar: Color(0xECFFF3DE),
    shadow: Color(0x1A734B1F),
    brightness: Brightness.light,
  );

  static const ReaderThemePalette sage = ReaderThemePalette(
    id: 'sage',
    name: '浅绿',
    background: Color(0xFFE8F1E4),
    foreground: Color(0xFF1F2A1F),
    secondaryText: Color(0xFF5C6858),
    accent: Color(0xFF4E7155),
    card: Color(0xFFF1F7EE),
    border: Color(0xFFCFE0C9),
    toolbar: Color(0xEAF6FCF0),
    shadow: Color(0x163A5B34),
    brightness: Brightness.light,
  );

  static const ReaderThemePalette night = ReaderThemePalette(
    id: 'night',
    name: '夜间',
    background: Color(0xFF151515),
    foreground: Color(0xFFD8D2C4),
    secondaryText: Color(0xFFA39A8B),
    accent: Color(0xFFD48B56),
    card: Color(0xFF23211E),
    border: Color(0xFF38332C),
    toolbar: Color(0xE3252320),
    shadow: Color(0x40000000),
    brightness: Brightness.dark,
  );

  static const ReaderThemePalette graphite = ReaderThemePalette(
    id: 'graphite',
    name: '深灰',
    background: Color(0xFF202124),
    foreground: Color(0xFFE8EAED),
    secondaryText: Color(0xFFB0B6BE),
    accent: Color(0xFF9FB4C9),
    card: Color(0xFF2A2D31),
    border: Color(0xFF3B4047),
    toolbar: Color(0xE62A2D31),
    shadow: Color(0x40000000),
    brightness: Brightness.dark,
  );

  static const List<ReaderThemePalette> palettes = [
    paper,
    warm,
    sage,
    night,
    graphite,
  ];

  static ReaderThemePalette paletteFor(String themeId) {
    return palettes.firstWhere(
      (palette) => palette.id == themeId,
      orElse: () => paper,
    );
  }

  static ThemeData buildAppTheme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: paper.accent,
      brightness: Brightness.light,
      surface: paper.card,
      primary: paper.accent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper.background,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.05,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.12,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        bodyLarge: TextStyle(fontSize: 18, height: 1.7, letterSpacing: 0.1),
        bodyMedium: TextStyle(fontSize: 15, height: 1.55),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2B2418),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        showDragHandle: false,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: const BorderSide(color: Color(0xFFE5D7C1)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
