import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/reference.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ui.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';

/// Génère un texte pour une candidature puis l'affiche en aperçu.
///
/// Renvoie le texte si l'utilisateur choisit « Utiliser ce texte » (uniquement si [canUse]).
/// [replyTo] ajoute « Ouvrir ma messagerie » (réponse à un recruteur).
Future<GeneratedText?> generateAndPreview(
  BuildContext context,
  WidgetRef ref, {
  required String applicationId,
  required GenerationKind kind,
  String? responseId,
  bool canUse = true,
  String? replyTo,
  String? replySubject,
}) async {
  final repository = ref.read(applicationsRepositoryProvider);
  final text = await runWithProgress(
    context,
    () => repository.generate(applicationId, GenerateRequest(kind, responseId: responseId)),
  );
  if (text == null || !context.mounted) return null;
  final used = await showAppSheet<bool>(
    context,
    expand: true,
    builder: (_) => GeneratedTextSheet(
      text: text,
      canUse: canUse,
      replyTo: replyTo,
      replySubject: replySubject,
    ),
  );
  return used == true ? text : null;
}

/// Aperçu d'un texte généré : copier, ou reprendre dans le brouillon.
class GeneratedTextSheet extends StatelessWidget {
  const GeneratedTextSheet({
    super.key,
    required this.text,
    this.canUse = true,
    this.replyTo,
    this.replySubject,
  });

  final GeneratedText text;
  final bool canUse;
  final String? replyTo;
  final String? replySubject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final byAi = text.generatedBy == GeneratedBy.ai;
    return SheetLayout(
      title: text.kind.label,
      expand: true,
      trailing: IconButton(
        tooltip: 'Copier',
        icon: const Icon(Icons.copy_rounded, size: 20),
        onPressed: () => copyText(text.clipboardText),
      ),
      footer: Row(
        children: [
          Expanded(
            child: replyTo != null
                ? OutlinedButton.icon(
                    onPressed: () => openExternal(
                      mailtoUri(replyTo!, subject: replySubject, body: text.content),
                    ),
                    icon: const Icon(Icons.outgoing_mail, size: 18),
                    label: const Text('Messagerie'),
                  )
                : OutlinedButton.icon(
                    onPressed: () => copyText(text.clipboardText),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copier'),
                  ),
          ),
          if (canUse) ...[
            const Gap(10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Utiliser ce texte'),
              ),
            ),
          ],
        ],
      ),
      children: [
        Row(
          children: [
            Pill(
              byAi ? 'Rédigé par l\'IA' : 'Modèle de texte',
              icon: byAi ? Icons.auto_awesome_rounded : Icons.description_outlined,
              color: byAi ? AppColors.violet : null,
            ),
          ],
        ),
        const Gap(16),
        if (text.subject != null) ...[
          const FieldCaption('Objet'),
          const Gap(4),
          SelectableText(text.subject!, style: theme.titleSmall),
          const Gap(16),
        ],
        AppCard(
          color: AppColors.surfaceRaised,
          child: SelectableText(text.content, style: theme.bodyMedium?.copyWith(height: 1.5)),
        ),
        const Gap(12),
        Text(
          'Relisez et personnalisez ce texte avant de l\'utiliser : il ne contient que les '
          'informations de votre profil.',
          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// Choix du texte à générer depuis le détail d'une candidature.
class GenerateKindSheet extends ConsumerWidget {
  const GenerateKindSheet({super.key});

  static const _kinds = [
    (
      GenerationKind.coverLetter,
      Icons.article_outlined,
      'Remplace le brouillon si vous le reprenez',
    ),
    (GenerationKind.applicationEmail, Icons.mail_outline_rounded, 'Objet et message d\'envoi'),
    (
      GenerationKind.jobSummary,
      Icons.summarize_outlined,
      'L\'essentiel de l\'offre en quelques lignes',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiStatusProvider).value;
    return SheetLayout(
      title: 'Générer un texte',
      children: [
        if (ai != null && !ai.enabled) ...[
          const NoticeBanner(
            message:
                'IA non configurée : le texte sera créé à partir d\'un modèle, '
                'à personnaliser ensuite.',
          ),
          const Gap(12),
        ],
        MenuGroup(
          children: [
            for (final (kind, icon, subtitle) in _kinds)
              MenuTile(
                icon: icon,
                title: kind.label,
                subtitle: subtitle,
                onTap: () => Navigator.of(context).pop(kind),
              ),
          ],
        ),
      ],
    );
  }
}
