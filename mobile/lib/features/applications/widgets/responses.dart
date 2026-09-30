import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../application_providers.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';
import 'generated_text_sheet.dart';
import 'status_change_sheet.dart';

/// Carte d'une réponse de recruteur (non lue = point + titre en gras).
class ResponseTile extends StatelessWidget {
  const ResponseTile({super.key, required this.response, this.onTap, this.applicationLabel});

  final RecruiterResponse response;
  final VoidCallback? onTap;

  /// Intitulé de la candidature liée (liste globale des réponses).
  final String? applicationLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final unread = !response.isRead;
    final preview = response.preview;
    return AppCard(
      onTap: onTap,
      borderColor: unread ? AppColors.borderStrong : AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (unread) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                const Gap(8),
              ],
              Expanded(
                child: Text(
                  response.displaySubject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleSmall?.copyWith(
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    color: unread ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
              const Gap(8),
              Text(
                Fmt.relative(response.receivedAt),
                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const Gap(4),
          Text(
            response.senderLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (preview != null) ...[
            const Gap(8),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium?.copyWith(
                color: unread ? AppColors.textSecondary : AppColors.textTertiary,
              ),
            ),
          ],
          const Gap(12),
          Row(
            children: [
              Pill(response.responseType.label, color: response.responseType.color, dense: true),
              if (applicationLabel != null) ...[
                const Gap(8),
                Flexible(
                  child: Pill(
                    applicationLabel!,
                    icon: Icons.link_rounded,
                    filled: false,
                    dense: true,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Ouvre le détail d'une réponse (la marque comme lue).
Future<void> showResponseDetail(
  BuildContext context,
  RecruiterResponse response, {
  ValueChanged<RecruiterResponse>? onChanged,
  bool showApplicationLink = true,
}) => showAppSheet<void>(
  context,
  expand: true,
  builder: (_) => ResponseDetailSheet(
    response: response,
    onChanged: onChanged,
    showApplicationLink: showApplicationLink,
  ),
);

/// Détail d'une réponse : message, analyse, candidature liée, statut suggéré, réponse à rédiger.
class ResponseDetailSheet extends ConsumerStatefulWidget {
  const ResponseDetailSheet({
    super.key,
    required this.response,
    this.onChanged,
    this.showApplicationLink = true,
  });

  final RecruiterResponse response;
  final ValueChanged<RecruiterResponse>? onChanged;

  /// false quand la feuille est ouverte depuis la candidature elle-même.
  final bool showApplicationLink;

  @override
  ConsumerState<ResponseDetailSheet> createState() => _ResponseDetailSheetState();
}

class _ResponseDetailSheetState extends ConsumerState<ResponseDetailSheet> {
  late RecruiterResponse _response = widget.response;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!_response.isRead) {
      unawaited(Future.microtask(() => _update(const RecruiterResponseUpdate(isRead: true))));
    }
  }

  Future<void> _update(RecruiterResponseUpdate data, {String? success}) async {
    if (!mounted) return;
    setState(() => _busy = true);
    // Le conteneur survit à la feuille : la mise à jour aboutit même si elle est fermée entre-temps.
    final container = ProviderScope.containerOf(context, listen: false);
    final onChanged = widget.onChanged;
    try {
      final updated = await container
          .read(applicationsRepositoryProvider)
          .updateResponse(_response.id, data);
      onChanged?.call(updated);
      if (updated.applicationId != null) {
        container.invalidate(applicationResponsesProvider(updated.applicationId!));
      }
      container.invalidate(unreadResponsesCountProvider);
      if (mounted) setState(() => _response = updated);
      if (success != null) showToast(success, kind: ToastKind.success);
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    final picked = await showAppSheet<Application>(
      context,
      expand: true,
      builder: (_) => ApplicationPickerSheet(selectedId: _response.applicationId),
    );
    if (picked == null || !mounted) return;
    await _update(
      RecruiterResponseUpdate(applicationId: picked.id),
      success: 'Réponse associée à « ${picked.displayTitle} »',
    );
  }

  Future<void> _changeType() async {
    final type = await showAppSheet<RecruiterResponseType>(
      context,
      builder: (context) => SheetLayout(
        title: 'Type de réponse',
        children: [
          for (final type in RecruiterResponseType.values) ...[
            SelectableOption(
              title: type.label,
              icon: Icons.label_outline_rounded,
              iconColor: type.color,
              selected: type == _response.responseType,
              onTap: () => Navigator.of(context).pop(type),
            ),
            const Gap(8),
          ],
        ],
      ),
    );
    if (type == null || type == _response.responseType || !mounted) return;
    await _update(RecruiterResponseUpdate(responseType: type), success: 'Type mis à jour');
  }

  Future<void> _applySuggestion(Application application, ApplicationStatus status) async {
    final updated = await showAppSheet<Application>(
      context,
      builder: (_) => StatusChangeSheet(
        application: application,
        initial: status,
        note: 'Réponse du recruteur${_response.subject == null ? '' : ' : ${_response.subject}'}',
      ),
    );
    if (updated == null || !mounted) return;
    ref.read(applicationControllerProvider(application.id).notifier).set(updated);
    ref.invalidate(applicationHistoryProvider(application.id));
    showToast('Candidature passée en « ${updated.status.label} »', kind: ToastKind.success);
  }

  Future<void> _reply() async {
    final applicationId = _response.applicationId;
    if (applicationId == null) return;
    final subject = _response.subject;
    await generateAndPreview(
      context,
      ref,
      applicationId: applicationId,
      kind: GenerationKind.recruiterReply,
      responseId: _response.id,
      canUse: false,
      replyTo: _response.senderEmail,
      replySubject: subject == null
          ? null
          : (subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject'),
    );
  }

  void _openApplication(String id) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(Routes.application(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final r = _response;
    final analysis = r.analysis;
    final summary = analysis.summary;
    final showSummary =
        summary != null && summary.trim() != (r.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

    return SheetLayout(
      title: 'Réponse du recruteur',
      expand: true,
      trailing: PopupMenuButton<String>(
        tooltip: 'Plus d\'actions',
        enabled: !_busy,
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (value) => switch (value) {
          'unread' => _update(
            const RecruiterResponseUpdate(isRead: false),
            success: 'Marquée comme non lue',
          ),
          'type' => _changeType(),
          'link' => _link(),
          'copy' => copyText(r.senderEmail, message: 'Adresse copiée'),
          _ => null,
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'unread', child: Text('Marquer comme non lue')),
          const PopupMenuItem(value: 'type', child: Text('Changer le type')),
          PopupMenuItem(
            value: 'link',
            child: Text(r.applicationId == null ? 'Associer à une candidature' : 'Changer de candidature'),
          ),
          const PopupMenuItem(value: 'copy', child: Text('Copier l\'adresse')),
        ],
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(r.responseType.label, color: r.responseType.color),
            if (analysis.generatedBy == GeneratedBy.ai)
              const Pill('Analysée par l\'IA', icon: Icons.auto_awesome_rounded, color: AppColors.violet),
          ],
        ),
        const Gap(14),
        Text(r.displaySubject, style: theme.titleLarge),
        const Gap(6),
        Text(
          r.senderName == null ? r.senderEmail : '${r.senderName} · ${r.senderEmail}',
          style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const Gap(2),
        Text(
          'Reçue le ${Fmt.dateTime(r.receivedAt)}',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        if (showSummary || analysis.nextSteps.isNotEmpty) ...[
          const Gap(16),
          AppCard(
            color: AppColors.surfaceRaised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSummary) ...[
                  const FieldCaption('Résumé'),
                  const Gap(4),
                  Text(summary, style: theme.bodyMedium),
                ],
                if (analysis.nextSteps.isNotEmpty) ...[
                  if (showSummary) const Gap(12),
                  const FieldCaption('Prochaines étapes'),
                  const Gap(4),
                  for (final step in analysis.nextSteps)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('•  $step', style: theme.bodyMedium),
                    ),
                ],
              ],
            ),
          ),
        ],
        const SectionHeader('Message'),
        AppCard(
          child: SelectableText(
            r.body ?? 'Message vide.',
            style: theme.bodyMedium?.copyWith(
              height: 1.5,
              color: r.body == null ? AppColors.textTertiary : AppColors.textPrimary,
            ),
          ),
        ),
        const SectionHeader('Candidature'),
        if (r.applicationId == null)
          NoticeBanner(
            message: 'Cette réponse n\'est associée à aucune candidature.',
            actionLabel: 'Associer à une candidature',
            onAction: _busy ? null : _link,
          )
        else
          _LinkedApplication(
            applicationId: r.applicationId!,
            suggested: analysis.suggestedStatus,
            onOpen: widget.showApplicationLink ? () => _openApplication(r.applicationId!) : null,
            onApply: _applySuggestion,
          ),
        const Gap(20),
        if (r.applicationId != null)
          PrimaryButton(
            label: 'Rédiger une réponse',
            icon: Icons.reply_rounded,
            outlined: true,
            onPressed: _busy ? null : _reply,
          ),
      ],
    );
  }
}

/// Candidature liée + mise à jour vers le statut suggéré par l'analyse.
class _LinkedApplication extends ConsumerWidget {
  const _LinkedApplication({
    required this.applicationId,
    required this.suggested,
    required this.onOpen,
    required this.onApply,
  });

  final String applicationId;
  final ApplicationStatus? suggested;
  final VoidCallback? onOpen;
  final Future<void> Function(Application application, ApplicationStatus status) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final value = ref.watch(applicationControllerProvider(applicationId));
    return AsyncValueView<Application>(
      value: value,
      loading: const LoadingView(padding: EdgeInsets.all(16)),
      onRetry: () => ref.invalidate(applicationControllerProvider(applicationId)),
      data: (app) {
        final canApply = suggested != null && app.manualTransitions.contains(suggested);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              onTap: onOpen,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.displayTitle, style: theme.titleSmall),
                        if (app.companyName != null)
                          Text(
                            app.companyName!,
                            style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  ApplicationStatusPill(app.status, dense: true),
                  if (onOpen != null)
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                ],
              ),
            ),
            if (canApply) ...[
              const Gap(12),
              NoticeBanner(
                title: 'Statut suggéré : ${suggested!.label}',
                message: 'D\'après ce message, la candidature peut passer en « ${suggested!.label} ».',
                icon: suggested!.icon,
                color: suggested!.color,
                actionLabel: 'Mettre à jour le statut',
                onAction: () => onApply(app, suggested!),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Choix d'une candidature (associer une réponse). Renvoie la candidature choisie.
class ApplicationPickerSheet extends ConsumerStatefulWidget {
  const ApplicationPickerSheet({super.key, this.selectedId});
  final String? selectedId;

  @override
  ConsumerState<ApplicationPickerSheet> createState() => _ApplicationPickerSheetState();
}

class _ApplicationPickerSheetState extends ConsumerState<ApplicationPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(applicationChoicesProvider);
    return SheetLayout(
      title: 'Choisir une candidature',
      expand: true,
      children: [
        AppTextField(
          hint: 'Rechercher un poste ou une entreprise',
          prefixIcon: Icons.search_rounded,
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
        ),
        const Gap(14),
        AsyncValueView<List<Application>>(
          value: choices,
          onRetry: () => ref.invalidate(applicationChoicesProvider),
          data: (items) {
            final filtered = items.where((app) {
              if (_query.isEmpty) return true;
              final text = '${app.jobTitle} ${app.companyName ?? ''}'.toLowerCase();
              return text.contains(_query);
            }).toList();
            if (filtered.isEmpty) {
              return const EmptyState(icon: Icons.search_off_rounded, title: 'Aucune candidature');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final app in filtered) ...[
                  SelectableOption(
                    title: app.displayTitle,
                    subtitle: [?app.companyName, app.status.label].join(' · '),
                    icon: app.status.icon,
                    iconColor: app.status.color,
                    selected: app.id == widget.selectedId,
                    onTap: () => Navigator.of(context).pop(app),
                  ),
                  const Gap(8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Saisie manuelle d'une réponse reçue (le type est analysé par le serveur).
class ResponseFormSheet extends ConsumerStatefulWidget {
  const ResponseFormSheet({super.key, this.application});

  /// Candidature présélectionnée (ouverture depuis son détail).
  final Application? application;

  @override
  ConsumerState<ResponseFormSheet> createState() => _ResponseFormSheetState();
}

class _ResponseFormSheetState extends ConsumerState<ResponseFormSheet> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  DateTime? _received = DateTime.now();
  Application? _application;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickApplication() async {
    final picked = await showAppSheet<Application>(
      context,
      expand: true,
      builder: (_) => ApplicationPickerSheet(selectedId: _application?.id),
    );
    if (picked != null && mounted) setState(() => _application = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    final day = _received;
    try {
      final created = await ref
          .read(applicationsRepositoryProvider)
          .createResponse(
            RecruiterResponseCreate(
              senderEmail: _email.text,
              senderName: _name.text,
              subject: _subject.text,
              body: _body.text,
              applicationId: _application?.id,
              // Jour choisi ; l'heure actuelle si c'est aujourd'hui.
              receivedAt: day == null
                  ? null
                  : DateTime(day.year, day.month, day.day, now.hour, now.minute),
            ),
          );
      if (mounted) Navigator.of(context).pop(created);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiException.describe(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _application;
    return Form(
      key: _form,
      child: SheetLayout(
        title: 'Ajouter une réponse',
        subtitle: 'Collez l\'email reçu : son type (entretien, refus...) est détecté automatiquement.',
        expand: true,
        footer: PrimaryButton(label: 'Enregistrer', loading: _loading, onPressed: _save),
        children: [
          AppTextField(
            label: 'Email de l\'expéditeur',
            controller: _email,
            hint: 'rh@entreprise.com',
            keyboardType: TextInputType.emailAddress,
            validator: Validators.email,
            textInputAction: TextInputAction.next,
          ),
          formGap,
          AppTextField(
            label: 'Nom',
            optional: true,
            controller: _name,
            maxLength: 200,
            textInputAction: TextInputAction.next,
          ),
          formGap,
          AppTextField(
            label: 'Objet',
            optional: true,
            controller: _subject,
            maxLength: 500,
            textInputAction: TextInputAction.next,
          ),
          formGap,
          AppTextField(
            label: 'Message',
            optional: true,
            controller: _body,
            maxLines: null,
            minLines: 6,
            keyboardType: TextInputType.multiline,
          ),
          formGap,
          DateField(
            label: 'Reçue le',
            value: _received,
            lastDate: DateTime.now(),
            clearable: false,
            onChanged: (value) => setState(() => _received = value),
          ),
          formGap,
          const FieldLabel('Candidature', optional: true),
          SelectableOption(
            title: app?.displayTitle ?? 'Détection automatique',
            subtitle: app == null
                ? 'Associée d\'après l\'expéditeur et l\'objet, si possible'
                : [?app.companyName, app.status.label].join(' · '),
            icon: Icons.link_rounded,
            selected: app != null,
            onTap: _loading ? null : _pickApplication,
          ),
          if (_error != null) ...[
            const Gap(12),
            NoticeBanner(message: _error!, color: AppColors.danger, icon: Icons.error_outline_rounded),
          ],
        ],
      ),
    );
  }
}
