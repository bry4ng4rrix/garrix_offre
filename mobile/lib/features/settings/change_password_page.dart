import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/settings_repository.dart';

/// Changement du mot de passe (`PUT /users/me/password`).
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _saving = false;

  /// Erreurs renvoyées par le serveur, affichées sous le champ concerné.
  String? _currentError;
  String? _newError;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _currentError = null;
      _newError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .changePassword(current: _current.text, newPassword: _new.text);
      if (!mounted) return;
      showToast('Mot de passe modifié', kind: ToastKind.success);
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      final fields = error.fieldErrors;
      if (error.code == 'INVALID_PASSWORD') {
        _currentError = 'Mot de passe actuel incorrect';
      } else if (fields.containsKey('new_password')) {
        _newError = '8 caractères minimum, avec au moins une lettre et un chiffre';
      } else if (fields.containsKey('current_password')) {
        _currentError = 'Mot de passe actuel invalide';
      } else {
        showError(error);
      }
      _formKey.currentState!.validate();
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _visibilityToggle(bool visible, VoidCallback onPressed) => IconButton(
    tooltip: visible ? 'Masquer' : 'Afficher',
    icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final checks = passwordChecks(_new.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe')),
      bottomNavigationBar: BottomActionBar(
        children: [PrimaryButton(label: 'Mettre à jour', loading: _saving, onPressed: _submit)],
      ),
      body: Form(
        key: _formKey,
        child: AutofillGroup(
          child: PageListView(
            children: [
              Text('Changer le mot de passe', style: theme.headlineSmall),
              const Gap(6),
              Text(
                'Saisissez votre mot de passe actuel puis choisissez-en un nouveau.',
                style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const Gap(28),
              AppTextField(
                label: 'Mot de passe actuel',
                controller: _current,
                obscureText: !_showCurrent,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.password],
                validator: (value) => _currentError ?? Validators.required(value),
                onChanged: (_) {
                  if (_currentError != null) setState(() => _currentError = null);
                },
                suffix: _visibilityToggle(
                  _showCurrent,
                  () => setState(() => _showCurrent = !_showCurrent),
                ),
              ),
              formGap,
              AppTextField(
                label: 'Nouveau mot de passe',
                controller: _new,
                obscureText: !_showNew,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  if (_newError != null) return _newError;
                  final rule = Validators.password(value);
                  if (rule != null) return rule;
                  if (value!.length > 128) return '128 caractères maximum';
                  if (value == _current.text) return 'Doit être différent du mot de passe actuel';
                  return null;
                },
                onChanged: (_) => setState(() => _newError = null),
                suffix: _visibilityToggle(_showNew, () => setState(() => _showNew = !_showNew)),
              ),
              const Gap(12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _Rule(label: '8 caractères', ok: checks.length),
                  _Rule(label: 'Une lettre', ok: checks.letter),
                  _Rule(label: 'Un chiffre', ok: checks.digit),
                ],
              ),
              formGap,
              AppTextField(
                label: 'Confirmation',
                controller: _confirm,
                obscureText: !_showNew,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Champ obligatoire';
                  return value == _new.text ? null : 'Les mots de passe ne correspondent pas';
                },
                onSubmitted: (_) => _saving ? null : _submit(),
              ),
              const Gap(24),
              Text(
                'Vos autres appareils restent connectés. Pour les déconnecter, utilisez '
                '« Déconnecter tous les appareils » dans les réglages.',
                style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Règle du mot de passe, cochée quand elle est respectée.
class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: color,
        ),
        const Gap(6),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
