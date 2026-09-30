import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Logo : carré blanc arrondi avec un « G » noir.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.textPrimary,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    alignment: Alignment.center,
    child: Text(
      'G',
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size * 0.5,
        fontWeight: FontWeight.w700,
        color: AppColors.onAccent,
        letterSpacing: -1,
        height: 1,
      ),
    ),
  );
}
