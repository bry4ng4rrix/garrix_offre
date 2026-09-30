import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/reference.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ui.dart';
import 'data/profile_labels.dart';
import 'data/profile_models.dart';
import 'data/profile_providers.dart';
import 'widgets/profile_widgets.dart';

/// Onglet « Profil » : résumé du profil et accès à tous les réglages qui nourrissent le matching.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(profileSkillsProvider)
      ..invalidate(experiencesProvider)
      ..invalidate(technologiesProvider)
      ..invalidate(jobTitlesProvider)
      ..invalidate(searchPreferencesProvider)
      ..invalidate(profileProvider);
    try {
      await ref.read(profileProvider.future);
    } catch (_) {
      // L'erreur est affichée dans la page (état d'erreur avec « Réessayer »).
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Se déconnecter ?',
      message: 'Vous devrez saisir à nouveau votre email et votre mot de passe.',
      confirmLabel: 'Se déconnecter',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final user = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isAdminProvider);

    // Compteurs affichés en sous-titre (null tant qu'ils ne sont pas chargés).
    final skills = ref.watch(profileSkillsProvider).value;
    final experiences = ref.watch(experiencesProvider).value;
    final technologies = ref.watch(technologiesProvider).value;
    final titles = ref.watch(jobTitlesProvider).value;
    final preferences = ref.watch(searchPreferencesProvider).value;
    final contractTypes = ref.watch(contractTypesProvider).value ?? const <ContractType>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
          const Gap(8),
        ],
      ),
      body: PageListView(
        onRefresh: () => _refresh(ref),
        children: [
          AsyncValueView<Profile>(
            value: profile,
            onRetry: () => ref.invalidate(profileProvider),
            loading: const LoadingView(padding: EdgeInsets.symmetric(vertical: 56)),
            data: (profile) => _ProfileHeader(profile: profile, accountEmail: user?.email),
          ),
          const SectionHeader('Mon profil'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.person_outline_rounded,
                title: 'Modifier le profil',
                subtitle: 'Identité, coordonnées, disponibilité, langues',
                onTap: () => context.push(Routes.profileEdit),
              ),
              MenuTile(
                icon: Icons.folder_open_outlined,
                title: 'Documents & CV',
                subtitle: 'CV, lettres de motivation, pièces jointes',
                onTap: () => context.push(Routes.documents),
              ),
              MenuTile(
                icon: Icons.psychology_outlined,
                title: 'Compétences',
                subtitle: _count(skills?.length, 'compétence', 'compétences', 'Ce que vous savez faire'),
                onTap: () => context.push(Routes.skills),
              ),
              MenuTile(
                icon: Icons.timeline_rounded,
                title: 'Expériences',
                subtitle: _count(
                  experiences?.length,
                  'expérience',
                  'expériences',
                  'Votre parcours professionnel',
                ),
                onTap: () => context.push(Routes.experiences),
              ),
              MenuTile(
                icon: Icons.memory_outlined,
                title: 'Technologies recherchées',
                subtitle: _count(
                  technologies?.where((t) => t.enabled).length,
                  'technologie active',
                  'technologies actives',
                  'Ce que vous voulez retrouver dans les offres',
                ),
                onTap: () => context.push(Routes.technologies),
              ),
              MenuTile(
                icon: Icons.badge_outlined,
                title: 'Postes recherchés',
                subtitle: _titlesSummary(titles),
                onTap: () => context.push(Routes.jobTitles),
              ),
            ],
          ),
          const SectionHeader('Recherche'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.tune_rounded,
                title: 'Préférences',
                subtitle: _preferencesSummary(preferences, contractTypes),
                onTap: () => context.push(Routes.preferences),
              ),
              MenuTile(
                icon: Icons.insights_rounded,
                title: 'Matching',
                subtitle: 'Poids des critères du score de compatibilité',
                onTap: () => context.push(Routes.matchingSettings),
              ),
            ],
          ),
          const SectionHeader('Application'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Alertes, email et Telegram',
                onTap: () => context.push(Routes.notificationSettings),
              ),
              MenuTile(
                icon: Icons.settings_outlined,
                title: 'Réglages',
                subtitle: 'Serveur, mot de passe, session',
                onTap: () => context.push(Routes.settings),
              ),
            ],
          ),
          if (isAdmin) ...[
            const SectionHeader('Administration'),
            MenuGroup(
              children: [
                MenuTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Administration',
                  subtitle: 'Utilisateurs, sources, collectes, système',
                  onTap: () => context.push(Routes.admin),
                ),
              ],
            ),
          ],
          const Gap(AppSpacing.xl),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.logout_rounded,
                title: 'Se déconnecter',
                subtitle: user?.email,
                destructive: true,
                trailing: const SizedBox.shrink(),
                onTap: () => _logout(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _count(int? count, String singular, String plural, String fallback) {
    if (count == null) return fallback;
    if (count == 0) return 'Aucune pour l\'instant';
    return '$count ${count == 1 ? singular : plural}';
  }

  static String _titlesSummary(List<JobTitle>? titles) {
    if (titles == null) return 'Les intitulés que vous visez';
    final active = titles.where((t) => t.enabled).map((t) => t.title).toList();
    if (active.isEmpty) return 'Aucun poste actif';
    if (active.length <= 2) return active.join(', ');
    return '${active.take(2).join(', ')} +${active.length - 2}';
  }

  static String _preferencesSummary(SearchPreferences? prefs, List<ContractType> types) {
    if (prefs == null) return 'Contrats, lieux, salaire, seuil d\'alerte';
    String contractName(String code) {
      for (final type in types) {
        if (type.code == code) return type.name;
      }
      return code.toUpperCase();
    }

    final parts = <String>[
      if (prefs.contractTypes.isNotEmpty) prefs.contractTypes.map(contractName).join(', '),
      if (prefs.locations.isNotEmpty)
        prefs.locations.length == 1
            ? prefs.locations.first.label
            : '${prefs.locations.length} lieux',
      'Alerte dès ${prefs.matchingThreshold} %',
    ];
    return parts.join(' · ');
  }
}

