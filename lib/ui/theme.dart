import 'package:flutter/material.dart';

import '../app/settings.dart';

/// Builds the app theme for the given brightness from the user settings.
ThemeData buildTheme(Settings s, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final hc = s.highContrast;
  Color c(int darkValue, int lightValue) => Color(dark ? darkValue : lightValue);
  final scheme = ColorScheme.fromSeed(seedColor: s.accent, brightness: brightness).copyWith(
    primary: s.accent,
    onPrimary: const Color(0xFFFFFFFF),
    surface: c(hc ? 0xFF000000 : 0xFF232427, hc ? 0xFFFFFFFF : 0xFFF3F4F6),
    surfaceContainerLowest: c(0xFF141516, 0xFFD3D6DB),
    surfaceContainerLow: c(0xFF1C1D20, 0xFFE7E9ED),
    surfaceContainer: c(hc ? 0xFF0B0B0C : 0xFF2A2B2F, 0xFFFFFFFF),
    surfaceContainerHigh: c(0xFF34363B, 0xFFEFF1F4),
    surfaceContainerHighest: c(0xFF404248, 0xFFE1E4E9),
    onSurface: c(hc ? 0xFFFFFFFF : 0xFFE6E7EA, hc ? 0xFF000000 : 0xFF1E1F22),
    onSurfaceVariant: c(hc ? 0xFFE0E0E0 : 0xFFA4A7AE, hc ? 0xFF202020 : 0xFF5B5F66),
    outline: c(hc ? 0xFFB0B0B0 : 0xFF55585F, hc ? 0xFF404040 : 0xFFAEB2BA),
    outlineVariant: c(hc ? 0xFF808080 : 0xFF3A3C41, hc ? 0xFF606060 : 0xFFD5D8DD),
  );
  final base = ThemeData(colorScheme: scheme, brightness: brightness, useMaterial3: true, visualDensity: VisualDensity.compact);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      textStyle: TextStyle(fontSize: 12, color: dark ? const Color(0xFF1E1F22) : const Color(0xFFFFFFFF)),
      decoration: BoxDecoration(color: dark ? const Color(0xFFE6E7EA) : const Color(0xFF2A2B2F), borderRadius: BorderRadius.circular(6)),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant,
      thumbColor: scheme.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(7),
      thumbColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0.22)),
      radius: const Radius.circular(4),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Shorthand for the colours used all over the workspace.
extension DrawlyTheme on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  Color get panel => cs.surfaceContainer;
  Color get workspace => cs.surfaceContainerLowest;
  Color get line => cs.outlineVariant;
  Color get dim => cs.onSurfaceVariant;
}

const TextStyle kSmall = TextStyle(fontSize: 12);
const TextStyle kTiny = TextStyle(fontSize: 11);
