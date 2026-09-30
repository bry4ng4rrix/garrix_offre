import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/enums.dart';
import '../../core/models/reference.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ui.dart';
import 'data/job_models.dart';
import 'data/jobs_repository.dart';
import 'job_labels.dart';
import 'jobs_providers.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/external_links.dart';
import 'widgets/job_analysis_sheet.dart';
import 'widgets/job_raw_sheet.dart';
import 'widgets/match_section.dart';

/// Détail d'une offre : en-tête, matching détaillé, compétences, description, contacts,
/// sources, dates et actions (candidature, sauvegarde, analyse IA, admin).
class JobDetailPage extends ConsumerWidget {
  const JobDetailPage({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(jobDetailProvider(jobId));
    final job = detail.value;
    return Scaffold(
      appBar: AppBar(
        actions: job == null
            ? null
            : [
                IconButton(
                  tooltip: job.status.isSaved ? 'Retirer des sauvegardes' : 'Sauvegarder',
                  icon: Icon(
                    job.status.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  ),
                  onPressed: () => runAction(
                    () => ref
                        .read(jobDetailProvider(jobId).notifier)
                        .updateState(JobStateUpdate(isSaved: !job.status.isSaved)),
                    success: job.status.isSaved ? 'Retirée des sauvegardes' : 'Offre sauvegardée',
                  ),
                ),
                _MoreMenu(job: job),
                const Gap(4),
              ],
      ),
      body: AsyncValueView<Job>(
        value: detail,
        onRetry: () => ref.invalidate(jobDetailProvider(jobId)),
        data: (job) => _DetailBody(job: job),
      ),
      bottomNavigationBar: job == null ? null : _ActionBar(job: job),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu « … »
// ---------------------------------------------------------------------------

enum _MenuAction { recalculate, markUnseen, toggleIgnore, copyLink, raw, delete }

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.job});

  final Job job;

  Future<void> _onSelected(BuildContext context, WidgetRef ref, _MenuAction action) async {
    final notifier = ref.read(jobDetailProvider(job.id).notifier);
    switch (action) {
      case _MenuAction.recalculate:
        await runAction(
          () => ref.refresh(jobMatchProvider(job.id).future),
          success: 'Score recalculé',
        );
      case _MenuAction.markUnseen:
        await runAction(
          () => notifier.updateState(const JobStateUpdate(seen: false)),
          success: 'Marquée comme non vue',
        );
      case _MenuAction.toggleIgnore:
        final ignored = job.status.isIgnored;
        await runAction(
          () => notifier.updateState(JobStateUpdate(isIgnored: !ignored)),
          success: ignored
              ? 'Offre rétablie'
              : 'Offre ignorée : elle n\'apparaîtra plus dans vos listes',
        );
      case _MenuAction.copyLink:
        await copyText(job.listingUrl!, message: 'Lien copié');
      case _MenuAction.raw:
        await showJobRawSheet(context, job.id);
      case _MenuAction.delete:
        final confirmed = await confirmDialog(
          context,
          title: 'Supprimer cette offre ?',
          message:
              'L\'offre sera supprimée pour tous les utilisateurs, ainsi que ses scores. '
              'Cette action est irréversible.',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!confirmed) return;
        final deleted = await runAction(() async {
          await ref.read(jobsRepositoryProvider).delete(job.id);
          return true;
        }, success: 'Offre supprimée');
        if (deleted == true) {
          ref.read(jobChangesProvider.notifier).emit(JobChange.deleted(job.id));
          if (context.mounted) context.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    PopupMenuItem<_MenuAction> item(
      _MenuAction value,
      IconData icon,
      String label, {
      bool destructive = false,
    }) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: destructive ? AppColors.danger : AppColors.textSecondary),
          const Gap(12),
          Text(label, style: destructive ? const TextStyle(color: AppColors.danger) : null),
        ],
      ),
    );
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Plus d\'actions',
      icon: const Icon(Icons.more_vert_rounded),
      position: PopupMenuPosition.under,
      onSelected: (action) => _onSelected(context, ref, action),
      itemBuilder: (_) => [
        item(_MenuAction.recalculate, Icons.refresh_rounded, 'Recalculer le matching'),
        item(_MenuAction.markUnseen, Icons.mark_email_unread_outlined, 'Marquer comme non vue'),
        item(
          _MenuAction.toggleIgnore,
          job.status.isIgnored ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          job.status.isIgnored ? 'Ne plus ignorer' : 'Ignorer cette offre',
        ),
        if (job.listingUrl != null)
          item(_MenuAction.copyLink, Icons.link_rounded, 'Copier le lien'),
        if (isAdmin) ...[
          const PopupMenuDivider(),
          item(_MenuAction.raw, Icons.data_object_rounded, 'Données brutes'),
          item(
            _MenuAction.delete,
            Icons.delete_outline_rounded,
            'Supprimer l\'offre',
            destructive: true,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barre d'actions : candidature + annonce
// ---------------------------------------------------------------------------

class _ActionBar extends ConsumerStatefulWidget {
  const _ActionBar({required this.job});

  final Job job;

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _busy = false;

  Future<void> _apply() async {
    final job = widget.job;
    final existing = job.status.applicationId;
    if (existing != null) {
      unawaited(context.push(Routes.application(existing)));
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(jobsRepositoryProvider);
      String id;
      try {
        id = await repo.createApplication(job.id);
      } on ApiException catch (error) {
        // Une candidature existe déjà (créée ailleurs) : on l'ouvre.
        if (error.code != 'APPLICATION_ALREADY_EXISTS') rethrow;
        id = await repo.findApplication(job.id) ?? (throw error);
      }
      ref.read(jobDetailProvider(job.id).notifier).setApplication(id);
      if (mounted) unawaited(context.push(Routes.application(id)));
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final url = job.listingUrl;
    final hasApplication = job.status.applicationId != null;
    return BottomBar(
      children: [
        if (url != null)
          PrimaryButton(
            label: 'Voir l\'annonce',
            icon: Icons.open_in_new_rounded,
            outlined: true,
            onPressed: () => openExternalUrl(url),
          ),
        PrimaryButton(
          label: hasApplication ? 'Ma candidature' : 'Préparer ma candidature',
          icon: hasApplication ? Icons.send_rounded : Icons.edit_note_rounded,
          loading: _busy,
          onPressed: _apply,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu
// ---------------------------------------------------------------------------

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiEnabled = ref.watch(aiStatusProvider).value?.enabled ?? false;
    final matched = {
      for (final skill in job.matching?.matchedSkills ?? const <String>[]) skill.toLowerCase(),
    };

    return PageListView(
      onRefresh: () async {
        ref.invalidate(jobMatchProvider(job.id));
        await ref.read(jobDetailProvider(job.id).notifier).reload();
      },
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 32),
      children: [
        _Header(job: job),
        const SectionHeader('Matching'),
        MatchSection(job: job),
        if (aiEnabled) ...[
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () => showJobAnalysisSheet(context, job.id),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.violet),
            label: const Text('Analyser avec l\'IA'),
          ),
        ],
        if (job.skills.isNotEmpty) ...[
          const SectionHeader('Compétences'),
          _SkillsCard(job: job, matched: matched),
        ],
        if (job.bestDescription != null) ...[
          const SectionHeader('Description'),
          _Description(text: job.bestDescription!, partial: job.description == null),
        ],
        if (job.languages.isNotEmpty) ...[
          const SectionHeader('Langues'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final code in job.languages)
                Pill(JobLabels.language(code), icon: Icons.translate_rounded),
            ],
          ),
        ],
        _ContactSection(job: job),
        _CompanySection(company: job.company),
        _SourcesSection(job: job),
        const SectionHeader('Dates'),
        _Rows(
          rows: [
            (
              Icons.event_outlined,
              'Publiée le',
              job.publishedAt == null ? null : Fmt.date(job.publishedAt),
              null,
            ),
            (
              Icons.event_busy_outlined,
              'Expire le',
              job.expiresAt == null ? null : Fmt.date(job.expiresAt),
              null,
            ),
            (
              Icons.download_outlined,
              'Collectée le',
              job.scrapedAt == null ? null : Fmt.dateTime(job.scrapedAt),
              null,
            ),
            (
              Icons.update_rounded,
              'Dernière vérification',
              job.lastCheckedAt == null ? null : Fmt.dateTime(job.lastCheckedAt),
              null,
            ),
            (
              Icons.add_circle_outline_rounded,
              'Ajoutée le',
              job.createdAt == null ? null : Fmt.dateTime(job.createdAt),
              null,
            ),
          ],
        ),
        if (job.qualityIssues.isNotEmpty) ...[
          const SectionHeader('Qualité des données'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final issue in job.qualityIssues)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
                        const Gap(10),
                        Expanded(
                          child: Text(
                            JobLabels.qualityIssue(issue),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Gap(6),
                Text(
                  'Informations incomplètes dans l\'annonce d\'origine.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final labels = ref.watch(jobLabelsProvider);
    final status = job.status;
    final contract = labels.contract(job.contract.type);
    final workTime = JobLabels.workTime(job.contract.workTime);
    final level = labels.level(job.experience.level);
    final years = job.experience.minYears;
    final experience = [
      ?level,
      if (years != null && years > 0) years == 1 ? '1 an min.' : '$years ans min.',
    ].join(' · ');
    final jobStatus = status.jobStatus;
    final meta = [
      job.source.category?.label ?? job.source.name ?? 'Offre',
      if (job.displayDate != null) Fmt.relative(job.displayDate),
    ].join(' · ');

    final pills = <Widget>[
      if (status.hasApplication || status.applicationStatus != ApplicationStatus.notApplied)
        Pill(
          status.applicationStatus.label,
          color: status.applicationStatus.color,
          icon: status.applicationStatus.icon,
        ),
      if (status.isSaved) const Pill('Sauvegardée', icon: Icons.bookmark_rounded),
      if (status.isIgnored) const Pill('Ignorée', icon: Icons.visibility_off_outlined),
      if (status.isExpired)
        const Pill('Expirée', color: AppColors.warning)
      else if (jobStatus != null && jobStatus != JobStatus.active)
        Pill(jobStatus.label, color: jobStatus.color),
      if (contract != null) Pill(contract, icon: Icons.description_outlined),
      if (workTime != null && workTime != contract) Pill(workTime),
      if (job.location.workModeLabel != null)
        Pill(job.location.workModeLabel!, icon: Icons.home_work_outlined),
      if (experience.isNotEmpty) Pill(experience, icon: Icons.trending_up_rounded),
      if (job.salary.isKnown)
        Pill(
          Fmt.salary(
            min: job.salary.min,
            max: job.salary.max,
            currency: job.salary.currency,
            period: job.salary.period,
            raw: job.salary.raw,
          ),
          icon: Icons.payments_outlined,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        job.source.category?.icon ?? Icons.public_rounded,
                        size: 15,
                        color: AppColors.textTertiary,
                      ),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  SelectableText(job.title, style: theme.headlineSmall),
                  const Gap(8),
                  if (job.company.name != null)
                    Text(
                      job.company.name!,
                      style: theme.titleMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  if (job.location.label != null) ...[
                    const Gap(2),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 15, color: AppColors.textTertiary),
                        const Gap(4),
                        Expanded(
                          child: Text(
                            job.location.label!,
                            style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Gap(16),
            ScoreRing(score: job.score, size: 68, strokeWidth: 5),
          ],
        ),
        if (pills.isNotEmpty) ...[const Gap(16), Wrap(spacing: 6, runSpacing: 8, children: pills)],
      ],
    );
  }
}

class _SkillsCard extends StatelessWidget {
  const _SkillsCard({required this.job, required this.matched});

  final Job job;
  final Set<String> matched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    Widget group(String title, List<JobSkill> skills, {required bool filled}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.labelMedium?.copyWith(color: AppColors.textTertiary)),
        const Gap(10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final skill in skills)
              matched.contains(skill.name.toLowerCase())
                  ? Pill(skill.name, color: AppColors.success, icon: Icons.check_rounded)
                  : Pill(skill.name, filled: filled),
          ],
        ),
      ],
    );
    final required = job.requiredSkills;
    final preferred = job.preferredSkills;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (required.isNotEmpty) group('Obligatoires', required, filled: true),
          if (required.isNotEmpty && preferred.isNotEmpty) const Gap(18),
          if (preferred.isNotEmpty) group('Souhaitées', preferred, filled: false),
          if (matched.isNotEmpty) ...[
            const Gap(14),
            Row(
              children: [
                const Icon(Icons.check_rounded, size: 14, color: AppColors.success),
                const Gap(6),
                Text(
                  'Présente dans votre profil',
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Description lisible, sélectionnable, repliée si elle est longue.
class _Description extends StatefulWidget {
  const _Description({required this.text, required this.partial});

  final String text;

  /// Seul l'extrait est disponible.
  final bool partial;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  static const _collapsedLines = 14;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: 1.65,
      color: AppColors.textPrimary.withValues(alpha: 0.9),
    );
    final long = widget.text.length > 900 || '\n'.allMatches(widget.text).length > _collapsedLines;
    final collapsed = long && !_expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (collapsed)
          Text(
            widget.text,
            maxLines: _collapsedLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          )
        else
          SelectableText(widget.text, style: style),
        if (long)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
            icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            label: Text(_expanded ? 'Réduire' : 'Lire la suite'),
          ),
        if (widget.partial)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Extrait : consultez l\'annonce pour le texte complet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// Lignes d'information dans une carte (valeurs vides ignorées).
/// Chaque ligne : (icône, libellé, valeur, action au toucher).
class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final List<(IconData, String, String?, VoidCallback?)> rows;

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((row) => row.$3 != null && row.$3!.isNotEmpty).toList();
    if (visible.isEmpty) {
      return Text(
        'Non renseigné',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
      child: Column(
        children: [
          for (final (icon, label, value, onTap) in visible)
            InfoRow(icon: icon, label: label, value: value, onTap: onTap),
        ],
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final apply = job.application;
    final recruiter = job.recruiter;
    final hasApply = apply.url != null || apply.email != null;
    if (!hasApply && recruiter.isEmpty) return const SizedBox.shrink();
    final who = [?recruiter.name, ?recruiter.jobTitle].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Postuler et contact'),
        _Rows(
          rows: [
            (
              Icons.link_rounded,
              'Lien de candidature',
              apply.url,
              apply.url == null ? null : () => openExternalUrl(apply.url!),
            ),
            (
              Icons.alternate_email_rounded,
              'Email de candidature',
              apply.email,
              apply.email == null ? null : () => openEmail(apply.email!),
            ),
            (Icons.person_outline_rounded, 'Recruteur', who.isEmpty ? null : who, null),
            (
              Icons.mail_outline_rounded,
              'Email du recruteur',
              recruiter.email,
              recruiter.email == null ? null : () => openEmail(recruiter.email!),
            ),
            (
              Icons.phone_outlined,
              'Téléphone',
              recruiter.phone,
              recruiter.phone == null ? null : () => openPhone(recruiter.phone!),
            ),
            (
              Icons.badge_outlined,
              'LinkedIn',
              recruiter.linkedin,
              recruiter.linkedin == null ? null : () => openExternalUrl(recruiter.linkedin!),
            ),
            (
              Icons.language_rounded,
              'Site',
              recruiter.website,
              recruiter.website == null ? null : () => openExternalUrl(recruiter.website!),
            ),
            (
              Icons.verified_outlined,
              'Provenance du contact',
              recruiter.contactSource?.label,
              null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CompanySection extends StatelessWidget {
  const _CompanySection({required this.company});

  final JobCompany company;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String?, VoidCallback?)>[
      (Icons.business_outlined, 'Nom', company.name, null),
      (
        Icons.language_rounded,
        'Site web',
        company.website,
        company.website == null ? null : () => openExternalUrl(company.website!),
      ),
      (Icons.place_outlined, 'Adresse', company.address, null),
      (
        Icons.mail_outline_rounded,
        'Email',
        company.email,
        company.email == null ? null : () => openEmail(company.email!),
      ),
      (
        Icons.phone_outlined,
        'Téléphone',
        company.phone,
        company.phone == null ? null : () => openPhone(company.phone!),
      ),
    ];
    if (rows.every((row) => row.$3 == null)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Entreprise'),
        _Rows(rows: rows),
      ],
    );
  }
}

class _SourcesSection extends StatelessWidget {
  const _SourcesSection({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final sources = [
      job.source,
      ...job.otherSources,
    ].where((s) => s.name != null || s.url != null).toList();
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(sources.length > 1 ? 'Sources (${sources.length})' : 'Source'),
        _Rows(
          rows: [
            for (final source in sources)
              (
                source.category?.icon ?? Icons.public_rounded,
                [source.name ?? 'Source', ?source.category?.label].join(' · '),
                source.url ?? (source.externalId == null ? null : 'Réf. ${source.externalId}'),
                source.url == null ? null : () => openExternalUrl(source.url!),
              ),
          ],
        ),
      ],
    );
  }
}