/// En-tête : photo, nom, titre, lieu, email et complétude du profil.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile, this.accountEmail});

  final Profile profile;
  final String? accountEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final levels = ref.watch(experienceLevelsProvider).value ?? const <ExperienceLevel>[];
    final name = profile.displayName;
    final pills = <Widget>[
      if (profile.yearsOfExperience != null && profile.yearsOfExperience! > 0)
        Pill('${yearsLabel(profile.yearsOfExperience!)} d\'exp.', icon: Icons.work_history_outlined),
      if (profile.experienceLevel != null && profile.experienceLevel!.isNotEmpty)
        Pill(experienceLevelName(profile.experienceLevel, levels), icon: Icons.trending_up_rounded),
      if (profile.availability != null)
        Pill(profile.availability!.label, icon: Icons.event_available_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(AppSpacing.sm),
        InkWell(
          borderRadius: AppRadius.card,
          onTap: () => context.push(Routes.profileEdit),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                ProfileAvatar(profile: profile, size: 76, fallbackLabel: accountEmail),
                const Gap(AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? 'Votre profil',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.headlineSmall,
                      ),
                      const Gap(2),
                      Text(
                        profile.professionalTitle?.trim().isNotEmpty == true
                            ? profile.professionalTitle!
                            : 'Ajoutez votre titre professionnel',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium?.copyWith(
                          color: profile.professionalTitle?.trim().isNotEmpty == true
                              ? AppColors.textSecondary
                              : AppColors.textTertiary,
                        ),
                      ),
                      const Gap(6),
                      if (profile.location != null)
                        _MetaLine(icon: Icons.place_outlined, text: profile.location!),
                      if (accountEmail != null)
                        _MetaLine(icon: Icons.alternate_email_rounded, text: accountEmail!),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (pills.isNotEmpty) ...[
          const Gap(AppSpacing.md),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
        if (profile.completionPercent < 100) ...[
          const Gap(AppSpacing.lg),
          _CompletionCard(profile: profile),
        ],
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const Gap(6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    ),
  );
}

/// Complétude du profil (calculée par le serveur) et champs encore vides.
class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final percent = profile.completionPercent.clamp(0, 100);
    final missing = profile.missingFields;
    return AppCard(
      onTap: () => context.push(Routes.profileEdit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Profil complété', style: theme.titleSmall)),
              Text(
                '$percent %',
                style: theme.titleSmall?.copyWith(color: AppColors.score(percent)),
              ),
            ],
          ),
          const Gap(10),
          ThinProgress(value: percent / 100, color: AppColors.score(percent)),
          if (missing.isNotEmpty) ...[
            const Gap(10),
            Text(
              'À compléter : ${missing.take(4).join(', ')}${missing.length > 4 ? '…' : ''}',
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
