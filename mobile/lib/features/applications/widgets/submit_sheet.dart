import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../../documents/data/documents_repository.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';

/// Façon d'envoyer (ou d'avoir envoyé) la candidature.
enum SendMode {
  sendNow(
    Icons.send_rounded,
    'Envoyer par email maintenant',
    'L\'email part avec votre CV en pièce jointe',
    SubmissionMethod.email,
  ),
  ownMailbox(
    Icons.outgoing_mail,
    'Envoyée depuis ma messagerie',
    'Enregistrer l\'envoi, sans rien envoyer',
    SubmissionMethod.email,
  ),
  website(
    Icons.language_rounded,
    'Envoyée sur le site',
    'Formulaire en ligne, plateforme de recrutement',
    SubmissionMethod.website,
  ),
  other(
    Icons.more_horiz_rounded,
    'Autre moyen',
    'Remise en main propre, courrier...',
    SubmissionMethod.other,
  );

  const SendMode(this.icon, this.label, this.description, this.method);
  final IconData icon;
  final String label;
  final String description;
  final SubmissionMethod method;

  /// Requête d'envoi correspondante (la confirmation vient de la case cochée).
  SubmitRequest request({required bool confirm, String? toEmail, String? reference}) =>
      this == sendNow
      ? SubmitRequest(confirm: confirm, sendEmail: true, toEmail: toEmail)
      : SubmitRequest(confirm: confirm, method: method, reference: reference);
}

/// « Valider l'envoi » : récapitulatif de ce qui part + case de confirmation explicite.
/// Aucune candidature n'est envoyée sans cette confirmation. Renvoie la candidature envoyée.
class SubmitSheet extends ConsumerStatefulWidget {
  const SubmitSheet({super.key, required this.application});

  final Application application;

  @override
  ConsumerState<SubmitSheet> createState() => _SubmitSheetState();
}

class _SubmitSheetState extends ConsumerState<SubmitSheet> {
  late SendMode _mode;
  late final TextEditingController _to;
  final _reference = TextEditingController();
  bool _confirmed = false;
  bool _loading = false;
  bool _fullBody = false;
  ApiException? _apiError;
  String? _error;

  Application get _app => widget.application;

  @override
  void initState() {
    super.initState();
    _to = TextEditingController(text: _app.applicationEmail ?? '');
    _mode = _app.applicationEmail == null && _app.job?.applicationUrl != null
        ? SendMode.website
        : SendMode.sendNow;
  }

