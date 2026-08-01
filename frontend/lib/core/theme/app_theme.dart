import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFF0B3D91);   // deep trade-blue (like the roadmap banner)
  static const Color secondary = Color(0xFF1B8A5A);  // export-green
  static const Color accent = Color(0xFFFF7A00);     // logistics-orange
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color heldBlue = Color(0xFF2563EB); // escrow-held status color
}

/// Dark-mode counterparts — same semantic roles as [AppColors], tuned for a dark surface.
class AppColorsDark {
  static const Color primary = Color(0xFF3B6FD4);
  static const Color secondary = Color(0xFF2FBE7E);
  static const Color accent = Color(0xFFFF9433);
  static const Color background = Color(0xFF0F1115);
  static const Color surface = Color(0xFF1A1D24);
  static const Color textPrimary = Color(0xFFECEDF0);
  static const Color textSecondary = Color(0xFF9AA1AC);
  static const Color success = Color(0xFF3FCB6E);
  static const Color warning = Color(0xFFFBBF3F);
  static const Color error = Color(0xFFF06058);
  static const Color heldBlue = Color(0xFF5B8DEF);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColorsDark.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColorsDark.primary,
        secondary: AppColorsDark.secondary,
        error: AppColorsDark.error,
        surface: AppColorsDark.surface,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColorsDark.textPrimary,
        displayColor: AppColorsDark.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColorsDark.surface,
        foregroundColor: AppColorsDark.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorsDark.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorsDark.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade800),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade800),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColorsDark.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColorsDark.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade800),
        ),
      ),
    );
  }
}

/// Maps order_status strings from backend -> display color, used across all 3 dashboards.
Color statusColor(String status) {
  switch (status) {
    case 'created':
      return AppColors.textSecondary;
    case 'payment_held':
      return AppColors.heldBlue;
    case 'accepted':
    case 'shipped':
    case 'in_transit':
      return AppColors.accent;
    case 'delivered':
      return AppColors.warning;
    case 'confirmed':
    case 'payment_released':
      return AppColors.success;
    case 'disputed':
      return AppColors.error;
    case 'cancelled':
    case 'refunded':
      return Colors.grey;
    default:
      return AppColors.textSecondary;
  }
}

String statusLabel(String status) {
  return status
      .split('_')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
