import 'package:flutter/material.dart';

/// Semantic colors aligned with [ColorScheme] — use instead of hardcoded hex values.
extension RapidAidColors on ColorScheme {
  Color get star => const Color(0xFFF59E0B);

  Color get pitchCardFill => primaryContainer.withValues(alpha: 0.4);

  Color get pitchCardBorder => primary.withValues(alpha: 0.22);

  Color get waitingBannerFill => primaryContainer.withValues(alpha: 0.5);

  Color get waitingBannerText => onPrimaryContainer;

  Color get busyChipFill => tertiaryContainer.withValues(alpha: 0.65);

  Color get busyChipText => onTertiaryContainer;
}
