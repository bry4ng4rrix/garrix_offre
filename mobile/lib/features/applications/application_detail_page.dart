import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ui.dart';
import '../documents/data/documents_repository.dart';
import 'application_providers.dart';
import 'data/application_models.dart';
import 'data/applications_repository.dart';
import 'widgets/common.dart';
import 'widgets/cv_picker_sheet.dart';
import 'widgets/draft_sheets.dart';
import 'widgets/generated_text_sheet.dart';
import 'widgets/history_timeline.dart';
import 'widgets/prepare_sheet.dart';
import 'widgets/responses.dart';
import 'widgets/status_change_sheet.dart';
import 'widgets/status_pipeline.dart';
import 'widgets/submit_sheet.dart';

enum _MenuAction { generate, details, status, delete }

/// Détail d'une candidature : « Préparer → Valider → Suivre ».
///
/// L'envoi (statut « Envoyée ») passe toujours par la feuille « Valider l'envoi » et sa case
/// de confirmation explicite : jamais d'envoi automatique.
class ApplicationDetailPage extends ConsumerStatefulWidget {
  const ApplicationDetailPage({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<ApplicationDetailPage> createState() => _ApplicationDetailPageState();
}

class _ApplicationDetailPageState extends ConsumerState<ApplicationDetailPage> {
  String get _id => widget.applicationId;

  ApplicationsRepository get _repository => ref.read(applicationsRepositoryProvider);

  /// Remplace la candidature affichée par celle renvoyée par une action.
  void _apply(Application? updated, {String? success}) {
    if (updated == null || !mounted) return;
    ref.read(applicationControllerProvider(_id).notifier).set(updated);
    ref.invalidate(applicationHistoryProvider(_id));
    if (success != null) showToast(success, kind: ToastKind.success);
  }

  Future<void> _refresh() async {
    ref.invalidate(applicationControllerProvider(_id));
    ref.invalidate(applicationHistoryProvider(_id));
    ref.invalidate(applicationResponsesProvider(_id));
    try {
      await ref.read(applicationControllerProvider(_id).future);
    } catch (_) {
      // L'erreur est affichée par la page.
    }
  }

  // --- Actions principales ---

  Future<void> _prepare(Application app) async {
    final result = await showAppSheet<Application>(
      context,
      builder: (_) => PrepareSheet(application: app),
    );
    _apply(result, success: 'Candidature prête : relisez le dossier avant de valider l\'envoi.');
  }

  Future<void> _submit(Application app) async {
    final result = await showAppSheet<Application>(
      context,
      expand: true,
      builder: (_) => SubmitSheet(application: app),
    );
    _apply(result); // le message de succès est affiché par la feuille
  }

  Future<void> _changeStatus(Application app) async {
    final result = await showAppSheet<Application>(
      context,
      builder: (_) => StatusChangeSheet(application: app),
    );
    _apply(result, success: result == null ? null : 'Statut : ${result.status.label}');
  }

  Future<void> _edit(Widget Function() sheet, {bool expand = false}) async {
    final result = await showAppSheet<Application>(
      context,
      expand: expand,
      builder: (_) => sheet(),
    );
    _apply(result, success: 'Enregistré');
  }

  Future<void> _pickCv(Application app) async {
    final picked = await showAppSheet<({String? id})>(
      context,
      builder: (_) => CvPickerSheet(selectedId: app.cvDocumentId),
    );
    if (picked == null || picked.id == app.cvDocumentId) return;
    final result = await runAction(
      () => _repository.update(app.id, ApplicationUpdate.cv(picked.id)),
    );
    _apply(result, success: picked.id == null ? 'CV retiré' : 'CV mis à jour');
  }

  Future<void> _generate(Application app) async {
    final kind = await showAppSheet<GenerationKind>(
      context,
      builder: (_) => const GenerateKindSheet(),
    );
    if (kind == null || !mounted) return;
    final text = await generateAndPreview(
      context,
      ref,
      applicationId: app.id,
      kind: kind,
      canUse: kind == GenerationKind.coverLetter || kind == GenerationKind.applicationEmail,
    );
    final update = text == null ? null : ApplicationUpdate.fromGenerated(text);
    if (update == null) return;
    final result = await runAction(() => _repository.update(app.id, update));
    _apply(result, success: 'Texte repris dans le brouillon');
  }

  Future<void> _addResponse(Application app) async {
    final created = await showAppSheet<RecruiterResponse>(
      context,
      expand: true,
      builder: (_) => ResponseFormSheet(application: app),
    );
    if (created == null || !mounted) return;
    ref.invalidate(applicationResponsesProvider(_id));
    ref.invalidate(unreadResponsesCountProvider);
    showToast('Réponse enregistrée : ${created.responseType.label}', kind: ToastKind.success);
    // Affiche l'analyse (et le statut suggéré) tout de suite.
    await showResponseDetail(context, created, showApplicationLink: false);
  }

  Future<void> _delete(Application app) async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer la candidature ?',
      message: 'Les brouillons et l\'historique de « ${app.displayTitle} » seront supprimés.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final router = GoRouter.of(context);
    final done = await runAction(() async {
      await _repository.delete(app.id);
      return true;
    }, success: 'Candidature supprimée');
    if (done == true && mounted) router.pop();
  }

  void _onMenu(_MenuAction action, Application app) => switch (action) {
    _MenuAction.generate => _generate(app),
    _MenuAction.details => _edit(() => DetailsSheet(application: app)),
    _MenuAction.status => _changeStatus(app),
    _MenuAction.delete => _delete(app),
  };

  @override
  Widget build(BuildContext context) {
    // Temps réel : statut changé ailleurs (n8n, autre appareil) ou nouvelle réponse.
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null || event.data['application_id']?.toString() != _id) return;
      if (event.type == 'application_status') {
        ref.invalidate(applicationControllerProvider(_id));
        ref.invalidate(applicationHistoryProvider(_id));
      } else if (event.type == 'recruiter_response') {
        ref.invalidate(applicationResponsesProvider(_id));
      }
    });

    final value = ref.watch(applicationControllerProvider(_id));
    final app = value.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidature'),
        actions: [
          if (app != null)
            PopupMenuButton<_MenuAction>(
              tooltip: 'Plus d\'actions',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) => _onMenu(action, app),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _MenuAction.generate, child: Text('Générer un texte')),
                if (app.jobId == null)
                  const PopupMenuItem(
                    value: _MenuAction.details,
                    child: Text('Modifier l\'intitulé'),
                  ),
                if (app.status.isDraft && app.manualTransitions.isNotEmpty)
                  const PopupMenuItem(value: _MenuAction.status, child: Text('Changer le statut')),
                if (app.status.isDraft)
                  const PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Text('Supprimer', style: TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
          const Gap(8),
        ],
      ),
      body: AsyncValueView<Application>(
        value: value,
        onRetry: _refresh,
        data: (app) => PageListView(
          onRefresh: _refresh,
          children: [
            _Header(application: app),
            const Gap(20),
            StatusPipeline(application: app),
            if (app.job != null) ...[const SectionHeader('Offre'), _JobCard(job: app.job!)],
            if (app.submittedAt != null) ...[
              const SectionHeader('Envoi'),
              _SubmissionCard(application: app),
            ],
            const SectionHeader('Dossier'),
            _CvCard(application: app, onTap: () => _pickCv(app)),
            const Gap(10),
            _DraftCard(
              icon: Icons.article_outlined,
              title: 'Lettre de motivation',
              preview: app.coverLetterText,
              placeholder: 'Pas encore rédigée',
              onTap: () => _edit(() => CoverLetterSheet(application: app), expand: true),
              onCopy: app.coverLetterText == null
                  ? null
                  : () => copyText(app.coverLetterText!, message: 'Lettre copiée'),
            ),
            const Gap(10),
            _DraftCard(
              icon: Icons.mail_outline_rounded,
              title: 'Email de candidature',
              value: app.emailSubject,
              preview: app.emailBody,
              placeholder: 'Pas encore rédigé',
              onTap: () => _edit(() => EmailDraftSheet(application: app), expand: true),
              onCopy: app.emailBody == null
                  ? null
                  : () => copyText(
                      [?app.emailSubject, app.emailBody!].join('\n\n'),
                      message: 'Email copié',
                    ),
            ),
            const Gap(10),
            _DraftCard(
              icon: Icons.sticky_note_2_outlined,
              title: 'Notes et relance',
              value: app.followUpAt == null
                  ? null
                  : 'Relance prévue le ${Fmt.date(app.followUpAt)}',
              preview: app.notes,
              placeholder: 'Aucune note',
              onTap: () => _edit(() => NotesSheet(application: app)),
            ),
            SectionHeader(
              'Réponses des recruteurs',
              action: app.status.isDraft ? null : 'Ajouter',
              onAction: () => _addResponse(app),
            ),
            _ResponsesSection(applicationId: app.id),
            const SectionHeader('Historique'),
            _HistorySection(applicationId: app.id),
          ],
        ),
      ),
      bottomNavigationBar: app == null ? null : _bottomBar(app),
    );
  }

  /// Action principale selon le statut.
  Widget? _bottomBar(Application app) => switch (app.status) {
    ApplicationStatus.notApplied || ApplicationStatus.preparing => BottomActionBar(
      children: [
        PrimaryButton(
          label: 'Préparer la candidature',
          icon: Icons.auto_awesome_rounded,
          onPressed: () => _prepare(app),
        ),
      ],
    ),
    ApplicationStatus.ready => BottomActionBar(
      children: [
        PrimaryButton(
          label: 'Valider l\'envoi',
          icon: Icons.send_rounded,
          onPressed: () => _submit(app),
        ),
      ],
    ),
    ApplicationStatus.submitted ||
    ApplicationStatus.followUp ||
    ApplicationStatus.interview ||
    ApplicationStatus.offer => BottomActionBar(
      children: [
        PrimaryButton(
          label: 'Réponse reçue',
          icon: Icons.mark_email_unread_outlined,
          outlined: true,
          onPressed: () => _addResponse(app),
        ),
        PrimaryButton(
          label: 'Changer le statut',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => _changeStatus(app),
        ),
      ],
    ),
    ApplicationStatus.rejected || ApplicationStatus.withdrawn => null,
  };
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.application});
  final Application application;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final app = application;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ApplicationStatusPill(app.status),
              if (app.job?.isExpired == true)
                const Pill(
                  'Offre expirée',
                  color: AppColors.warning,
                  icon: Icons.event_busy_outlined,
                ),
              if (app.isFollowUpDue())
                const Pill(
                  'Relance à faire',
                  color: AppColors.warning,
                  icon: Icons.notification_important_outlined,
                ),
            ],
          ),
          const Gap(14),
          Text(app.displayTitle, style: theme.headlineSmall),
          const Gap(4),
          Text(
            app.companyName ?? 'Entreprise non précisée',
            style: theme.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const Gap(6),
          Text(
            'Créée le ${Fmt.date(app.createdAt)} · mise à jour ${Fmt.relative(app.updatedAt)}',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final ApplicationJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final url = job.applicationUrl;
    final email = job.applicationEmail;
    return AppCard(
      onTap: () => context.push(Routes.job(job.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.work_outline_rounded),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleSmall,
                    ),
                    Text(
                      'Voir l\'offre',
                      style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (job.isExpired) const Pill('Expirée', color: AppColors.warning, dense: true),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ],
          ),
          if (url != null || email != null) ...[
            const Gap(10),
            const Divider(),
            const Gap(4),
            if (url != null)
              InfoRow(
                icon: Icons.language_rounded,
                label: 'Candidater sur le site',
                value: Uri.tryParse(url)?.host ?? url,
                onTap: () => openExternal(Uri.parse(url)),
              ),
            if (email != null)
              InfoRow(
                icon: Icons.alternate_email_rounded,
                label: 'Email de candidature',
                value: email,
                onTap: () => copyText(email, message: 'Adresse copiée'),
              ),
          ],
        ],
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.application});
  final Application application;

  @override
  Widget build(BuildContext context) {
    final app = application;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
      child: Column(
        children: [
          InfoRow(
            icon: Icons.send_outlined,
            label: 'Envoyée le',
            value: Fmt.dateTime(app.submittedAt),
          ),
          if (app.submissionMethod != null)
            InfoRow(icon: Icons.route_outlined, label: 'Moyen', value: app.submissionMethod!.label),
          if (app.submissionReference != null)
            InfoRow(
              icon: Icons.tag_rounded,
              label: 'Référence',
              value: app.submissionReference,
              onTap: () => copyText(app.submissionReference!, message: 'Référence copiée'),
            ),
          if (app.followUpAt != null)
            InfoRow(
              icon: Icons.schedule_rounded,
              label: 'Relance prévue',
              value: Fmt.date(app.followUpAt),
            ),
          if (app.lastContactAt != null)
            InfoRow(
              icon: Icons.forum_outlined,
              label: 'Dernier contact',
              value: Fmt.dateTime(app.lastContactAt),
            ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 19, color: AppColors.textSecondary),
  );
}

/// Carte d'un élément du dossier (CV, lettre, email, notes).
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.icon,
    required this.title,
    required this.placeholder,
    required this.onTap,
    this.value,
    this.preview,
    this.onCopy,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? preview;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onCopy;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final empty = value == null && preview == null;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBox(icon: icon),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const Gap(3),
                if (empty)
                  Text(
                    placeholder,
                    style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                  ),
                if (value != null)
                  Text(
                    value!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(color: valueColor ?? AppColors.textPrimary),
                  ),
                if (preview != null) ...[
                  if (value != null) const Gap(2),
                  Text(
                    preview!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copier',
              icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textTertiary),
              onPressed: onCopy,
            )
          else
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.edit_outlined, size: 18, color: AppColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// CV rattaché (titre lu dans les documents).
class _CvCard extends ConsumerWidget {
  const _CvCard({required this.application, required this.onTap});

  final Application application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cvId = application.cvDocumentId;
    final document = cvId == null ? null : ref.watch(documentProvider(cvId));
    final doc = document?.value;
    return _DraftCard(
      icon: Icons.description_outlined,
      title: 'CV',
      value: cvId == null
          ? null
          : doc?.title ?? (document?.hasError == true ? 'CV introuvable' : 'Chargement...'),
      valueColor: document?.hasError == true ? AppColors.warning : null,
      preview: doc == null
          ? null
          : [
              doc.originalFilename,
              Fmt.fileSize(doc.sizeBytes),
              if (!doc.isActive) 'inactif',
            ].join(' · '),
      placeholder: application.status.isDraft
          ? 'Choisi automatiquement lors de la préparation'
          : 'Aucun CV',
      onTap: onTap,
    );
  }
}

class _ResponsesSection extends ConsumerWidget {
  const _ResponsesSection({required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(applicationResponsesProvider(applicationId));
    return AsyncValueView<List<RecruiterResponse>>(
      value: value,
      loading: const LoadingView(padding: EdgeInsets.all(20)),
      onRetry: () => ref.invalidate(applicationResponsesProvider(applicationId)),
      data: (items) {
        if (items.isEmpty) {
          return const _MutedCard(text: 'Aucune réponse pour le moment.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Gap(10),
              ResponseTile(
                response: items[i],
                onTap: () => showResponseDetail(context, items[i], showApplicationLink: false),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(applicationHistoryProvider(applicationId));
    return AsyncValueView<List<StatusHistoryEntry>>(
      value: value,
      loading: const LoadingView(padding: EdgeInsets.all(20)),
      onRetry: () => ref.invalidate(applicationHistoryProvider(applicationId)),
      data: (entries) => entries.isEmpty
          ? const _MutedCard(text: 'Aucun historique.')
          : HistoryTimeline(entries: entries),
    );
  }
}

class _MutedCard extends StatelessWidget {
  const _MutedCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
    ),
  );
}
