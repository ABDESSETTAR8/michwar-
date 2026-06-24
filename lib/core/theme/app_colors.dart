import 'package:flutter/material.dart';

/// MICHWAR brand palette.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0A6E57); // deep teal-green
  static const Color primaryDark = Color(0xFF064D3D);
  static const Color secondary = Color(0xFFFFC233); // taxi-yellow accent
  static const Color background = Color(0xFFF6F8F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF161B19);
  static const Color textSecondary = Color(0xFF6B7570);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFD32F2F);
  static const Color sos = Color(0xFFE11D48);
  static const Color online = Color(0xFF22C55E);
  static const Color offline = Color(0xFF9CA3AF);

  // Heatmap gradient stops (low -> high demand).
  static const List<Color> heatmapGradient = [
    Color(0x0022C55E),
    Color(0xFFFACC15),
    Color(0xFFF97316),
    Color(0xFFDC2626),
  ];

  // Loyalty tier colors.
  static const Color tierStandard = Color(0xFF94A3B8);
  static const Color tierEco = Color(0xFF22C55E);
  static const Color tierPremium = Color(0xFF7C3AED);
}
