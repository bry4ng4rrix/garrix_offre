import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/network/api_exception.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_providers.dart';
import 'data/admin_repository.dart';
import 'data/source_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/run_widgets.dart';
import 'widgets/source_form_sheet.dart';
import 'widgets/source_test_sheet.dart';

/// Détail d'une source : réglages, test, lancement d'une collecte, historique.
class SourceDetailPage extends ConsumerStatefulWidget {
  const SourceDetailPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<SourceDetailPage> createState() => _SourceDetailPageState();
}

enum _Menu { edit, delete }

class _SourceDetailPageState extends ConsumerState<SourceDetailPage> {
  bool _launching = false;
  bool _saving = false;

  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  void _reload() {
    ref.invalidate(sourceDetailProvider(widget.sourceId));
    ref.invalidate(sourceRunsProvider(widget.sourceId));
  }

  Future<void> _edit(Source source) async {
    final saved = await showSourceForm(context, source: source);
    if (saved != null) ref.invalidate(sourceDetailProvider(widget.sourceId));
  }

  Future<void> _delete(Source source) async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${source.name} » ?',
      message:
          'Son historique de collectes sera supprimé. Les offres déjà collectées sont conservées.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runAdmin(() async {
      await _repo.deleteSource(source.id);
      return true;
    }, success: 'Source supprimée');
    if (done == true && mounted) Navigator.of(context).pop();
  }

  /// Modification rapide d'un interrupteur (`PUT /sources/{id}`).
  Future<bool> _patch(Map<String, dynamic> body, {String? success}) async {
    if (!mounted) return false;
    setState(() => _saving = true);
    final saved = await runAdmin(() => _repo.updateSource(widget.sourceId, body), success: success);
    if (!mounted) return saved != null;
    setState(() => _saving = false);
    if (saved != null) ref.invalidate(sourceDetailProvider(widget.sourceId));
    return saved != null;
  }

  Future<void> _toggleTerms(bool value) async {
    if (value) {
      final ok = await confirmDialog(
        context,
        title: 'Conditions d\'utilisation vérifiées ?',
        message:
            'Confirmez que les conditions d\'utilisation du site autorisent la collecte '
            'automatique de ses offres.',
        confirmLabel: 'Je confirme',
      );
      if (!ok) return;
    }
    await _patch({'terms_reviewed': value});
  }

  void _test(Source source) =>
      showAppSheet<void>(context, expand: true, builder: (_) => SourceTestSheet(source: source));

  Future<void> _launch(Source source) async {
    setState(() => _launching = true);
    try {
      await _repo.runSource(source.id);
      showToast('Collecte lancée. Vous serez prévenu à la fin.', kind: ToastKind.success);
      ref.invalidate(sourceRunsProvider(widget.sourceId));
    } on ApiException catch (error) {
      await _handleRunError(source, error);
    } catch (error) {
      showAdminError(error);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  /// Erreurs de lancement : propose la correction quand c'est possible.
  Future<void> _handleRunError(Source source, ApiException error) async {
    switch (error.code) {
      case 'SOURCE_DISABLED':
        showToast(
          error.userMessage,
          kind: ToastKind.error,
          action: SnackBarAction(
            label: 'Activer',
            onPressed: () => _patch({'enabled': true}, success: 'Source activée'),
          ),
        );
      case 'SOURCE_TERMS_NOT_REVIEWED':
        if (!mounted) return;
        final ok = await confirmDialog(
          context,
          title: 'Conditions d\'utilisation',
          message:
              'La collecte d\'une page HTML n\'est permise que si les conditions d\'utilisation '
              'du site l\'autorisent. Les avez-vous vérifiées ?',
          confirmLabel: 'Oui, lancer',
          cancelLabel: 'Non',
        );
        if (ok && mounted && await _patch({'terms_reviewed': true})) {
          if (mounted) await _launch(source.copyWith(termsReviewed: true));
        }
      case 'WORKER_UNAVAILABLE':
        showToast(
          '${error.userMessage} Vérifiez le worker Celery sur le serveur.',
          kind: ToastKind.error,
        );
        ref.invalidate(sourceRunsProvider(widget.sourceId));
      default:
        showAdminError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      if ((event.type == 'scraping_run' || event.type == 'scraping_error') &&
          event.data['source_id']?.toString() == widget.sourceId) {
        _reload();
      }
    });

    final value = ref.watch(sourceDetailProvider(widget.sourceId));
    final source = value.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(source?.name ?? 'Source'),
        actions: [
          if (source != null)
            PopupMenuButton<_Menu>(
              tooltip: 'Plus d\'actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (item) => switch (item) {
                _Menu.edit => _edit(source),
                _Menu.delete => _delete(source),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _Menu.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Modifier'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _Menu.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    title: Text('Supprimer', style: TextStyle(color: AppColors.danger)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          const Gap(4),
        ],
      ),
      body: AsyncValueView<Source>(
        value: value,
        onRetry: _reload,
        data: (source) => PageListView(
          onRefresh: () async {
            _reload();
            await ref.read(sourceDetailProvider(widget.sourceId).future).catchError((_) => source);
          },
          children: [
            _Header(source: source),
            const Gap(16),
            _Actions(
              source: source,
              launching: _launching,
              onTest: () => _test(source),
              onLaunch: () => _launch(source),
            ),
            const SectionHeader('Réglages'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  SwitchRow(
                    title: 'Source active',
                    subtitle: 'Les offres de cette source sont acceptées.',
                    value: source.enabled,
                    onChanged: _saving
                        ? null
                        : (v) => _patch({
                            'enabled': v,
                          }, success: v ? 'Source activée' : 'Source désactivée'),
                  ),
                  const Divider(),
                  SwitchRow(
                    title: 'Collecte automatique',
                    subtitle: 'Incluse dans les collectes planifiées.',
                    value: source.scrapingEnabled,
                    onChanged: _saving ? null : (v) => _patch({'scraping_enabled': v}),
                  ),
                  const Divider(),
                  SwitchRow(
                    title: 'Conditions d\'utilisation vérifiées',
                    subtitle: 'Obligatoire pour collecter une page HTML.',
                    value: source.termsReviewed,
                    onChanged: _saving ? null : _toggleTerms,
                  ),
                ],
              ),
            ),
            const SectionHeader('Informations'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  InfoRow(
                    icon: Icons.link_rounded,
                    label: 'Site',
                    value: source.baseUrl,
                    onTap: source.baseUrl == null ? null : () => openLink(source.baseUrl!),
                  ),
                  InfoRow(
                    icon: Icons.extension_outlined,
                    label: 'Adapter',
                    value: source.adapter ?? 'Aucun (n8n, alertes email ou saisie manuelle)',
                  ),
                  InfoRow(
                    icon: Icons.low_priority_rounded,
                    label: 'Priorité',
                    value: '${source.priority} / 10',
                  ),
                  InfoRow(
                    icon: Icons.speed_rounded,
                    label: 'Limite de requêtes',
                    value: source.rateLimit == null
                        ? 'Par défaut'
                        : '${source.rateLimit} par minute',
                  ),
                  InfoRow(
                    icon: Icons.history_rounded,
                    label: 'Dernière collecte',
                    value: source.lastRunAt == null ? 'Jamais' : Fmt.dateTime(source.lastRunAt),
                  ),
                  InfoRow(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Dernier succès',
                    value: source.lastSuccessAt == null
                        ? 'Jamais'
                        : Fmt.dateTime(source.lastSuccessAt),
                  ),
                  InfoRow(
                    icon: Icons.event_outlined,
                    label: 'Créée / modifiée',
                    value: '${Fmt.date(source.createdAt)} · ${Fmt.relative(source.updatedAt)}',
                  ),
                ],
              ),
            ),
            if (source.hasError) ...[
              const Gap(12),
              NoteBox(
                title: 'Dernière erreur',
                message: source.lastError!,
                color: AppColors.danger,
                icon: Icons.error_outline_rounded,
              ),
            ],
            if (source.notes != null && source.notes!.trim().isNotEmpty) ...[
              const SectionHeader('Notes'),
              AppCard(
                child: SelectableText(
                  source.notes!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.45),
                ),
              ),
            ],
            const SectionHeader('Configuration'),
            JsonBlock(value: source.configuration, emptyLabel: 'Aucune configuration.'),
            const Gap(8),
            Text(
              'Lecture seule. Les clés secrètes (API, jetons) sont définies dans le .env du serveur.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            _RecentRuns(sourceId: widget.sourceId),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Gap(4),
        Text(source.name, style: theme.headlineSmall),
        const Gap(10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            source.enabled
                ? const Pill('Active', color: AppColors.success, icon: Icons.check_rounded)
                : const Pill('Désactivée', color: AppColors.danger),
            Pill(source.categoryLabel, icon: source.category?.icon),
            Pill(source.typeLabel),
            Pill(source.fetchMode == FetchMode.n8n ? 'Via n8n' : 'Via le serveur', filled: false),
            if (source.scrapingEnabled)
              const Pill('Collecte auto', color: AppColors.info, icon: Icons.schedule_rounded),
          ],
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.source,
    required this.launching,
    required this.onTest,
    required this.onLaunch,
  });

  final Source source;
  final bool launching;
  final VoidCallback onTest;
  final VoidCallback onLaunch;

  /// Explication quand le serveur refusera la collecte.
  String? get _hint {
    if (!source.hasAdapter) {
      return 'Aucun adapter : cette source est alimentée par n8n, les alertes email ou la saisie '
          'manuelle. Le serveur ne peut ni la tester ni la collecter.';
    }
    if (!source.enabled) return 'La source est désactivée : activez-la pour lancer une collecte.';
    if (source.type == SourceType.html && !source.termsReviewed) {
      return 'Collecte HTML : vérifiez d\'abord que les conditions d\'utilisation du site '
          'l\'autorisent.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Tester',
                icon: Icons.science_outlined,
                outlined: true,
                onPressed: source.hasAdapter ? onTest : null,
              ),
            ),
            const Gap(10),
            Expanded(
              child: PrimaryButton(
                label: 'Lancer une collecte',
                icon: Icons.play_arrow_rounded,
                loading: launching,
                onPressed: source.hasAdapter ? onLaunch : null,
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const Gap(12),
          NoteBox(
            message: hint,
            color: source.hasAdapter ? AppColors.warning : null,
            icon: source.hasAdapter ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
          ),
        ],
      ],
    );
  }
}

class _RecentRuns extends ConsumerWidget {
  const _RecentRuns({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(sourceRunsProvider(sourceId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Dernières collectes'),
        AsyncValueView<List<ScrapingRun>>(
          value: runs,
          onRetry: () => ref.invalidate(sourceRunsProvider(sourceId)),
          loading: const LoadingView(padding: EdgeInsets.symmetric(vertical: 32)),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Aucune collecte pour cette source.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final run in items) ...[
                      RunCard(
                        run: run,
                        showSource: false,
                        onTap: () => showRunDetail(
                          context,
                          runId: run.id,
                          linkToSource: false,
                          onChanged: (_) => ref.invalidate(sourceRunsProvider(sourceId)),
                        ),
                      ),
                      const Gap(10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
