import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_labels.dart';
import '../data/admin_repository.dart';
import '../data/source_models.dart';
import 'admin_ui.dart';

/// Test « à blanc » d'une source (`POST /sources/{id}/test`) : rien n'est enregistré.
class SourceTestSheet extends ConsumerStatefulWidget {
  const SourceTestSheet({super.key, required this.source});

  final Source source;

  @override
  ConsumerState<SourceTestSheet> createState() => _SourceTestSheetState();
}

class _SourceTestSheetState extends ConsumerState<SourceTestSheet> {
  SourceTestResult? _result;
  Object? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await ref.read(adminRepositoryProvider).testSource(widget.source.id);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final result = _result;
    return DetailSheet(
      title: 'Test de la source',
      actions: [
        PrimaryButton(
          label: 'Relancer le test',
          icon: Icons.replay_rounded,
          outlined: true,
          loading: _running,
          onPressed: _run,
        ),
      ],
      children: [
        Text(
          '${widget.source.name} · aucune offre n\'est enregistrée pendant le test.',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        const Gap(16),
        if (_running && result == null)
          const Column(
            children: [
              LoadingView(padding: EdgeInsets.only(top: 48, bottom: 12)),
              Text('Récupération et analyse en cours...'),
            ],
          )
        else if (_error != null)
          NoteBox(
            title: 'Échec du test',
            message: adminErrorMessage(_error!),
            color: AppColors.danger,
            icon: Icons.error_outline_rounded,
          )
        else if (result != null) ...[
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Pages lues',
                  value: '${result.pagesFetched}',
                  icon: Icons.description_outlined,
                ),
              ),
              const Gap(10),
              Expanded(
                child: StatTile(
                  label: 'Offres analysées',
                  value: '${result.jobsParsed}',
                  icon: Icons.work_outline_rounded,
                  color: result.jobsParsed > 0 ? AppColors.success : AppColors.warning,
                ),
              ),
            ],
          ),
          if (result.errors.isNotEmpty) ...[
            const SheetSection('Messages'),
            for (final error in result.errors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        error,
                        style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          SheetSection('Aperçu (${result.preview.length})'),
          if (result.preview.isEmpty)
            Text(
              'Aucune offre extraite : vérifiez la configuration de l\'adapter.',
              style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          else
            for (final job in result.preview) ...[_TestedJobCard(job: job), const Gap(10)],
        ],
      ],
    );
  }
}

class _TestedJobCard extends StatelessWidget {
  const _TestedJobCard({required this.job});

  final TestedJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final meta = [
      job.companyName,
      job.location,
      if (job.isRemote) 'Télétravail',
      if (job.isHybrid) 'Hybride',
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' · ');
    final link = job.sourceUrl ?? job.applicationUrl;

    return AppCard(
      color: AppColors.surfaceRaised,
      onTap: link == null ? null : () => openLink(link),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.title, style: theme.titleSmall),
          if (meta.isNotEmpty) ...[
            const Gap(4),
            Text(meta, style: theme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
          const Gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (job.contractType != null) Pill(job.contractType!, dense: true),
              if (job.experienceLevel != null) Pill(job.experienceLevel!, dense: true),
              if (job.hasSalary)
                Pill(
                  Fmt.salary(
                    min: job.salaryMin,
                    max: job.salaryMax,
                    currency: job.salaryCurrency,
                    period: job.salaryPeriod,
                    raw: job.salaryRaw,
                  ),
                  dense: true,
                  color: AppColors.success,
                ),
              if (job.publishedAt != null)
                Pill('Publiée ${Fmt.relative(job.publishedAt)}', dense: true, filled: false),
            ],
          ),
          if (job.skills.isNotEmpty) ...[
            const Gap(8),
            Text(
              job.skills.take(10).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (job.qualityIssues.isNotEmpty) ...[
            const Gap(8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final issue in job.qualityIssues)
                  Pill(issue, dense: true, color: AppColors.warning),
              ],
            ),
          ],
          if (job.applicationEmail != null) ...[
            const Gap(6),
            Text(
              'Candidature : ${job.applicationEmail}',
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
