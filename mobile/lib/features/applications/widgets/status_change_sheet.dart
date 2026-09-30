import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/application_models.dart';
import '../data/applications_repository.dart';
import 'common.dart';

/// Changement de statut manuel (transitions autorisées, jamais « Envoyée »).
/// Renvoie la candidature mise à jour.
class StatusChangeSheet extends ConsumerStatefulWidget {
  const StatusChangeSheet({super.key, required this.application, this.initial, this.note});

  final Application application;

  /// Statut présélectionné (ex. statut suggéré par l'analyse d'une réponse).
  final ApplicationStatus? initial;
  final String? note;

  @override
  ConsumerState<StatusChangeSheet> createState() => _StatusChangeSheetState();
}

class _StatusChangeSheetState extends ConsumerState<StatusChangeSheet> {
  ApplicationStatus? _target;
  late final TextEditingController _note;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final options = widget.application.manualTransitions;
    _target = options.contains(widget.initial) ? widget.initial : null;
    _note = TextEditingController(text: widget.note);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = _target;
    if (target == null) return;
    if (target.isFinal) {
      final ok = await confirmDialog(
        context,
        title: 'Passer en « ${target.label} » ?',
        message: 'Ce statut est définitif : la candidature ne pourra plus évoluer.',
        confirmLabel: 'Confirmer',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(applicationsRepositoryProvider)
          .changeStatus(widget.application.id, StatusChange(target, note: _note.text));
      if (mounted) Navigator.of(context).pop(result);
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
    final current = widget.application.status;
    final options = widget.application.manualTransitions;
    return SheetLayout(
      title: 'Changer le statut',
      subtitle: 'Statut actuel : ${current.label}',
      footer: PrimaryButton(
        label: 'Mettre à jour',
        loading: _loading,
        onPressed: _target == null ? null : _save,
      ),
      children: [
        if (options.isEmpty)
          const NoticeBanner(message: 'Aucun changement de statut n\'est possible.'),
        for (final status in options) ...[
          SelectableOption(
            title: status.label,
            subtitle: statusDescription(current, status),
            icon: status.icon,
            iconColor: status.color,
            selected: _target == status,
            onTap: _loading ? null : () => setState(() => _target = status),
          ),
          const Gap(8),
        ],
        if (current.allowedTransitions.contains(ApplicationStatus.submitted)) ...[
          const Gap(4),
          const NoticeBanner(
            message: 'Pour indiquer que la candidature est envoyée, utilisez « Valider l\'envoi » : '
                'une confirmation explicite est demandée.',
          ),
        ],
        const Gap(12),
        AppTextField(
          label: 'Note',
          optional: true,
          controller: _note,
          hint: 'Ex. : entretien le 12/10 avec la RH',
          maxLines: 3,
          minLines: 1,
          maxLength: 2000,
        ),
        if (_error != null) ...[
          const Gap(8),
          NoticeBanner(message: _error!, color: AppColors.danger, icon: Icons.error_outline_rounded),
        ],
      ],
    );
  }
}

/// Explication courte d'une transition de statut.
String statusDescription(ApplicationStatus from, ApplicationStatus to) => switch (to) {
  ApplicationStatus.notApplied => 'Aucune démarche engagée',
  ApplicationStatus.preparing =>
    from == ApplicationStatus.ready ? 'Revenir à la rédaction des brouillons' : 'Commencer la préparation',
  ApplicationStatus.ready => 'Brouillons terminés, prête à être validée',
  ApplicationStatus.submitted => 'Envoi confirmé',
  ApplicationStatus.followUp => 'Une relance est nécessaire ou a été faite',
  ApplicationStatus.interview => 'Un entretien est prévu ou a eu lieu',
  ApplicationStatus.offer => 'Vous avez reçu une proposition',
  ApplicationStatus.rejected => 'Le recruteur a décliné (définitif)',
  ApplicationStatus.withdrawn => 'Vous abandonnez cette candidature (définitif)',
};
