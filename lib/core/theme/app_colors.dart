import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color colorFuchsia500 = Color(0xFFD946EF);
  static const Color colorFuchsia50 = Color(0xFFFDF4FF);
  static const Color colorFoundationPrimary500 = Color(0xFF00A788);
  static const Color colorViolate100 = Color(0xFFEDE9FE);
  static const Color shadowColor = Color(0x26000000);
  static const Color selectionColorPositive = Color(0xFF3AAFA2);
  static const Color selectionColorNegative = Color(0xFFFA6969);

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
    0xFF00A788,
    // 0% comes in here, this will be color picked if no shade is selected when defining a Color property which doesn’t require a swatch.
    <int, Color>{
      50: Color(0xFFE6F8F4), //10%
      100: Color(0xFFB0E9DE), //20%
      200: Color(0xFF8ADECE), //30%
      300: Color(0xFF54CFB8), //40%
      400: Color(0xFF33C5AA), //50%
      500: Color(0xFF00B795), //60%
      600: Color(0xFF00A788), //70%
      700: Color(0xFF00826A), //80%
      800: Color(0xFF006552), //80%
      900: Color(0xFF004D3F), //80%
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
