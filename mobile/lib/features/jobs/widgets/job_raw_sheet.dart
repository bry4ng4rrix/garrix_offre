import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/job_models.dart';
import '../job_labels.dart';
import '../jobs_providers.dart';
import 'external_links.dart';

/// Données brutes et normalisées d'une offre (admin, débogage des parsers).
Future<void> showJobRawSheet(BuildContext context, String jobId) =>
    showAppSheet<void>(context, expand: true, builder: (_) => JobRawSheet(jobId: jobId));

class JobRawSheet extends ConsumerStatefulWidget {
  const JobRawSheet({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<JobRawSheet> createState() => _JobRawSheetState();
}

class _JobRawSheetState extends ConsumerState<JobRawSheet> {
  bool _normalized = false;

  static const _encoder = JsonEncoder.withIndent('  ');

  String _pretty(Map<String, dynamic> data) {
    try {
      return _encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(jobRawProvider(widget.jobId));
    final data = raw.value;
    final text = data == null ? null : _pretty(_normalized ? data.normalizedData : data.rawData);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Données de l\'offre',
          trailing: text == null
              ? null
              : IconButton(
                  tooltip: 'Copier',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () => copyText(text),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Brutes')),
              ButtonSegment(value: true, label: Text('Normalisées')),
            ],
            selected: {_normalized},
            onSelectionChanged: (value) => setState(() => _normalized = value.first),
          ),
        ),
        Expanded(
          child: AsyncValueView<JobRaw>(
            value: raw,
            onRetry: () => ref.invalidate(jobRawProvider(widget.jobId)),
            data: (data) => ListView(
              primary: true,
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 32),
              children: [
                if (data.qualityIssues.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final issue in data.qualityIssues)
                        Pill(JobLabels.qualityIssue(issue), color: AppColors.warning, dense: true),
                    ],
                  ),
                  const Gap(12),
                ],
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SelectableText(
                    text ?? '',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (data.sources.isNotEmpty) ...[
                  const SectionHeader('Sources'),
                  for (final source in data.sources)
                    InfoRow(
                      icon: source.category?.icon ?? Icons.public_rounded,
                      label: source.name ?? 'Source',
                      value: source.url ?? source.externalId,
                      onTap: source.url == null ? null : () => openExternalUrl(source.url!),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
