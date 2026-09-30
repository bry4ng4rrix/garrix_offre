import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/document_models.dart';

/// Carte d'un document : type, taille, date, badges (principal, inactif, langue, poste ciblé).
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    this.onTap,
    this.onMore,
    this.showType = true,
  });

  final UserDocument document;
  final VoidCallback? onTap;
  final VoidCallback? onMore;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final doc = document;
    final pills = <Widget>[
      if (doc.isPrimary)
        const Pill('Principal', color: AppColors.success, icon: Icons.star_rounded, dense: true),
      if (!doc.isActive) const Pill('Inactif', filled: false, dense: true),
      if (showType) Pill(doc.type.label, dense: true),
      if (doc.language != null) Pill(languageLabel(doc.language!), dense: true),
      if (doc.targetJobTitle != null)
        Pill(doc.targetJobTitle!, icon: Icons.work_outline_rounded, dense: true),
    ];
    return Opacity(
      opacity: doc.isActive ? 1 : 0.6,
      child: AppCard(
        onTap: onTap,
        onLongPress: onMore,
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, 4, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(doc.type.icon, size: 18, color: AppColors.textSecondary),
                  const Gap(2),
                  Text(
                    doc.extension.toUpperCase(),
                    style: theme.labelSmall?.copyWith(
                      fontSize: 8.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall,
                  ),
                  const Gap(2),
                  Text(
                    '${doc.originalFilename} · ${Fmt.fileSize(doc.sizeBytes)} · ${Fmt.date(doc.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  if (pills.isNotEmpty) ...[
                    const Gap(10),
                    Wrap(spacing: 6, runSpacing: 6, children: pills),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Actions',
              onPressed: onMore,
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
