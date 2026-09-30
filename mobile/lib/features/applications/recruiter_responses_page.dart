import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'application_providers.dart';
import 'data/application_models.dart';
import 'data/applications_repository.dart';
import 'widgets/responses.dart';

/// Réponses des recruteurs : reçues par email (via n8n) ou saisies à la main.
class RecruiterResponsesPage extends ConsumerStatefulWidget {
  const RecruiterResponsesPage({super.key});

  @override
  ConsumerState<RecruiterResponsesPage> createState() => _RecruiterResponsesPageState();
}

class _RecruiterResponsesPageState extends ConsumerState<RecruiterResponsesPage> {
  final _list = PagedListController();

  void _onChanged(RecruiterResponse updated) =>
      _list.updateWhere<RecruiterResponse>((r) => r.id == updated.id, (_) => updated);

  Future<void> _add() async {
    final created = await showAppSheet<RecruiterResponse>(
      context,
      expand: true,
      builder: (_) => const ResponseFormSheet(),
    );
    if (created == null || !mounted) return;
    showToast('Réponse enregistrée : ${created.responseType.label}', kind: ToastKind.success);
    ref.invalidate(applicationChoicesProvider);
    await _list.refresh();
    if (mounted) await showResponseDetail(context, created, onChanged: _onChanged);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      if (next.value?.type == 'recruiter_response') _list.refresh();
    });
    final repository = ref.watch(applicationsRepositoryProvider);
    // Intitulés des candidatures, pour indiquer à quoi chaque réponse est liée.
    final titles = {
      for (final app in ref.watch(applicationChoicesProvider).value ?? const <Application>[])
        app.id: app.displayTitle,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Réponses des recruteurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
      body: PagedListView<RecruiterResponse>(
        controller: _list,
        fetch: (page) => repository.responses(page: page),
        header: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Les emails des recruteurs sont ajoutés automatiquement et classés '
              '(entretien, refus...). Vous pouvez aussi en saisir un.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
        itemBuilder: (context, response) => ResponseTile(
          response: response,
          applicationLabel: response.applicationId == null
              ? null
              : titles[response.applicationId] ?? 'Candidature liée',
          onTap: () => showResponseDetail(context, response, onChanged: _onChanged),
        ),
        emptyBuilder: (context) => EmptyState(
          icon: Icons.mark_email_read_outlined,
          title: 'Aucune réponse',
          message: 'Les réponses des recruteurs apparaîtront ici.',
          actionLabel: 'Ajouter une réponse',
          onAction: _add,
        ),
      ),
    );
  }
}
