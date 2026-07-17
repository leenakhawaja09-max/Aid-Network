import 'package:flutter/material.dart';

/// Brand + shared [ThemeData] for RapidAid / CAN.
abstract final class AppBranding {
  static const Color primary = Color(0xFF1D63D8);
  static const Color primaryDeep = Color(0xFF124099);
  static const Color accentTeal = Color(0xFF0D9488);
  static const Color mapPin = Color(0xFFE11D48);
  static const Color star = Color(0xFFF59E0B);

  static const LinearGradient authBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2563EB),
      Color(0xFF1D4ED8),
      primaryDeep,
    ],
    stops: [0.0, 0.45, 1.0],
  );
}

ThemeData buildRapidAidTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppBranding.primary,
    brightness: Brightness.light,
    primary: AppBranding.primary,
    secondary: AppBranding.accentTeal,
    tertiary: const Color(0xFF5B6B8C),
    error: const Color(0xFFDC2626),
    surface: const Color(0xFFF0F3F8),
  ).copyWith(
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: const Color(0xFF1A2332),
    onSurfaceVariant: const Color(0xFF5C6578),
    outline: const Color(0xFFB8C4D4),
    outlineVariant: const Color(0xFFD8E0EB),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFAFBFD),
    surfaceContainer: const Color(0xFFF3F6FA),
    surfaceContainerHigh: const Color(0xFFE8EDF4),
    surfaceContainerHighest: const Color(0xFFDCE3ED),
    primaryContainer: const Color(0xFFD9E8FC),
    onPrimaryContainer: AppBranding.primaryDeep,
    secondaryContainer: const Color(0xFFC8F0EA),
    onSecondaryContainer: const Color(0xFF0D5C52),
    tertiaryContainer: const Color(0xFFFFE8CC),
    onTertiaryContainer: const Color(0xFF7C4A03),
    inverseSurface: const Color(0xFF1A2332),
    onInverseSurface: const Color(0xFFF4F6FA),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    primaryIconTheme: IconThemeData(color: scheme.primary, size: 22),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
        color: scheme.onSurface,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.25,
        color: scheme.onSurface,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: scheme.onSurface,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        height: 1.45,
        color: scheme.onSurface,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.4,
        color: scheme.onSurface,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: scheme.onSurface,
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      backgroundColor: scheme.surfaceContainerLowest,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: scheme.onSurface),
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      alignLabelWithHint: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        fontWeight: FontWeight.w400,
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface.withValues(alpha: 0.88),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        alignment: Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        alignment: Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        alignment: Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
        foregroundColor: scheme.primary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      highlightElevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primaryContainer.withValues(alpha: 0.85),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: selected ? 0.1 : 0,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.55),
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: scheme.onSurface,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerHeight: 0,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      overlayColor: WidgetStateProperty.all(scheme.primary.withValues(alpha: 0.06)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: false,
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
