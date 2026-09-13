import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

enum ThemePreset { warm, sky, mint }

extension ThemePresetX on ThemePreset {
  String get key => switch (this) {
    ThemePreset.warm => 'warm',
    ThemePreset.sky => 'sky',
    ThemePreset.mint => 'mint',
  };

  static ThemePreset parse(String value) => switch (value) {
    'sky' => ThemePreset.sky,
    'mint' => ThemePreset.mint,
    _ => ThemePreset.warm,
  };
}

/// アプリ全体の配色。
///
/// 元の温かいクリーム基調を軸に、設定で選べる3系統を追加。
/// 既存コードの多くが [AppColors] を参照しているため、後方互換で
/// デフォルト値を維持した静的色定義は残しておく。
class AppColors {
  AppColors._();

  /// 陽線・プラス（温かみのあるグリーン）
  static const bull = Color(0xFF2E9E6B);

  /// 陰線・マイナス（柔らかいレッド）
  static const bear = Color(0xFFE25C5C);

  /// 背景（温かいクリーム）
  static const cream = Color(0xFFF7F1E8);

  /// カード面
  static const card = Color(0xFFFFFFFF);

  /// メインテキスト（濃いウォームブラウン）
  static const ink = Color(0xFF33291F);

  /// サブテキスト
  static const inkSoft = Color(0xFF8C7D6B);

  /// アクセント（アンバー / 移動平均線にも使う）
  static const accent = Color(0xFFEFA94A);

  /// ボタンなどの濃い面（書くボタンの黒っぽい四角）
  static const inkButton = Color(0xFF2B2118);
}

class ThemePalette {
  final Color seed;
  final Color bull;
  final Color bear;
  final Color cream;
  final Color card;
  final Color ink;
  final Color inkSoft;
  final Color accent;
  final Color button;
  final Color surface;

  const ThemePalette({
    required this.seed,
    required this.bull,
    required this.bear,
    required this.cream,
    required this.card,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.button,
    required this.surface,
  });

  static ThemePalette of(ThemePreset preset) {
    return switch (preset) {
      ThemePreset.warm => const ThemePalette(
        seed: Color(0xFF2E9E6B),
        bull: Color(0xFF2E9E6B),
        bear: Color(0xFFE25C5C),
        cream: Color(0xFFF7F1E8),
        card: Color(0xFFFFFFFF),
        ink: Color(0xFF33291F),
        inkSoft: Color(0xFF8C7D6B),
        accent: Color(0xFFEFA94A),
        button: Color(0xFF2B2118),
        surface: Color(0xFFF7F1E8),
      ),
      ThemePreset.sky => const ThemePalette(
        seed: Color(0xFF3D80F5),
        bull: Color(0xFF3D80F5),
        bear: Color(0xFFEE6A63),
        cream: Color(0xFFF3F7FF),
        card: Color(0xFFFFFFFF),
        ink: Color(0xFF1F3F6A),
        inkSoft: Color(0xFF6B8299),
        accent: Color(0xFFFFC24D),
        button: Color(0xFF1F2F4A),
        surface: Color(0xFFF3F7FF),
      ),
      ThemePreset.mint => const ThemePalette(
        seed: Color(0xFF2AB7A9),
        bull: Color(0xFF2AB7A9),
        bear: Color(0xFFEF6B7F),
        cream: Color(0xFFF5FFFC),
        card: Color(0xFFFFFFFF),
        ink: Color(0xFF18423B),
        inkSoft: Color(0xFF4E7A73),
        accent: Color(0xFFFFD166),
        button: Color(0xFF143B35),
        surface: Color(0xFFF5FFFC),
      ),
    };
  }
}

ThemeData buildAppTheme({ThemePreset preset = ThemePreset.warm}) {
  final palette = ThemePalette.of(preset);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.seed,
        brightness: Brightness.light,
      ).copyWith(
        primary: palette.button,
        onPrimary: Colors.white,
        secondary: palette.accent,
        surface: palette.surface,
        onSurface: palette.ink,
        surfaceContainerLowest: palette.card,
        surfaceContainerLow: palette.card,
        surfaceContainer: palette.card,
        surfaceContainerHighest: palette.cream,
        outline: palette.inkSoft,
        error: palette.bear,
      );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: palette.surface,
    // iPhone風の横スライド遷移（戻るスワイプ対応）
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    textTheme: base.textTheme.apply(
      bodyColor: palette.ink,
      displayColor: palette.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.cream,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: palette.ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      elevation: 14,
      shadowColor: palette.ink.withValues(alpha: 0.09),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.card,
      indicatorColor: palette.cream,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: palette.inkSoft,
        ),
      ),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: palette.inkSoft)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.button,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.ink.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: palette.button,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: palette.ink.withValues(alpha: 0.15)),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: palette.bull,
      thumbColor: palette.bull,
      inactiveTrackColor: palette.ink.withValues(alpha: 0.1),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.cream.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(color: palette.inkSoft),
    ),
    dividerTheme: DividerThemeData(color: palette.ink.withValues(alpha: 0.08)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.button,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
