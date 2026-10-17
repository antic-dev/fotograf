import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Topla, elegantna paleta: slonovača + ugalj + smaragdno zelena.
/// Zelena znači "izabrano" svuda u aplikaciji — jedno pravilo koje svako razume.
class AppColors {
  static const ivory = Color(0xFFFBF8F3);
  static const paper = Color(0xFFFFFFFF);
  static const sand = Color(0xFFF2ECE3);
  static const line = Color(0xFFE4DCCF);
  static const ink = Color(0xFF1D1B18);
  static const inkSoft = Color(0xFF5E5850);
  static const inkFaint = Color(0xFF8F877C);
  static const emerald = Color(0xFF17694F);
  static const emeraldDark = Color(0xFF0F4D3A);
  static const emeraldSoft = Color(0xFFE2F1EA);
  static const gold = Color(0xFFB4884B);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFBE9E7);
  static const amber = Color(0xFFB26B00);
  static const amberSoft = Color(0xFFFFF1DC);
  static const night = Color(0xFF0E0D0C);
}

const displayFont = 'Fraunces';
const bodyFont = 'Inter';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.emerald,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.emerald,
    onPrimary: Colors.white,
    primaryContainer: AppColors.emeraldSoft,
    onPrimaryContainer: AppColors.emeraldDark,
    secondary: AppColors.gold,
    surface: AppColors.ivory,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSoft,
    surfaceContainerLowest: AppColors.paper,
    surfaceContainerLow: const Color(0xFFF7F3EC),
    surfaceContainer: AppColors.sand,
    surfaceContainerHigh: const Color(0xFFEDE6DB),
    outline: AppColors.line,
    outlineVariant: AppColors.line,
    error: AppColors.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: bodyFont);
  final t = base.textTheme;
  TextStyle display(TextStyle? s, double size, {FontWeight w = FontWeight.w600}) =>
      (s ?? const TextStyle()).copyWith(fontFamily: displayFont, fontSize: size, fontWeight: w, height: 1.12, letterSpacing: -0.4, color: AppColors.ink);

  final text = t.copyWith(
    displayLarge: display(t.displayLarge, 56),
    displayMedium: display(t.displayMedium, 44),
    displaySmall: display(t.displaySmall, 36),
    headlineLarge: display(t.headlineLarge, 32),
    headlineMedium: display(t.headlineMedium, 28),
    headlineSmall: display(t.headlineSmall, 24),
    titleLarge: t.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: t.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    titleSmall: t.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.5),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
    bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 1.4, color: AppColors.inkSoft),
    labelLarge: t.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const big = Size(64, 56);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: AppColors.ivory,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ivory,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: AppColors.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: big,
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 52),
        shape: shape,
        side: const BorderSide(color: AppColors.line, width: 1.5),
        foregroundColor: AppColors.ink,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    cardTheme: CardThemeData(
      color: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.emerald, width: 2)),
      labelStyle: text.bodyLarge?.copyWith(color: AppColors.inkSoft),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: AppColors.emerald, fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppColors.line, width: 1.5),
      labelStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      selectedColor: AppColors.emeraldSoft,
      checkmarkColor: AppColors.emerald,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: text.bodyLarge?.copyWith(color: Colors.white, fontSize: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.headlineSmall,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.emeraldSoft,
      labelTextStyle: WidgetStatePropertyAll(text.bodySmall?.copyWith(fontSize: 11.5, letterSpacing: -0.2, fontWeight: FontWeight.w600, color: AppColors.ink)),
      height: 72,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.paper,
      indicatorColor: AppColors.emeraldSoft,
      selectedLabelTextStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.emeraldDark),
      unselectedLabelTextStyle: text.bodyMedium?.copyWith(color: AppColors.inkSoft),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.emerald, linearTrackColor: AppColors.sand),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.emerald : null),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
