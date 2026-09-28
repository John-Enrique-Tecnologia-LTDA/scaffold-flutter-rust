import 'package:flutter/material.dart';

/// Paleta do app: grafite quase preto (o app passa horas aberto), superfícies um
/// tom acima e divisórias em branco translúcido. A cor da marca vem do manifest do scaffold.
abstract final class Palette {
  /// Fundo mais fundo (atrás do conteúdo).
  static const ink = Color(0xFF0A0C0F);

  /// Fundo das páginas.
  static const canvas = Color(0xFF0E1013);

  /// Barras, painéis laterais e navegação.
  static const bar = Color(0xFF13161B);

  /// Cartões e blocos sobre o fundo.
  static const raised = Color(0xFF171A20);

  /// Diálogos e menus, um tom acima dos cartões.
  static const overlay = Color(0xFF1C2027);

  static const hairline = Color(0x1AFFFFFF);
  static const hairlineStrong = Color(0x2EFFFFFF);

  /// Cor de destaque da marca.
  static const accent = Color(0xFF{= colors.accent =});

  /// Cores de destaque dos itens, em sequência.
  static const tracks = [accent, Color(0xFFE3B341), Color(0xFFB58CF0), Color(0xFFEF7D6D), Color(0xFF6BA8F0), Color(0xFF6BCB8B)];

  static const success = Color(0xFF6BCB8B);
  static const danger = Color(0xFFEF7D6D);
}

final _radius10 = BorderRadius.circular(10);
final _radius14 = BorderRadius.circular(14);

ThemeData buildTheme() {
  final base = ColorScheme.fromSeed(seedColor: const Color(0xFF{= colors.accent_dark =}), brightness: Brightness.dark);
  final scheme = base.copyWith(
    primary: Palette.accent,
    surface: Palette.canvas,
    surfaceContainerLowest: Palette.ink,
    surfaceContainerLow: Palette.bar,
    surfaceContainer: Palette.raised,
    surfaceContainerHigh: Palette.overlay,
    surfaceContainerHighest: const Color(0xFF242932),
    outlineVariant: const Color(0xFF2B3039),
  );
  const hairline = BorderSide(color: Palette.hairline);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Palette.canvas,
    canvasColor: Palette.canvas,
    dividerTheme: const DividerThemeData(color: Palette.hairline, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Palette.raised,
      shape: RoundedRectangleBorder(borderRadius: _radius14, side: hairline),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.bar,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shape: Border(bottom: hairline),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: _radius10,
        borderSide: const BorderSide(color: Palette.hairlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _radius10,
        borderSide: const BorderSide(color: Palette.hairlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _radius10,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: hairline),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Palette.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: hairline),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Palette.bar, surfaceTintColor: Colors.transparent, showDragHandle: true),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2F38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Palette.bar,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.bar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      height: 64,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: _radius10),
    ),
    scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(6), radius: Radius.circular(3)),
  );
}

/// Cor de destaque pela posição.
Color trackColorAt(int i) => Palette.tracks[i % Palette.tracks.length];
