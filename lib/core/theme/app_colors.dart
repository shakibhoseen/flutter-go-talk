import 'package:flutter/material.dart';

class PastelPalette {
  final Color bg;
  final Color text;
  const PastelPalette({required this.bg, required this.text});
}

class AppColors {
  AppColors._();

  static const Color colorFuchsia500 = Color(0xFFD946EF);
  static const Color colorFuchsia50 = Color(0xFFFDF4FF);
  static const Color colorFoundationPrimary500 = Color(0xFF00C3F8);
  static const Color colorViolate100 = Color(0xFFEDE9FE);
  static const Color shadowColor = Color(0x26000000);
  static const Color selectionColorPositive = Color(0xFF00C3F8);
  static const Color selectionColorNegative = Color(0xFFFA6969);

  // Cute Modern Cyan & Online Colors
  static const Color cyanAccent = Color(0xFF00C3F8);
  static const Color cyanLight = Color(0xFFE0F7FE);
  static const Color cyanDark = Color(0xFF0284C7);
  static const Color onlineGreen = Color(0xFF22C55E);
  static const Color offlineGrey = Color(0xFFCBD5E1);
  static const Color seenNavy = Color(0xFF0C4A6E);

  // Cute Pastel Avatar Palette (as seen in screenshots: MF, MJ, DR, SL, GM, etc.)
  static const List<PastelPalette> pastelPalettes = [
    PastelPalette(bg: Color(0xFFD9F99D), text: Color(0xFF365314)), // Soft lime/olive (MF)
    PastelPalette(bg: Color(0xFFBAE6FD), text: Color(0xFF0369A1)), // Soft sky blue (AG)
    PastelPalette(bg: Color(0xFFFED7AA), text: Color(0xFF9A3412)), // Soft peach/orange (MJ)
    PastelPalette(bg: Color(0xFFA7F3D0), text: Color(0xFF065F46)), // Soft mint (DR)
    PastelPalette(bg: Color(0xFFDDD6FE), text: Color(0xFF5B21B6)), // Soft lavender (SC)
    PastelPalette(bg: Color(0xFFFBCFE8), text: Color(0xFF9D174D)), // Soft pink (GM)
    PastelPalette(bg: Color(0xFFFEF08A), text: Color(0xFF854D0E)), // Soft butter yellow (SL)
    PastelPalette(bg: Color(0xFFCFFAFE), text: Color(0xFF155E75)), // Soft cyan (WH)
  ];

  static PastelPalette getPastelFor(String name) {
    if (name.isEmpty) return pastelPalettes[0];
    final hash = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return pastelPalettes[hash % pastelPalettes.length];
  }

  // material style
  static const Color foundationWhite = Color(0xFFFFFFFF);
  static const Color foundationBlack = Color(0xFF0A0A0A);
  static const MaterialColor neutralColor = MaterialColor(
    0xFF64748B,
    // 0% comes in here, this will be color picked if no shade is selected when defining a Color property which doesn’t require a swatch.
    <int, Color>{
      50: Color(0xFFF8FAFC), //10%
      100: Color(0xFFF1F5F9), //20%
      200: Color(0xFFE2E8F0), //30%
      300: Color(0xFFCBD5E1), //40%
      400: Color(0xFF94A3B8), //50%
      500: Color(0xFF64748B), //60%
      600: Color(0xFF475569), //70%
      700: Color(0xFF334155), //80%
      800: Color(0xFF1E293B), //80%
      900: Color(0xFF0F172A), //80%
    },
  );

  static const MaterialColor primaryColor = MaterialColor(
    0xFF00C3F8,
    <int, Color>{
      50: Color(0xFFE0F7FE), //10%
      100: Color(0xFFBAE6FD), //20%
      200: Color(0xFF7DD3FC), //30%
      300: Color(0xFF38BDF8), //40%
      400: Color(0xFF0EA5E9), //50%
      500: Color(0xFF00C3F8), //60%
      600: Color(0xFF0284C7), //70%
      700: Color(0xFF0369A1), //80%
      800: Color(0xFF075985), //80%
      900: Color(0xFF0C4A6E), //80%
    },
  );

  static const MaterialColor secondaryColor =
      MaterialColor(0xFFFF9209, <int, Color>{
        50: Color(0xFFFFFAF2),
        100: Color(0xFFFFDEB5),
        200: Color(0xFFFFC884),
        300: Color(0xFFFFB252),
        400: Color(0xFFFF9C21),
        500: Color(0xFFFF9209),
        600: Color(0xFFD97904),
        700: Color(0xFFA95E03),
        800: Color(0xFF794302),
        900: Color(0xFF482801),
      });

  static const MaterialColor successColor =
      MaterialColor(0xFF22C55E, <int, Color>{
        50: Color(0xFFF0FDF4),
        100: Color(0xFFDCFCE7),
        200: Color(0xFFBBF7D0),
        300: Color(0xFF86EFAC),
        400: Color(0xFF4ADE80),
        500: Color(0xFF22C55E),
        600: Color(0xFF16A34A),
        700: Color(0xFF15803D),
        800: Color(0xFF166534),
        900: Color(0xFF14532D),
      });

  static const MaterialColor infoColor = MaterialColor(0xFF3B82F6, <int, Color>{
    50: Color(0xFFEFF6FF),
    100: Color(0xFFDBEAFE),
    200: Color(0xFFBFDBFE),
    300: Color(0xFF93C5FD),
    400: Color(0xFF60A5FA),
    500: Color(0xFF3B82F6),
    600: Color(0xFF2563EB),
    700: Color(0xFF1D4ED8),
    800: Color(0xFF1E40AF),
    900: Color(0xFF1E3A8A),
  });

  static const MaterialColor warningColor =
      MaterialColor(0xFFEAB308, <int, Color>{
        50: Color(0xFFFEFCE8),
        100: Color(0xFFFEF9C3),
        200: Color(0xFFFEF08A),
        300: Color(0xFFFDE047),
        400: Color(0xFFFACC15),
        500: Color(0xFFEAB308),
        600: Color(0xFFCA8A04),
        700: Color(0xFFA16207),
        800: Color(0xFF854D0E),
        900: Color(0xFF713F12),
      });

  static const MaterialColor errorColor =
      MaterialColor(0xFFEF4444, <int, Color>{
        50: Color(0xFFFEF2F2),
        100: Color(0xFFFEE2E2),
        200: Color(0xFFFECACA),
        300: Color(0xFFFCA5A5),
        400: Color(0xFFF87171),
        500: Color(0xFFEF4444),
        600: Color(0xFFDC2626),
        700: Color(0xFFB91C1C),
        800: Color(0xFF991B1B),
        900: Color(0xFF7F1D1D),
      });
}
