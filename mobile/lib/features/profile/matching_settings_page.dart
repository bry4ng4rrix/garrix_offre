import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/profile_models.dart';
import 'data/profile_providers.dart';
import 'data/profile_repository.dart';
import 'widgets/profile_widgets.dart';

/// Poids des critères du matching (`GET/PUT /matching/settings`), réinitialisation et recalcul.
class MatchingSettingsPage extends ConsumerWidget {
  const MatchingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(matchingSettingsProvider);
    final value = settings.value;
    if (value != null) return _MatchingForm(key: const ValueKey('matching'), initial: value);
    return Scaffold(
      appBar: AppBar(title: const Text('Matching')),
      body: AsyncValueView<MatchingSettings>(
        value: settings,
        onRetry: () => ref.invalidate(matchingSettingsProvider),
        data: (_) => const SizedBox.shrink(),
      ),
    );
  }
}

class _MatchingForm extends ConsumerStatefulWidget {
  const _MatchingForm({super.key, required this.initial});

  final MatchingSettings initial;

  @override
  ConsumerState<_MatchingForm> createState() => _MatchingFormState();
}

class _MatchingFormState extends ConsumerState<_MatchingForm> {
  late MatchingSettings _weights = widget.initial;
  late MatchingSettings _saved = widget.initial;
  bool _saving = false;
  bool _resetting = false;
  bool _recalculating = false;

  bool get _dirty => _weights != _saved;
  bool get _busy => _saving || _resetting;

  Future<void> _onPop() async {
    if (_busy) return;
    if (!_dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = ref.read(profileRepositoryProvider);
    try {
      final saved = await ref.read(matchingSettingsProvider.notifier).save(_weights);
      if (mounted) {
        setState(() => _weights = _saved = saved);
      }
      showSavedWithRecalculate('Poids enregistrés', repository);
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Réinitialiser les poids ?',
      message: 'Les poids par défaut du serveur remplaceront vos réglages.',
      confirmLabel: 'Réinitialiser',
    );
    if (!confirmed || !mounted) return;
    setState(() => _resetting = true);
    final repository = ref.read(profileRepositoryProvider);
    try {
      final saved = await ref.read(matchingSettingsProvider.notifier).reset();
      if (mounted) {
        setState(() => _weights = _saved = saved);
      }
      showSavedWithRecalculate('Poids par défaut rétablis', repository);
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _recalculate() async {
    if (_dirty) {
      final saveFirst = await confirmDialog(
        context,
        title: 'Modifications non enregistrées',
        message:
            'Le recalcul utilise les poids enregistrés. Enregistrer d\'abord vos modifications ?',
        confirmLabel: 'Enregistrer et recalculer',
        cancelLabel: 'Recalculer sans',
      );
      if (!mounted) return;
      if (saveFirst) {
        await _save();
        if (!mounted || _dirty) return;
      }
    }
    setState(() => _recalculating = true);
    await recalculateScores(ref.read(profileRepositoryProvider));
    if (mounted) setState(() => _recalculating = false);
  }

  @override
  Widget build(BuildContext context) {
    // Fin d'un recalcul lancé en tâche de fond.
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event?.type != 'matching_recalculated') return;
      final count = parseInt(event!.data['jobs_matched']);
      showToast(
        count == null ? 'Scores recalculés' : 'Scores recalculés ($count offres)',
        kind: ToastKind.success,
      );
    });

    final theme = Theme.of(context).textTheme;
    final allIgnored = _weights.total == 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Matching'),
          actions: [
            TextButton(
              onPressed: _busy ? null : _reset,
              child: _resetting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Réinitialiser'),
            ),
            const Gap(8),
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          children: [
            PrimaryButton(
              label: _dirty ? 'Enregistrer' : 'Enregistré',
              icon: _dirty ? Icons.check_rounded : Icons.done_all_rounded,
              loading: _saving,
              onPressed: _dirty && !_resetting ? _save : null,
            ),
          ],
        ),
        body: PageListView(
          children: [
            const IntroText(
              'Chaque critère reçoit un poids de 0 à 100. Le score final est toujours ramené '
              'sur 100 : seule la proportion entre les poids compte. Un poids à 0 ignore le critère.',
            ),
            if (allIgnored) ...[
              const Gap(4),
              const InlineError(
                message: 'Tous les critères sont ignorés : aucune offre ne sera notée.',
              ),
            ],
            const Gap(AppSpacing.sm),
            _ShareBar(settings: _weights),
            const Gap(AppSpacing.lg),
            for (final criterion in MatchingCriterion.values) ...[
              _CriterionCard(
                criterion: criterion,
                weight: _weights.weightOf(criterion),
                share: _weights.shareOf(criterion),
                onChanged: (value) =>
                    setState(() => _weights = _weights.copyWith(criterion, value)),
              ),
              const Gap(10),
            ],
            const SectionHeader('Appliquer'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recalculer mes scores', style: theme.titleSmall),
                  const Gap(4),
                  Text(
                    'Recalcule la compatibilité de toutes les offres avec vos poids, votre profil '
                    'et vos préférences actuels.',
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  const Gap(14),
                  PrimaryButton(
                    label: 'Recalculer mes scores',
                    icon: Icons.refresh_rounded,
                    outlined: true,
                    loading: _recalculating,
                    onPressed: _busy ? null : _recalculate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Répartition du score entre les critères (barre segmentée en nuances de gris).
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.settings});

  final MatchingSettings settings;

  static const _shades = [
    Color(0xFFFAFAFA),
    Color(0xFFD4D4D4),
    Color(0xFFA3A3A3),
    Color(0xFF7A7A7A),
    Color(0xFF5C5C5C),
    Color(0xFF454545),
    Color(0xFF363636),
    Color(0xFF2A2A2A),
  ];

  @override
  Widget build(BuildContext context) {
    final criteria = [...MatchingCriterion.values]
      ..sort((a, b) => settings.weightOf(b).compareTo(settings.weightOf(a)));
    final visible = criteria.where((c) => settings.weightOf(c) > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (var i = 0; i < visible.length; i++)
                  Expanded(
                    flex: settings.weightOf(visible[i]),
                    child: Container(
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                      color: _shades[i % _shades.length],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Gap(10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (var i = 0; i < visible.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _shades[i % _shades.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Gap(6),
                  Text(
                    '${visible[i].label} ${settings.shareOf(visible[i]).round()} %',
                    style: theme.labelSmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Un critère : icône, libellé, part réelle du score, explication et curseur du poids.
class _CriterionCard extends StatelessWidget {
  const _CriterionCard({
    required this.criterion,
    required this.weight,
    required this.share,
    required this.onChanged,
  });

  final MatchingCriterion criterion;
  final int weight;
  final double share;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final ignored = weight == 0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                criterion.icon,
                size: 18,
                color: ignored ? AppColors.textTertiary : AppColors.textSecondary,
              ),
              const Gap(10),
              Expanded(
                child: Text(
                  criterion.label,
                  style: theme.titleSmall?.copyWith(
                    color: ignored ? AppColors.textTertiary : AppColors.textPrimary,
                  ),
                ),
              ),
              Pill(
                ignored ? 'Ignoré' : '${share.round()} % du score',
                dense: true,
                filled: !ignored,
              ),
            ],
          ),
          const Gap(6),
          Text(
            criterion.description,
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const Gap(6),
          SliderRow(
            label: 'Poids',
            value: weight.toDouble(),
            divisions: 20,
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}
