import 'package:flutter/material.dart';

/// Palette "noir pur" : fond #000000, surfaces à peine plus claires, texte blanc,
/// une seule couleur d'accent (blanc) et des couleurs sémantiques discrètes.
abstract final class AppColors {
  // Fonds et surfaces (du plus sombre au plus clair).
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF0A0A0A);
  static const surfaceRaised = Color(0xFF111111);
  static const surfaceHigh = Color(0xFF171717);
  static const surfaceHighest = Color(0xFF1F1F1F);

  // Bordures et séparateurs.
  static const border = Color(0xFF1C1C1C);
  static const borderStrong = Color(0xFF2A2A2A);

  // Texte.
  static const textPrimary = Color(0xFFFAFAFA);
  static const textSecondary = Color(0xFFA3A3A3);
  static const textTertiary = Color(0xFF6B6B6B);
  static const textDisabled = Color(0xFF474747);

  // Accent : blanc (boutons principaux, sélection).
  static const accent = Color(0xFFFFFFFF);
  static const onAccent = Color(0xFF000000);

  // Couleurs sémantiques.
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const info = Color(0xFF93C5FD);
  static const violet = Color(0xFFC4B5FD);

  /// Fond teinté (très discret) pour une pastille de couleur sémantique.
  static Color tint(Color color, [double alpha = 0.12]) => color.withValues(alpha: alpha);

  /// Couleur d'un score de matching (0-100).
  static Color score(num? value) {
    if (value == null) return textTertiary;
    if (value >= 75) return success;
    if (value >= 50) return warning;
    return danger;
  }
}
