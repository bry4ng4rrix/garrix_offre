import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_user.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/models/reference.dart';
import '../../core/network/api_exception.dart';
import '../../core/realtime/realtime_service.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ui.dart';
import '../auth/widgets/server_sheet.dart';
import 'data/settings_repository.dart';

/// Réglages : compte, serveur, sécurité, IA, à propos, déconnexion.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(serverHealthProvider);
    ref.invalidate(aiStatusProvider);
    try {
      await ref.read(authControllerProvider.notifier).refreshUser();
    } catch (_) {
      // Informations du compte déjà affichées : une erreur ici n'est pas bloquante.
    }
  }

  Future<void> _changeServer(BuildContext context, WidgetRef ref) async {
    final before = ref.read(serverUrlProvider);
    await showAppSheet<void>(context, builder: (_) => const ServerSheet());
    if (!context.mounted || ref.read(serverUrlProvider) == before) return;
    // La session a été ouverte sur l'ancien serveur : on propose de se reconnecter.
    final relogin = await confirmDialog(
      context,
      title: 'Serveur modifié',
      message:
          'Votre session a été ouverte sur l\'ancien serveur. Déconnectez-vous puis '
          'reconnectez-vous pour utiliser le nouveau.',
      confirmLabel: 'Se reconnecter',
      cancelLabel: 'Plus tard',
    );
    if (relogin && context.mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  Future<void> _logoutAllDevices(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Déconnecter tous les appareils ?',
      message:
          'Toutes vos sessions seront fermées, y compris celle-ci. '
          'Vous devrez vous reconnecter sur chaque appareil.',
      confirmLabel: 'Tout déconnecter',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(authControllerProvider.notifier).logout(allDevices: true);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Se déconnecter ?',
      message: 'Vous pourrez vous reconnecter à tout moment avec votre email.',
      confirmLabel: 'Se déconnecter',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  Future<void> _openDocs(String serverUrl) async {
    try {
      final opened = await launchUrl(
        Uri.parse('$serverUrl/docs'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) showToast('Impossible d\'ouvrir le navigateur.', kind: ToastKind.error);
    } catch (_) {
      showToast('Impossible d\'ouvrir le navigateur.', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final serverUrl = ref.watch(serverUrlProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: PageListView(
        onRefresh: () => _refresh(ref),
        children: [
          if (user != null) _AccountCard(user: user),
          SectionHeader(
            'Serveur',
            action: 'Tester',
            onAction: () => ref.invalidate(serverHealthProvider),
          ),
          _ServerCard(serverUrl: serverUrl),
          const Gap(10),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.swap_horiz_rounded,
                title: 'Changer de serveur',
                subtitle: 'Une reconnexion sera nécessaire',
                onTap: () => _changeServer(context, ref),
              ),
            ],
          ),
          const SectionHeader('Sécurité'),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.lock_outline_rounded,
                title: 'Changer le mot de passe',
                onTap: () => context.push(Routes.changePassword),
              ),
              MenuTile(
                icon: Icons.devices_other_rounded,
                title: 'Déconnecter tous les appareils',
                subtitle: 'Ferme toutes vos sessions, y compris celle-ci',
                onTap: () => _logoutAllDevices(context, ref),
              ),
            ],
          ),
          const SectionHeader('Intelligence artificielle'),
          const _AiCard(),
          const SectionHeader('À propos'),
          MenuGroup(
            children: [
              const MenuTile(
                icon: Icons.info_outline_rounded,
                title: kAppName,
                subtitle: 'Version $kAppVersion',
              ),
              MenuTile(
                icon: Icons.menu_book_outlined,
                title: 'Documentation de l\'API',
                subtitle: '${_hostLabel(serverUrl)}/docs',
                trailing: const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                onTap: () => _openDocs(serverUrl),
              ),
              MenuTile(
                icon: Icons.shield_outlined,
                title: 'Confidentialité',
                subtitle: 'Vos données restent sur votre serveur',
                onTap: () => showAppSheet<void>(context, builder: (_) => const _PrivacySheet()),
              ),
            ],
          ),
          const Gap(AppSpacing.xxl),
          MenuGroup(
            children: [
              MenuTile(
                icon: Icons.logout_rounded,
                title: 'Se déconnecter',
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
}

String _hostLabel(String url) => url.replaceFirst(RegExp(r'^https?://'), '');

/// Carte du compte : avatar, email, rôle, dates.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(label: user.email, size: 52),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium,
                    ),
                    const Gap(6),
                    Pill(
                      user.isSuperuser ? 'Administrateur' : 'Utilisateur',
                      icon: user.isSuperuser
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline_rounded,
                      color: user.isSuperuser ? AppColors.violet : null,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          const Divider(),
          const Gap(4),
          InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Membre depuis',
            value: user.createdAt == null ? null : Fmt.date(user.createdAt),
          ),
          InfoRow(
            icon: Icons.login_rounded,
            label: 'Dernière connexion',
            value: user.lastLoginAt == null ? null : Fmt.dateTime(user.lastLoginAt),
          ),
        ],
      ),
    );
  }
}

