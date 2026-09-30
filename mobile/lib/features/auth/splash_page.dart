import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/brand_mark.dart';

/// Affichée pendant la restauration de la session.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: 56),
          SizedBox(height: 28),
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary),
          ),
        ],
      ),
    ),
  );
}
