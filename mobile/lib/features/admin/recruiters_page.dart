import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_repository.dart';
import 'data/directory_models.dart';
import 'widgets/admin_ui.dart';
import 'widgets/company_sheets.dart';
import 'widgets/recruiter_sheets.dart';

/// Recruteurs : recherche, filtre par entreprise, fiche (provenance des coordonnées), CRUD.
class RecruitersPage extends ConsumerStatefulWidget {
  const RecruitersPage({super.key});

  @override
  ConsumerState<RecruitersPage> createState() => _RecruitersPageState();
}

class _RecruitersPageState extends ConsumerState<RecruitersPage> {
  final _controller = PagedListController();
  String _search = '';
  Company? _company;
  int? _total;

  void _open(Recruiter recruiter) => showAppSheet<void>(
    context,
    expand: true,
    builder: (_) => RecruiterDetailSheet(
      recruiter: recruiter,
      onUpdated: (updated) =>
          _controller.updateWhere<Recruiter>((r) => r.id == updated.id, (_) => updated),
      onDeleted: () => _controller.removeWhere<Recruiter>((r) => r.id == recruiter.id),
    ),
  );

  Future<void> _create() async {
    final recruiter = await showRecruiterForm(context);
    if (recruiter != null) await _controller.refresh();
  }

  Future<void> _pickCompany() async {
    final choice = await pickCompany(context);
    if (choice != null) setState(() => _company = choice.company);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recruteurs'),
        actions: [
          IconButton(
            tooltip: 'Filtrer par entreprise',
            onPressed: _pickCompany,
            icon: Badge(
              isLabelVisible: _company != null,
              smallSize: 8,
              backgroundColor: AppColors.textPrimary,
              child: const Icon(Icons.business_outlined),
            ),
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Recruteur'),
      ),
      body: Column(
        children: [
          PageBody(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 0),
            child: SearchField(
              hint: 'Nom, email, fonction...',
              initialValue: _search,
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Expanded(
            child: PagedListView<Recruiter>(
              key: ValueKey('$_search|${_company?.id}'),
              controller: _controller,
              fetch: (page) =>
                  repo.recruiters(page: page, search: _search, companyId: _company?.id),
              onTotal: (total) => setState(() => _total = total),
              header: [
                if (_company != null) ...[
                  const Gap(8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.business_outlined, size: 16),
                      label: Text(_company!.name),
                      onDeleted: () => setState(() => _company = null),
                    ),
                  ),
                ],
                ListCount(count: _total, singular: 'recruteur', plural: 'recruteurs'),
              ],
              emptyBuilder: (_) => EmptyState(
                icon: Icons.badge_outlined,
                title: 'Aucun recruteur',
                message: _search.isEmpty && _company == null
                    ? 'Les recruteurs sont ajoutés par les collectes ou manuellement.'
                    : 'Aucun recruteur ne correspond à ces critères.',
              ),
              itemBuilder: (context, recruiter) =>
                  _RecruiterCard(recruiter: recruiter, onTap: () => _open(recruiter)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecruiterCard extends StatelessWidget {
  const _RecruiterCard({required this.recruiter, required this.onTap});

  final Recruiter recruiter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final muted = theme.bodySmall?.copyWith(color: AppColors.textTertiary);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AppAvatar(label: recruiter.displayName, size: 42),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recruiter.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (recruiter.jobTitle != null)
                  Text(
                    recruiter.jobTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                if (recruiter.companyId != null)
                  CompanyName(companyId: recruiter.companyId!, style: muted),
                const Gap(6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (recruiter.email != null)
                      const Icon(
                        Icons.mail_outline_rounded,
                        size: 15,
                        color: AppColors.textTertiary,
                      ),
                    if (recruiter.phone != null)
                      const Icon(Icons.phone_outlined, size: 15, color: AppColors.textTertiary),
                    if (recruiter.linkedinUrl != null)
                      const Icon(Icons.link_rounded, size: 15, color: AppColors.textTertiary),
                    if (recruiter.contactSource != null)
                      Pill(recruiter.contactSource!.label, dense: true)
                    else if (recruiter.hasContact)
                      const Pill('Provenance manquante', dense: true, color: AppColors.warning),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
