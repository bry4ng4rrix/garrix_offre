import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui.dart';
import '../data/application_models.dart';

/// Parcours visuel « Préparer → Valider → Suivre » avec la prochaine étape.
class StatusPipeline extends StatelessWidget {
  const StatusPipeline({super.key, required this.application});

  final Application application;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final status = application.status;
    final current = ApplicationPhase.of(status);
    final phases = ApplicationPhase.values;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < phases.length; i++) ...[
                _Step(
                  number: i + 1,
                  label: phases[i].label,
                  state: current == null
                      ? _StepState.inactive
                      : i < current.index
                      ? _StepState.done
                      : i == current.index
                      ? _StepState.current
                      : _StepState.todo,
                ),
                if (i < phases.length - 1)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 15, left: 6, right: 6),
                      child: Container(
                        height: 1.5,
                        color: current != null && i < current.index
                            ? AppColors.textPrimary
                            : AppColors.borderStrong,
                      ),
                    ),
                  ),
              ],
            ],
          ),
          const Gap(18),
          const Divider(),
          const Gap(14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(status.icon, size: 18, color: status.color),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.label,
                      style: theme.labelLarge?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      nextStepHint(application),
                      style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, todo, inactive }

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.label, required this.state});

  final int number;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final (fill, border, fg) = switch (state) {
      _StepState.done => (AppColors.textPrimary, AppColors.textPrimary, AppColors.onAccent),
      _StepState.current => (AppColors.surfaceHighest, AppColors.textPrimary, AppColors.textPrimary),
      _StepState.todo => (Colors.transparent, AppColors.borderStrong, AppColors.textTertiary),
      _StepState.inactive => (Colors.transparent, AppColors.border, AppColors.textDisabled),
    };
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1.5),
          ),
          child: state == _StepState.done
              ? Icon(Icons.check_rounded, size: 17, color: fg)
              : Text(
                  '$number',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const Gap(8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: state == _StepState.current || state == _StepState.done
                ? AppColors.textPrimary
                : AppColors.textTertiary,
            fontWeight: state == _StepState.current ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Explication de la prochaine étape, selon le statut.
String nextStepHint(Application application) {
  final followUp = application.followUpAt;
  return switch (application.status) {
    ApplicationStatus.notApplied =>
      'Lancez la préparation : le CV est choisi et la lettre et l\'email sont rédigés pour vous. '
          'Rien n\'est envoyé.',
    ApplicationStatus.preparing =>
      'Complétez vos brouillons, puis lancez la préparation pour passer à la validation.',
    ApplicationStatus.ready =>
      'Relisez le CV, la lettre et l\'email, puis validez l\'envoi. '
          'Rien ne part sans votre confirmation.',
    ApplicationStatus.submitted =>
      application.isFollowUpDue()
          ? 'Pas de nouvelles ? C\'est le moment de relancer le recruteur.'
          : followUp != null
          ? 'En attente de réponse. Relance prévue le ${Fmt.date(followUp)}.'
          : 'En attente de réponse du recruteur.',
    ApplicationStatus.followUp =>
      'Relancez le recruteur, puis mettez à jour le statut selon sa réponse.',
    ApplicationStatus.interview =>
      'Préparez votre entretien et mettez à jour le statut après l\'échange.',
    ApplicationStatus.offer => 'Félicitations ! Prenez le temps d\'étudier l\'offre reçue.',
    ApplicationStatus.rejected => 'Candidature refusée. Elle reste dans votre historique.',
    ApplicationStatus.withdrawn => 'Candidature abandonnée. Elle reste dans votre historique.',
  };
}