  @override
  void dispose() {
    _to.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _setMode(SendMode mode) => setState(() {
    _mode = mode;
    _confirmed = false; // ce qui part change : nouvelle confirmation requise
    _apiError = null;
    _error = null;
  });

  bool get _recipientValid => Validators.email(_to.text) == null;

  bool get _canSubmit {
    if (!_confirmed || _loading) return false;
    if (_mode == SendMode.sendNow) return _recipientValid && _app.hasEmailDraft;
    return true;
  }

  Future<void> _submit() async {
    if (!_confirmed) return;
    setState(() {
      _loading = true;
      _apiError = null;
      _error = null;
    });
    try {
      final result = await ref
          .read(applicationsRepositoryProvider)
          .submit(
            _app.id,
            _mode.request(confirm: _confirmed, toEmail: _to.text, reference: _reference.text),
          );
      showToast(
        _mode == SendMode.sendNow
            ? 'Candidature envoyée par email'
            : 'Candidature enregistrée comme envoyée',
        kind: ToastKind.success,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (error is ApiException) {
          _apiError = error;
        } else {
          _error = ApiException.describe(error);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sendNow = _mode == SendMode.sendNow;
    return SheetLayout(
      title: 'Valider l\'envoi',
      subtitle: 'Vérifiez ce qui sera envoyé. Rien ne part sans votre confirmation.',
      expand: true,
      footer: PrimaryButton(
        label: sendNow ? 'Envoyer la candidature' : 'Marquer comme envoyée',
        icon: sendNow ? Icons.send_rounded : Icons.check_rounded,
        loading: _loading,
        onPressed: _canSubmit ? _submit : null,
      ),
      children: [
        const FieldLabel('Mode d\'envoi'),
        for (final mode in SendMode.values) ...[
          SelectableOption(
            title: mode.label,
            subtitle: mode.description,
            icon: mode.icon,
            selected: _mode == mode,
            onTap: _loading ? null : () => _setMode(mode),
          ),
          const Gap(8),
        ],
        const Gap(12),
        const FieldLabel('Récapitulatif'),
        _Summary(
          application: _app,
          mode: _mode,
          recipient: _to,
          reference: _reference,
          fullBody: _fullBody,
          onToggleBody: () => setState(() => _fullBody = !_fullBody),
          onRecipientChanged: () => setState(() => _confirmed = false),
        ),
        if (_apiError != null || _error != null) ...[const Gap(16), _errorBanner()],
        const Gap(20),
        _ConfirmBox(
          value: _confirmed,
          subtitle: sendNow
              ? (_recipientValid
                    ? 'Un email sera envoyé à ${_to.text.trim()} avec votre CV.'
                    : 'Saisissez d\'abord l\'adresse du destinataire.')
              : 'Elle sera marquée comme envoyée (${_mode.method.label.toLowerCase()}). '
                    'Aucun email ne sera envoyé.',
          onChanged: _loading ? null : (value) => setState(() => _confirmed = value),
        ),
      ],
    );
  }

  Widget _errorBanner() {
    final code = _apiError?.code;
    return switch (code) {
      'NO_APPLICATION_EMAIL' => NoticeBanner(
        title: 'Destinataire inconnu',
        message:
            'Aucune adresse de candidature n\'est connue pour cette offre. Saisissez le '
            'destinataire, ou postulez sur le site puis enregistrez l\'envoi.',
        color: AppColors.warning,
        icon: Icons.alternate_email_rounded,
        actionLabel: 'Enregistrer un envoi sur le site',
        onAction: () => _setMode(SendMode.website),
      ),
      'EMAIL_NOT_CONFIGURED' || 'EMAIL_ERROR' => NoticeBanner(
        title: code == 'EMAIL_ERROR' ? 'L\'envoi a échoué' : 'Envoi d\'email indisponible',
        message: code == 'EMAIL_ERROR'
            ? 'L\'email n\'a pas pu être envoyé. Réessayez, ou envoyez la candidature depuis '
                  'votre messagerie puis enregistrez l\'envoi ici.'
            : 'L\'envoi d\'emails n\'est pas configuré sur le serveur. Envoyez la candidature '
                  'depuis votre messagerie, puis enregistrez l\'envoi ici.',
        color: AppColors.warning,
        icon: Icons.mail_lock_outlined,
        actionLabel: 'Envoyer depuis ma messagerie',
        onAction: () => _setMode(SendMode.ownMailbox),
      ),
      'EMAIL_DRAFT_MISSING' => const NoticeBanner(
        title: 'Email incomplet',
        message: 'Rédigez l\'objet et le texte de l\'email (section « Dossier ») avant l\'envoi.',
        color: AppColors.warning,
        icon: Icons.edit_note_rounded,
      ),
      _ => NoticeBanner(
        message: _apiError?.userMessage ?? _error ?? 'Une erreur est survenue.',
        color: AppColors.danger,
        icon: Icons.error_outline_rounded,
      ),
    };
  }
}

/// Récapitulatif de ce qui sera envoyé ou enregistré.
class _Summary extends ConsumerWidget {
  const _Summary({
    required this.application,
    required this.mode,
    required this.recipient,
    required this.reference,
    required this.fullBody,
    required this.onToggleBody,
    required this.onRecipientChanged,
  });

  final Application application;
  final SendMode mode;
  final TextEditingController recipient;
  final TextEditingController reference;
  final bool fullBody;
  final VoidCallback onToggleBody;
  final VoidCallback onRecipientChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final app = application;
    final cvId = app.cvDocumentId;
    final cv = cvId == null ? null : ref.watch(documentProvider(cvId));
    final cvLabel = cvId == null
        ? 'Aucun CV sélectionné'
        : cv?.value?.title ?? (cv?.hasError == true ? 'CV introuvable' : 'Chargement...');
    final job = app.job;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(
            icon: Icons.work_outline_rounded,
            label: 'Candidature',
            value: [app.displayTitle, ?app.companyName].join(' · '),
          ),
          _Line(
            icon: Icons.description_outlined,
            label: mode == SendMode.sendNow ? 'Pièce jointe' : 'CV',
            value: cvLabel,
            warning: cvId == null && mode == SendMode.sendNow,
          ),
          if (mode == SendMode.sendNow) ...[
            const Gap(8),
            AppTextField(
              label: 'Destinataire',
              controller: recipient,
              hint: 'recrutement@entreprise.com',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.alternate_email_rounded,
              onChanged: (_) => onRecipientChanged(),
            ),
            const Gap(14),
            _Line(
              icon: Icons.subject_rounded,
              label: 'Objet',
              value: app.emailSubject ?? 'Objet manquant',
              warning: app.emailSubject == null,
            ),
            const Gap(6),
            const FieldCaption('Message'),
            const Gap(6),
            if (app.emailBody == null)
              Text(
                'Message manquant : rédigez l\'email dans la section « Dossier ».',
                style: theme.bodyMedium?.copyWith(color: AppColors.warning),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: AppRadius.input,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  app.emailBody!,
                  maxLines: fullBody ? null : 6,
                  overflow: fullBody ? null : TextOverflow.fade,
                  style: theme.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: InlineAction(
                  label: fullBody ? 'Réduire' : 'Afficher tout le message',
                  icon: fullBody ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  onPressed: onToggleBody,
                ),
              ),
            ],
            if (app.coverLetterText != null)
              Text(
                'La lettre rédigée n\'est pas jointe : seuls le message et les documents '
                'le sont.',
                style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
          ] else ...[
            const Gap(8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (mode == SendMode.website && job?.applicationUrl != null)
                  InlineAction(
                    label: 'Ouvrir le site',
                    icon: Icons.open_in_new_rounded,
                    onPressed: () => openExternal(Uri.parse(job!.applicationUrl!)),
                  ),
                if (mode == SendMode.ownMailbox)
                  InlineAction(
                    label: 'Ouvrir ma messagerie',
                    icon: Icons.outgoing_mail,
                    onPressed: () => openExternal(
                      mailtoUri(
                        app.applicationEmail ?? '',
                        subject: app.emailSubject,
                        body: app.emailBody,
                      ),
                    ),
                  ),
                if (app.emailBody != null)
                  InlineAction(
                    label: 'Copier l\'email',
                    icon: Icons.copy_rounded,
                    onPressed: () => copyText(
                      [?app.emailSubject, app.emailBody!].join('\n\n'),
                      message: 'Email copié',
                    ),
                  ),
                if (app.coverLetterText != null)
                  InlineAction(
                    label: 'Copier la lettre',
                    icon: Icons.copy_rounded,
                    onPressed: () => copyText(app.coverLetterText!, message: 'Lettre copiée'),
                  ),
              ],
            ),
            const Gap(8),
            AppTextField(
              label: 'Référence',
              optional: true,
              controller: reference,
              hint: 'N° de candidature, lien de suivi...',
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: warning ? AppColors.warning : AppColors.textTertiary),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldCaption(label),
                const Gap(2),
                Text(
                  value,
                  style: theme.bodyMedium?.copyWith(
                    color: warning ? AppColors.warning : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Case « Je confirme l'envoi de cette candidature » (obligatoire).
class _ConfirmBox extends StatelessWidget {
  const _ConfirmBox({required this.value, required this.subtitle, required this.onChanged});

  final bool value;
  final String subtitle;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Material(
      color: value ? AppColors.surfaceHigh : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.input,
        side: BorderSide(color: value ? AppColors.textPrimary : AppColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (checked) => onChanged!(checked ?? false),
              ),
              const Gap(4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Je confirme l\'envoi de cette candidature',
                        style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Gap(4),
                      Text(
                        subtitle,
                        style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
