import 'package:flutter/material.dart';

/// Shared visual chrome (no business logic).
abstract final class AppUi {
  static Widget sheetDragHandle(ColorScheme scheme) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  static List<BoxShadow> panelShadow(ColorScheme scheme) => [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.14),
          blurRadius: 24,
          offset: const Offset(0, -8),
        ),
      ];

  static Widget emptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget partnerAvatar({
    required ColorScheme scheme,
    required String name,
    double radius = 24,
  }) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.85),
      child: Text(
        initial,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}

/// Use when the dashboard [Scaffold] has [extendBody] + [NavigationBar] (~72–88px).
class FabAboveBottomNavLocation extends FloatingActionButtonLocation {
  const FabAboveBottomNavLocation({
    this.navBarHeight = 88,
    this.margin = 20,
  });

  final double navBarHeight;
  final double margin;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final fabSize = scaffoldGeometry.floatingActionButtonSize;
    final scaffoldSize = scaffoldGeometry.scaffoldSize;
    final x = scaffoldSize.width - fabSize.width - margin;
    final y = scaffoldSize.height - fabSize.height - navBarHeight - margin;
    return Offset(x, y);
  }
}
