import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_user.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_repository.dart';
import 'widgets/admin_ui.dart';

/// Comptes utilisateurs. Les inscriptions étant fermées côté serveur, c'est ici qu'on
/// crée les comptes.
class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _controller = PagedListController();
  int? _total;

  Future<void> _create() async {
    final user = await showAppSheet<AppUser>(context, builder: (_) => const _CreateUserSheet());
    if (user != null) await _controller.refresh();
  }

  Future<void> _open(AppUser user) => showAppSheet<void>(
    context,
    builder: (_) => _UserSheet(
      user: user,
      onChanged: (updated) =>
          _controller.updateWhere<AppUser>((u) => u.id == updated.id, (_) => updated),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final repo = ref.watch(adminRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Nouveau compte'),
      ),
      body: PagedListView<AppUser>(
        controller: _controller,
        fetch: (page) => repo.users(page: page),
        onTotal: (total) => setState(() => _total = total),
        header: [
          const Gap(4),
          const NoteBox(
            message:
                'Les inscriptions sont fermées : créez ici les comptes des personnes qui doivent '
                'accéder à l\'application.',
          ),
          ListCount(count: _total, singular: 'compte', plural: 'comptes'),
        ],
        emptyBuilder: (_) =>
            const EmptyState(icon: Icons.people_outline_rounded, title: 'Aucun compte'),
        itemBuilder: (context, user) =>
            _UserCard(user: user, isMe: user.id == me?.id, onTap: () => _open(user)),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.isMe, required this.onTap});

  final AppUser user;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          AppAvatar(label: user.email, size: 42),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: user.isActive ? AppColors.textPrimary : AppColors.textTertiary,
                  ),
                ),
                const Gap(2),
                Text(
                  user.lastLoginAt == null
                      ? 'Jamais connecté'
                      : 'Dernière connexion ${Fmt.relative(user.lastLoginAt)}',
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
                const Gap(8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _RolePill(isAdmin: user.isSuperuser),
                    if (!user.isActive)
                      const Pill('Désactivé', color: AppColors.danger, dense: true),
                    if (isMe) const Pill('Vous', filled: false, dense: true),
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

class _RolePill extends StatelessWidget {
  const _RolePill({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) => isAdmin
      ? const Pill(
          'Administrateur',
          color: AppColors.violet,
          icon: Icons.shield_outlined,
          dense: true,
        )
      : const Pill('Utilisateur', dense: true);
}

/// Gestion d'un compte : actif / administrateur (avec confirmation).
class _UserSheet extends ConsumerStatefulWidget {
  const _UserSheet({required this.user, required this.onChanged});

  final AppUser user;
  final ValueChanged<AppUser> onChanged;

  @override
  ConsumerState<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends ConsumerState<_UserSheet> {
  late AppUser _user = widget.user;
  bool _busy = false;

  Future<void> _toggleActive(bool value) async {
    final ok = await confirmDialog(
      context,
      title: value ? 'Réactiver ce compte ?' : 'Désactiver ce compte ?',
      message: value
          ? '${_user.email} pourra de nouveau se connecter.'
          : '${_user.email} ne pourra plus se connecter. Ses données sont conservées.',
      confirmLabel: value ? 'Réactiver' : 'Désactiver',
      destructive: !value,
    );
    if (ok) await _update(isActive: value);
  }

  Future<void> _toggleAdmin(bool value) async {
    final ok = await confirmDialog(
      context,
      title: value
          ? 'Donner les droits d\'administration ?'
          : 'Retirer les droits d\'administration ?',
      message: value
          ? '${_user.email} pourra gérer les comptes, les sources et les référentiels.'
          : '${_user.email} n\'aura plus accès à l\'administration.',
      confirmLabel: value ? 'Promouvoir' : 'Rétrograder',
      destructive: !value,
    );
    if (ok) await _update(isSuperuser: value);
  }

  Future<void> _update({bool? isActive, bool? isSuperuser}) async {
    if (!mounted) return;
    setState(() => _busy = true);
    final updated = await runAdmin(
      () => ref
          .read(adminRepositoryProvider)
          .updateUser(_user.id, isActive: isActive, isSuperuser: isSuperuser),
      success: 'Compte mis à jour',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (updated != null) _user = updated;
    });
    if (updated != null) widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final isMe = ref.watch(currentUserProvider)?.id == _user.id;
    final locked = isMe || _busy;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppAvatar(label: _user.email, size: 48),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _user.email,
                        style: theme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _RolePill(isAdmin: _user.isSuperuser),
                          if (isMe) const Pill('Vous', filled: false, dense: true),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Gap(12),
            InfoRow(
              icon: Icons.event_outlined,
              label: 'Compte créé',
              value: Fmt.dateTime(_user.createdAt),
            ),
            InfoRow(
              icon: Icons.login_rounded,
              label: 'Dernière connexion',
              value: _user.lastLoginAt == null ? 'Jamais' : Fmt.dateTime(_user.lastLoginAt),
            ),
            const Divider(height: 24),
            SwitchRow(
              title: 'Compte actif',
              subtitle: 'Un compte désactivé ne peut plus se connecter.',
              value: _user.isActive,
              onChanged: locked ? null : _toggleActive,
            ),
            SwitchRow(
              title: 'Administrateur',
              subtitle: 'Accès aux comptes, sources, collectes et référentiels.',
              value: _user.isSuperuser,
              onChanged: locked ? null : _toggleAdmin,
            ),
            if (isMe) ...[
              const Gap(8),
              const NoteBox(
                message: 'Vous ne pouvez pas désactiver ni rétrograder votre propre compte.',
                icon: Icons.lock_outline_rounded,
              ),
            ],
            const Gap(16),
            PrimaryButton(
              label: 'Terminé',
              outlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Création d'un compte (`POST /users`).
class _CreateUserSheet extends ConsumerStatefulWidget {
  const _CreateUserSheet();

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _admin = false;
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Mot de passe aléatoire respectant la règle du serveur (lettres et chiffres).
  void _generate() {
    const letters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
    const digits = '23456789';
    final random = Random.secure();
    final chars = [
      for (var i = 0; i < 11; i++) letters[random.nextInt(letters.length)],
      for (var i = 0; i < 3; i++) digits[random.nextInt(digits.length)],
    ]..shuffle(random);
    setState(() {
      _password.text = chars.join();
      _obscure = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final user = await runAdmin(
      () => ref
          .read(adminRepositoryProvider)
          .createUser(email: _email.text, password: _password.text, isSuperuser: _admin),
      success: 'Compte créé',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (user != null) Navigator.of(context).pop(user);
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: 'Nouveau compte',
    subtitle: 'Communiquez le mot de passe à la personne : il ne sera plus affiché ensuite.',
    formKey: _formKey,
    expand: false,
    saving: _saving,
    submitLabel: 'Créer le compte',
    onSubmit: _submit,
    children: [
      AppTextField(
        label: 'Email',
        controller: _email,
        hint: 'prenom.nom@exemple.com',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        validator: Validators.email,
        autofocus: true,
      ),
      formGap,
      AppTextField(
        label: 'Mot de passe',
        controller: _password,
        obscureText: _obscure,
        validator: Validators.password,
        helper: '8 caractères minimum, avec au moins une lettre et un chiffre.',
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Générer',
              icon: const Icon(Icons.casino_outlined, size: 20),
              onPressed: _generate,
            ),
            IconButton(
              tooltip: 'Copier',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                if (_password.text.isNotEmpty) {
                  copyText(_password.text, message: 'Mot de passe copié');
                }
              },
            ),
            IconButton(
              tooltip: _obscure ? 'Afficher' : 'Masquer',
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ],
        ),
      ),
      const Gap(8),
      SwitchRow(
        title: 'Administrateur',
        subtitle: 'Accès complet à l\'administration.',
        value: _admin,
        onChanged: (value) => setState(() => _admin = value),
      ),
    ],
  );
}