/// Carte du serveur : adresse, temps réel (WebSocket) et état des dépendances.
class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.serverUrl});

  final String serverUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final realtime = ref.watch(realtimeServiceProvider);
    final health = ref.watch(serverHealthProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_outlined, size: 20, color: AppColors.textSecondary),
              const Gap(12),
              Expanded(
                child: SelectableText(_hostLabel(serverUrl), maxLines: 1, style: theme.titleSmall),
              ),
              if (serverUrl.startsWith('https://'))
                const Pill('HTTPS', icon: Icons.lock_outline_rounded, dense: true)
              else
                const Pill('HTTP', dense: true),
            ],
          ),
          const Gap(14),
          const Divider(),
          const Gap(12),
          _HealthStatus(health: health),
          const Gap(10),
          ValueListenableBuilder<bool>(
            valueListenable: realtime.connected,
            builder: (context, connected, _) => _StatusLine(
              color: connected ? AppColors.success : AppColors.textTertiary,
              label: connected ? 'Temps réel connecté' : 'Temps réel déconnecté',
              detail: connected ? null : 'Reconnexion automatique en cours',
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthStatus extends StatelessWidget {
  const _HealthStatus({required this.health});

  final AsyncValue<ServerHealth> health;

  @override
  Widget build(BuildContext context) {
    if (health.isLoading) {
      return const _StatusLine(label: 'Vérification du serveur...', loading: true);
    }
    final value = health.value;
    if (health.hasError || value == null) {
      final error = health.error;
      return _StatusLine(
        color: AppColors.danger,
        label: 'Serveur injoignable',
        detail: error == null ? null : ApiException.describe(error),
      );
    }
    final latency = value.latency == null ? '' : ' · ${value.latency!.inMilliseconds} ms';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusLine(
          color: value.isReady ? AppColors.success : AppColors.warning,
          label: value.isReady ? 'Serveur opérationnel$latency' : 'Serveur dégradé$latency',
        ),
        if (value.checks.isNotEmpty) ...[
          const Gap(10),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final check in value.checks.entries)
                  Pill(
                    ServerHealth.checkLabel(check.key),
                    icon: check.value == 'ok' ? Icons.check_rounded : Icons.close_rounded,
                    color: check.value == 'ok' ? AppColors.success : AppColors.danger,
                    dense: true,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Ligne d'état : pastille colorée (ou chargement), libellé, détail.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    this.color = AppColors.textTertiary,
    this.detail,
    this.loading = false,
  });

  final String label;
  final Color color;
  final String? detail;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: loading
                ? const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.bodyMedium),
              if (detail != null)
                Text(detail!, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// État de l'IA (lecture seule : elle se configure sur le serveur).
class _AiCard extends ConsumerWidget {
  const _AiCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final status = ref.watch(aiStatusProvider);
    final ai = status.value;

    Widget body;
    if (ai != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ai.enabled) ...[
            const Gap(8),
            InfoRow(
              icon: Icons.hub_outlined,
              label: 'Fournisseur',
              value: aiProviderLabel(ai.provider),
            ),
            InfoRow(icon: Icons.memory_rounded, label: 'Modèle', value: ai.model),
          ],
          const Gap(8),
          Text(
            ai.enabled
                ? 'Utilisée pour analyser les offres et préparer vos candidatures. '
                      'Le fournisseur et le modèle se règlent dans la configuration du serveur.'
                : 'L\'IA n\'est pas activée sur ce serveur : l\'analyse des offres utilise des '
                      'règles automatiques. L\'administrateur peut l\'activer dans la '
                      'configuration du serveur.',
            style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      );
    } else if (status.hasError) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              'État de l\'IA indisponible.',
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(aiStatusProvider),
            child: const Text('Réessayer'),
          ),
        ],
      );
    } else {
      body = const LoadingView(padding: EdgeInsets.symmetric(vertical: 12));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              const Gap(14),
              Expanded(child: Text('Assistant IA', style: theme.titleSmall)),
              if (ai != null)
                Pill(
                  ai.enabled ? 'Activée' : 'Désactivée',
                  color: ai.enabled ? AppColors.success : null,
                  dense: true,
                ),
            ],
          ),
          body,
        ],
      ),
    );
  }
}

/// Note de confidentialité.
class _PrivacySheet extends StatelessWidget {
  const _PrivacySheet();

  static const _points = [
    (
      Icons.dns_outlined,
      'Vos données restent chez vous',
      'Profil, documents, offres et candidatures sont stockés uniquement sur le serveur '
          'que vous avez choisi.',
    ),
    (
      Icons.key_outlined,
      'Session protégée',
      'Vos jetons de connexion sont conservés dans le stockage sécurisé de l\'appareil.',
    ),
    (
      Icons.visibility_off_outlined,
      'Aucun traceur',
      'L\'application n\'intègre ni publicité ni outil de mesure d\'audience.',
    ),
    (
      Icons.share_outlined,
      'Services externes',
      'Si l\'IA, Telegram ou l\'email sont activés sur le serveur, seules les informations '
          'nécessaires (offre, profil, alerte) leur sont transmises.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Confidentialité', style: theme.titleLarge),
            const Gap(20),
            for (final (index, point) in _points.indexed) ...[
              if (index > 0) const Gap(18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(point.$1, size: 20, color: AppColors.textSecondary),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(point.$2, style: theme.titleSmall),
                        const Gap(2),
                        Text(
                          point.$3,
                          style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
