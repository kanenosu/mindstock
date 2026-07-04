import 'package:flutter/material.dart';

/// アプリ全体の配色。
///
/// 温かいクリーム基調 + 株アプリらしい緑/赤。
/// ダークで冷たい「トレーダー向け」ではなく、
/// iPhone風に洗練された、毎日開きたくなる温かさを狙う（仕様書 §8）。
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

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.bull,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.inkButton,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        surface: AppColors.cream,
        onSurface: AppColors.ink,
        surfaceContainerLowest: AppColors.card,
        surfaceContainerLow: AppColors.card,
        surfaceContainer: AppColors.card,
        surfaceContainerHighest: const Color(0xFFF0E8DB),
        outline: AppColors.inkSoft,
        error: AppColors.bear,
      );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 10,
      shadowColor: AppColors.ink.withValues(alpha: 0.07),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.cream,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
      iconTheme: const WidgetStatePropertyAll(
        IconThemeData(color: AppColors.inkSoft),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.inkButton,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.ink.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.inkButton,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: AppColors.ink.withValues(alpha: 0.15)),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.bull,
      thumbColor: AppColors.bull,
      inactiveTrackColor: AppColors.ink.withValues(alpha: 0.1),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cream.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: AppColors.inkSoft),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.ink.withValues(alpha: 0.08),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.inkButton,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
