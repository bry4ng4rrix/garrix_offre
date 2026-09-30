import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/job_models.dart';
import '../job_labels.dart';
import '../jobs_providers.dart';

/// Ouvre l'analyse de l'offre (`POST /ai/jobs/{id}/analyze`) dans une feuille.
Future<void> showJobAnalysisSheet(BuildContext context, String jobId) =>
    showAppSheet<void>(context, expand: true, builder: (_) => JobAnalysisSheet(jobId: jobId));

class JobAnalysisSheet extends ConsumerWidget {
  const JobAnalysisSheet({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(jobAnalysisProvider(jobId));
    final by = analysis.value?.generatedBy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Analyse de l\'offre',
          trailing: by == null
              ? null
              : Pill(
                  by == GeneratedBy.ai ? 'Générée par l\'IA' : 'Analyse automatique',
                  icon: by == GeneratedBy.ai ? Icons.auto_awesome_rounded : Icons.rule_rounded,
                  color: by == GeneratedBy.ai ? AppColors.violet : null,
                  dense: true,
                ),
        ),
        Expanded(
          child: AsyncValueView<JobAnalysis>(
            value: analysis,
            onRetry: () => ref.invalidate(jobAnalysisProvider(jobId)),
            loading: const _Analyzing(),
            data: (data) => _AnalysisContent(analysis: data),
          ),
        ),
      ],
    );
  }
}

class _Analyzing extends StatelessWidget {
  const _Analyzing();

  @override
  Widget build(BuildContext context) => ListView(
    primary: true,
    children: [
      const LoadingView(padding: EdgeInsets.only(top: 64, bottom: 16)),
      Text(
        'Analyse en cours…',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}

class _AnalysisContent extends ConsumerWidget {
  const _AnalysisContent({required this.analysis});

  final JobAnalysis analysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final labels = ref.watch(jobLabelsProvider);
    final a = analysis;
    final profile = <(IconData, String, String)>[
      if (labels.level(a.experienceLevel) != null)
        (Icons.trending_up_rounded, 'Niveau', labels.level(a.experienceLevel)!),
      if ((a.minYearsExperience ?? 0) > 0)
        (
          Icons.timelapse_rounded,
          'Expérience minimum',
          a.minYearsExperience == 1 ? '1 an' : '${a.minYearsExperience} ans',
        ),
      if (JobLabels.remotePolicy(a.remotePolicy) != null)
        (Icons.home_work_outlined, 'Télétravail', JobLabels.remotePolicy(a.remotePolicy)!),
      if (a.languages.isNotEmpty)
        (Icons.translate_rounded, 'Langues', a.languages.map(JobLabels.language).join(', ')),
      if (a.education != null) (Icons.school_outlined, 'Formation', a.education!),
    ];

    return ListView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 32),
      children: [
        if (a.summary.isNotEmpty)
          SelectableText(a.summary, style: theme.bodyLarge?.copyWith(height: 1.6)),
        if (a.highlights.isNotEmpty) ...[
          const SectionHeader('Points forts'),
          for (final item in a.highlights)
            _Bullet(item, icon: Icons.check_rounded, color: AppColors.success),
        ],
        if (a.redFlags.isNotEmpty) ...[
          const SectionHeader('Points de vigilance'),
          for (final item in a.redFlags)
            _Bullet(item, icon: Icons.warning_amber_rounded, color: AppColors.warning),
        ],
        if (a.responsibilities.isNotEmpty) ...[
          const SectionHeader('Missions'),
          for (final item in a.responsibilities) _Bullet(item),
        ],
        if (a.requiredSkills.isNotEmpty) ...[
          const SectionHeader('Compétences requises'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final skill in a.requiredSkills) Pill(skill)],
          ),
        ],
        if (a.preferredSkills.isNotEmpty) ...[
          const SectionHeader('Compétences appréciées'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final skill in a.preferredSkills) Pill(skill, filled: false)],
          ),
        ],
        if (profile.isNotEmpty) ...[
          const SectionHeader('Profil recherché'),
          for (final (icon, label, value) in profile)
            InfoRow(icon: icon, label: label, value: value),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.icon = Icons.remove_rounded, this.color = AppColors.textTertiary});

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const Gap(10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}
