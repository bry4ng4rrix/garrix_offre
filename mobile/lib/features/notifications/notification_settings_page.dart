import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/enums.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/notification_models.dart';
import 'data/notifications_repository.dart';
import 'widgets/notification_filter_bar.dart';

const _title = 'Préférences d\'alerte';

/// Canaux externes (Telegram, Email), types envoyés et seuil des offres très compatibles.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final threshold = ref.watch(matchingThresholdProvider);
    final loaded = settings.value;
    // Le seuil est facultatif : on attend seulement qu'il ait répondu (valeur ou null).
    if (loaded == null || !threshold.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text(_title)),
        body: AsyncValueView<NotificationSettings>(
          value: settings,
          onRetry: () => ref.invalidate(notificationSettingsProvider),
          data: (_) => const LoadingView(),
        ),
      );
    }
    return _SettingsForm(initial: loaded, initialThreshold: threshold.value);
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial, required this.initialThreshold});

  final NotificationSettings initial;
  final int? initialThreshold;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _chatId;
  late final TextEditingController _emailTo;
  late NotificationSettings _saved;
  late bool _telegram;
  late bool _email;
  late Set<NotificationType> _types;
  int? _savedThreshold;
  double? _threshold;
  bool _saving = false;
  Map<String, String> _serverErrors = const {};
  String? _channelError;

  @override
  void initState() {
    super.initState();
    _saved = widget.initial;
    _telegram = _saved.telegramEnabled;
    _email = _saved.emailEnabled;
    _types = {..._saved.externalTypes};
    _chatId = TextEditingController(text: _saved.telegramChatId ?? '');
    _emailTo = TextEditingController(text: _saved.emailTo ?? '');
    _savedThreshold = widget.initialThreshold;
    _threshold = widget.initialThreshold?.toDouble();
  }

  @override
  void dispose() {
    _chatId.dispose();
    _emailTo.dispose();
    super.dispose();
  }

  NotificationSettings get _current => NotificationSettings(
    telegramEnabled: _telegram,
    telegramChatId: _chatId.text.trim(),
    emailEnabled: _email,
    emailTo: _emailTo.text.trim(),
    externalTypes: _types,
    telegramConfigured: _saved.telegramConfigured,
    emailConfigured: _saved.emailConfigured,
  );

  bool get _settingsDirty =>
      jsonEncode(_current.toUpdateJson()) != jsonEncode(_saved.toUpdateJson());

  bool get _thresholdDirty => _threshold != null && _threshold!.round() != _savedThreshold;

  bool get _dirty => _settingsDirty || _thresholdDirty;

  void _edit(VoidCallback change) => setState(() {
    change();
    _channelError = null;
  });

  Future<void> _save() async {
    setState(() => _serverErrors = const {});
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _channelError = null;
    });
    final repository = ref.read(notificationsRepositoryProvider);
    try {
      if (_settingsDirty) {
        final saved = await repository.updateSettings(_current);
        if (!mounted) return;
        setState(() => _saved = saved);
      }
      if (_thresholdDirty) {
        final value = _threshold!.round();
        await repository.updateMatchingThreshold(value);
        if (!mounted) return;
        setState(() => _savedThreshold = value);
      }
      showToast('Préférences enregistrées', kind: ToastKind.success);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'TELEGRAM_NOT_CONFIGURED' || error.code == 'EMAIL_NOT_CONFIGURED') {
        setState(() => _channelError = error.userMessage);
      } else if (error.fieldErrors.keys.any(_knownFields.contains)) {
        setState(() => _serverErrors = error.fieldErrors);
        _formKey.currentState!.validate();
      } else {
        showError(error);
      }
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _knownFields = {'telegram_chat_id', 'email_to'};

  Future<void> _confirmLeave() async {
    final leave = await confirmDialog(
      context,
      title: 'Quitter sans enregistrer ?',
      message: 'Vos modifications seront perdues.',
      confirmLabel: 'Quitter',
      destructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  String? _validateChatId(String? value) {
    final server = _serverErrors['telegram_chat_id'];
    if (server != null) return 'Identifiant invalide';
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return telegramChatIdPattern.hasMatch(text) ? null : 'Nombre (ex. 123456789) ou @nom_du_canal';
  }

  String? _validateEmail(String? value) {
    if (_serverErrors['email_to'] != null) return 'Email invalide';
    if (value == null || value.trim().isEmpty) return null;
    return Validators.email(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final isAdmin = ref.watch(isAdminProvider);
    final userEmail = ref.watch(currentUserProvider)?.email;
    final noExternal = !_telegram && !_email;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text(_title)),
        bottomNavigationBar: BottomActionBar(
          children: [
            PrimaryButton(label: 'Enregistrer', loading: _saving, onPressed: _dirty ? _save : null),
          ],
        ),
        body: Form(
          key: _formKey,
          child: PageListView(
            children: [
              Text(
                'Toutes vos alertes restent visibles dans l\'application. Choisissez celles '
                'qui vous sont aussi envoyées sur Telegram ou par email.',
                style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              if (_channelError != null) ...[
                const Gap(16),
                _Notice(message: _channelError!, color: AppColors.danger),
              ],
              const SectionHeader('Canaux'),
              const _ChannelCard(
                icon: Icons.notifications_active_outlined,
                title: 'Dans l\'application',
                subtitle: 'Toujours actif, en temps réel',
                trailing: Pill('Actif', color: AppColors.success, dense: true),
              ),
              const Gap(10),
              _ChannelCard(
                icon: Icons.send_rounded,
                title: 'Telegram',
                subtitle: 'Message instantané envoyé par le bot du serveur',
                trailing: Switch(
                  value: _telegram,
                  onChanged: (value) => _edit(() => _telegram = value),
                ),
                children: [
                  if (!_saved.telegramConfigured)
                    const _Notice(
                      message:
                          'Le bot Telegram n\'est pas configuré sur le serveur. Vos réglages '
                          'sont enregistrés, mais aucun message ne sera envoyé pour l\'instant.',
                    ),
                  if (_telegram) ...[
                    AppTextField(
                      label: 'Chat id Telegram',
                      controller: _chatId,
                      hint: '123456789',
                      optional: isAdmin,
                      prefixIcon: Icons.tag_rounded,
                      keyboardType: TextInputType.text,
                      helper: isAdmin
                          ? 'Laissez vide pour utiliser le chat id défini sur le serveur.'
                          : 'Nécessaire pour recevoir les messages.',
                      validator: _validateChatId,
                      onChanged: (_) => _edit(() => _serverErrors = const {}),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                        onPressed: () =>
                            showAppSheet<void>(context, builder: (_) => const _TelegramHelpSheet()),
                        icon: const Icon(Icons.help_outline_rounded, size: 18),
                        label: const Text('Comment trouver mon chat id ?'),
                      ),
                    ),
                  ],
                ],
              ),
              const Gap(10),
              _ChannelCard(
                icon: Icons.alternate_email_rounded,
                title: 'Email',
                subtitle: 'Un email par alerte',
                trailing: Switch(value: _email, onChanged: (value) => _edit(() => _email = value)),
                children: [
                  if (!_saved.emailConfigured)
                    const _Notice(
                      message:
                          'L\'envoi d\'emails n\'est pas configuré sur le serveur (SMTP). Vos '
                          'réglages sont enregistrés, mais aucun email ne sera envoyé pour l\'instant.',
                    ),
                  if (_email)
                    AppTextField(
                      label: 'Adresse de réception',
                      controller: _emailTo,
                      optional: true,
                      hint: userEmail ?? 'vous@exemple.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      helper: userEmail == null
                          ? null
                          : 'Laissez vide pour recevoir les alertes sur $userEmail.',
                      validator: _validateEmail,
                      onChanged: (_) => _edit(() => _serverErrors = const {}),
                    ),
                ],
              ),
              const SectionHeader('Alertes envoyées hors de l\'application'),
              if (noExternal) ...[
                Text(
                  'Activez Telegram ou l\'email pour recevoir ces alertes en dehors de '
                  'l\'application.',
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
                const Gap(12),
              ],
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
                child: Column(
                  children: [
                    for (final (index, type) in filterableTypes(isAdmin: isAdmin).indexed) ...[
                      if (index > 0) const Divider(indent: 46),
                      _TypeSwitch(
                        type: type,
                        value: _types.contains(type),
                        dimmed: noExternal,
                        onChanged: (on) => _edit(() {
                          _types = {..._types};
                          on ? _types.add(type) : _types.remove(type);
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              if (_threshold != null) ...[
                const SectionHeader('Offres très compatibles'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SliderRow(
                        label: 'Score minimum',
                        value: _threshold!,
                        divisions: 20,
                        format: (value) => '${value.round()} %',
                        onChanged: (value) => _edit(() => _threshold = value),
                      ),
                      Text(
                        'Une alerte « Offre très compatible » est créée quand une nouvelle offre '
                        'atteint ce score de matching. Également réglable dans votre profil.',
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte d'un canal : icône, titre, interrupteur et contenu éventuel (avertissement, champs).
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
                child: Icon(icon, size: 20, color: AppColors.textSecondary),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.titleSmall),
                    Text(subtitle, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const Gap(12),
              trailing,
            ],
          ),
          for (final child in children) ...[const Gap(16), child],
        ],
      ),
    );
  }
}

/// Interrupteur d'un type de notification (icône teintée, libellé, description).
class _TypeSwitch extends StatelessWidget {
  const _TypeSwitch({
    required this.type,
    required this.value,
    required this.onChanged,
    this.dimmed = false,
  });

  final NotificationType type;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dimmed;

  static String description(NotificationType type) => switch (type) {
    NotificationType.newJob => 'Résumé des nouvelles offres collectées',
    NotificationType.highMatch => 'Offres qui atteignent votre score minimum',
    NotificationType.applicationStatus => 'Changements de statut de vos candidatures',
    NotificationType.recruiterResponse => 'Réponses de recruteurs détectées',
    NotificationType.scrapingError => 'Échecs de collecte des sources',
    NotificationType.system => 'Messages importants du serveur',
    NotificationType.monitoring => 'Alertes de supervision du serveur',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Opacity(
          opacity: dimmed ? 0.6 : 1,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.tint(type.color, 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(type.icon, size: 16, color: type.color),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label, style: theme.bodyLarge),
                    Text(
                      description(type),
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encadré d'information (avertissement par défaut).
class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.color = AppColors.warning});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.tint(color, 0.08),
      borderRadius: AppRadius.input,
      border: Border.all(color: AppColors.tint(color, 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: color),
        const Gap(10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

/// Aide : obtenir son identifiant de conversation Telegram.
class _TelegramHelpSheet extends StatelessWidget {
  const _TelegramHelpSheet();

  static const _steps = [
    (
      'Démarrez le bot',
      'Dans Telegram, ouvrez le bot de notification de votre serveur et envoyez-lui /start. '
          'Sans cela, il ne peut pas vous écrire.',
    ),
    (
      'Récupérez votre identifiant',
      'Écrivez à @userinfobot : il vous répond avec votre identifiant numérique '
          '(« Id: 123456789 »).',
    ),
    (
      'Collez-le ici',
      'Pour un groupe, ajoutez le bot au groupe : son identifiant commence par -100. '
          'Un canal public peut aussi être indiqué par son nom (@mon_canal).',
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
            Text('Trouver votre chat id', style: theme.titleLarge),
            const Gap(6),
            Text(
              'Le chat id indique au bot où envoyer vos alertes.',
              style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const Gap(20),
            for (final (index, step) in _steps.indexed) ...[
              if (index > 0) const Gap(16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Text('${index + 1}', style: theme.labelMedium),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.$1, style: theme.titleSmall),
                        const Gap(2),
                        Text(
                          step.$2,
                          style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const Gap(24),
            PrimaryButton(label: 'Compris', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
