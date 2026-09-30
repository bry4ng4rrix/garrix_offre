import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/admin_providers.dart';
import '../data/admin_repository.dart';
import '../data/source_models.dart';
import 'admin_ui.dart';

/// Carte et détail d'une collecte (listes des collectes, détail d'une source, page Système).

String runDurationLabel(ScrapingRun run) {
  final duration = run.duration;
  if (duration == null) return run.isActive ? 'en cours' : '—';
  return Fmt.duration(duration.inMilliseconds / 1000);
}

/// Pastille de statut d'une collecte.
class RunStatusPill extends StatelessWidget {
  const RunStatusPill({super.key, required this.run, this.dense = true});

  final ScrapingRun run;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final status = run.status;
    return Pill(
      status?.label ?? run.statusValue,
      color: status?.color,
      dense: dense,
      icon: run.isActive ? Icons.autorenew_rounded : null,
    );
  }
}

/// Carte résumée d'une collecte.
class RunCard extends StatelessWidget {
  const RunCard({super.key, required this.run, this.onTap, this.showSource = true});

  final ScrapingRun run;
  final VoidCallback? onTap;

  /// false dans le détail d'une source (le nom est déjà affiché).
  final bool showSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final title = showSource ? (run.sourceName ?? 'Source inconnue') : Fmt.dateTime(run.createdAt);
    final meta = [
      run.trigger?.label ?? run.triggerValue,
      if (showSource) Fmt.relative(run.createdAt),
      if (run.duration != null) runDurationLabel(run),
    ].join(' · ');

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleSmall,
                ),
              ),
              const Gap(10),
              RunStatusPill(run: run),
            ],
          ),
          const Gap(4),
          Text(meta, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          const Gap(10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              MetricText(value: run.jobsFound, label: run.jobsFound > 1 ? 'trouvées' : 'trouvée'),
              MetricText(value: run.jobsCreated, label: run.jobsCreated > 1 ? 'créées' : 'créée'),
              if (run.jobsUpdated > 0) MetricText(value: run.jobsUpdated, label: 'mises à jour'),
              if (run.jobsDuplicates > 0)
                MetricText(
                  value: run.jobsDuplicates,
                  label: run.jobsDuplicates > 1 ? 'doublons' : 'doublon',
                ),
              if (run.jobsInvalid > 0)
                MetricText(
                  value: run.jobsInvalid,
                  label: run.jobsInvalid > 1 ? 'invalides' : 'invalide',
                  color: AppColors.warning,
                ),
            ],
          ),
          if (run.errorMessage != null && run.errorMessage!.trim().isNotEmpty) ...[
            const Gap(8),
            Text(
              run.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ouvre le détail d'une collecte. [onChanged] reçoit la collecte après annulation.
Future<void> showRunDetail(
  BuildContext context, {
  required String runId,
  ValueChanged<ScrapingRun>? onChanged,
  bool linkToSource = true,
}) => showAppSheet<void>(
  context,
  expand: true,
  builder: (_) => RunDetailSheet(runId: runId, onChanged: onChanged, linkToSource: linkToSource),
);

/// Détail d'une collecte (`GET /scraping/runs/{id}`), avec annulation si elle est active.
class RunDetailSheet extends ConsumerStatefulWidget {
  const RunDetailSheet({super.key, required this.runId, this.onChanged, this.linkToSource = true});

  final String runId;
  final ValueChanged<ScrapingRun>? onChanged;
  final bool linkToSource;

  @override
  ConsumerState<RunDetailSheet> createState() => _RunDetailSheetState();
}

class _RunDetailSheetState extends ConsumerState<RunDetailSheet> {
  bool _cancelling = false;

  Future<void> _cancel(ScrapingRun run) async {
    final ok = await confirmDialog(
      context,
      title: 'Annuler la collecte ?',
      message: 'La collecte de « ${run.sourceName ?? 'cette source'} » sera marquée comme annulée.',
      confirmLabel: 'Annuler la collecte',
      cancelLabel: 'Retour',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _cancelling = true);
    final updated = await runAdmin(
      () => ref.read(adminRepositoryProvider).cancelRun(run.id),
      success: 'Collecte annulée',
    );
    if (!mounted) return;
    setState(() => _cancelling = false);
    if (updated != null) {
      ref.invalidate(runDetailProvider(run.id));
      widget.onChanged?.call(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mise à jour automatique quand la collecte se termine.
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      if ((event.type == 'scraping_run' || event.type == 'scraping_error') &&
          event.data['run_id']?.toString() == widget.runId) {
        ref.invalidate(runDetailProvider(widget.runId));
      }
    });

    final value = ref.watch(runDetailProvider(widget.runId));
    final run = value.value;
    return DetailSheet(
      title: 'Collecte',
      actions: [
        if (run != null && run.isActive)
          PrimaryButton(
            label: 'Annuler la collecte',
            icon: Icons.stop_circle_outlined,
            outlined: true,
            loading: _cancelling,
            onPressed: () => _cancel(run),
          ),
      ],
      children: [
        AsyncValueView<ScrapingRun>(
          value: value,
          onRetry: () => ref.invalidate(runDetailProvider(widget.runId)),
          data: (run) => _RunDetailBody(run: run, linkToSource: widget.linkToSource),
        ),
      ],
    );
  }
}

class _RunDetailBody extends StatelessWidget {
  const _RunDetailBody({required this.run, required this.linkToSource});

  final ScrapingRun run;
  final bool linkToSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final errors = run.detailErrors;
    final extraDetails = Map<String, dynamic>.of(run.details)..remove('errors');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(run.sourceName ?? 'Source inconnue', style: theme.headlineSmall)),
            const Gap(10),
            RunStatusPill(run: run, dense: false),
          ],
        ),
        const Gap(6),
        Text(
          'Déclenchée ${run.trigger == ScrapingTrigger.manual ? 'manuellement' : 'par ${run.trigger?.label ?? run.triggerValue}'} · ${Fmt.relative(run.createdAt)}',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        const Gap(18),
        ResponsiveGrid(
          minItemWidth: 96,
          maxColumns: 5,
          spacing: 8,
          children: [
            _CountTile(label: 'Trouvées', value: run.jobsFound),
            _CountTile(label: 'Créées', value: run.jobsCreated, color: AppColors.success),
            _CountTile(label: 'Mises à jour', value: run.jobsUpdated),
            _CountTile(label: 'Doublons', value: run.jobsDuplicates),
            _CountTile(
              label: 'Invalides',
              value: run.jobsInvalid,
              color: run.jobsInvalid > 0 ? AppColors.warning : null,
            ),
          ],
        ),
        if (run.errorMessage != null && run.errorMessage!.trim().isNotEmpty) ...[
          const Gap(16),
          NoteBox(
            title: 'Erreur',
            message: run.errorMessage!,
            color: AppColors.danger,
            icon: Icons.error_outline_rounded,
          ),
        ],
        if (errors.isNotEmpty) ...[
          const SheetSection('Avertissements'),
          for (final error in errors)
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
        const SheetSection('Chronologie'),
        InfoRow(
          icon: Icons.add_circle_outline_rounded,
          label: 'Créée',
          value: Fmt.dateTime(run.createdAt),
        ),
        InfoRow(
          icon: Icons.play_circle_outline_rounded,
          label: 'Démarrée',
          value: Fmt.dateTime(run.startedAt),
        ),
        InfoRow(icon: Icons.flag_outlined, label: 'Terminée', value: Fmt.dateTime(run.finishedAt)),
        InfoRow(icon: Icons.timer_outlined, label: 'Durée', value: runDurationLabel(run)),
        if (run.externalExecutionId != null)
          InfoRow(icon: Icons.tag_rounded, label: 'Exécution n8n', value: run.externalExecutionId),
        if (linkToSource && run.sourceId.isNotEmpty) ...[
          const Gap(8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(Routes.adminSource(run.sourceId));
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Voir la source'),
          ),
        ],
        if (extraDetails.isNotEmpty) ...[
          const SheetSection('Détails techniques'),
          JsonBlock(value: extraDetails),
        ],
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Fmt.number(value),
            style: theme.titleLarge?.copyWith(color: color ?? AppColors.textPrimary),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
