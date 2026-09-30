import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'widgets/brand_mark.dart';
import 'widgets/server_sheet.dart';

/// Connexion (et création de compte si le serveur l'autorise).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = ref.read(authControllerProvider).message;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_registerMode) {
        await auth.register(email: _email.text, password: _password.text);
      } else {
        await auth.login(email: _email.text, password: _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = ApiException.describe(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final server = ref.watch(serverUrlProvider);
    final serverLabel = server.replaceFirst(RegExp(r'^https?://'), '');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(size: 52),
                      const Gap(36),
                      Text(
                        _registerMode ? 'Créer un compte' : 'Bon retour.',
                        style: theme.displaySmall,
                      ),
                      const Gap(8),
                      Text(
                        _registerMode
                            ? 'Le premier compte créé devient administrateur.'
                            : 'Vos offres, vos candidatures, au même endroit.',
                        style: theme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                      ),
                      const Gap(36),
                      AppTextField(
                        label: 'Email',
                        controller: _email,
                        hint: 'vous@exemple.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: Validators.email,
                      ),
                      formGap,
                      AppTextField(
                        label: 'Mot de passe',
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          _registerMode ? AutofillHints.newPassword : AutofillHints.password,
                        ],
                        validator: _registerMode ? Validators.password : Validators.required,
                        onSubmitted: (_) => _submit(),
                        suffix: IconButton(
                          tooltip: _obscure ? 'Afficher' : 'Masquer',
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      if (_error != null) ...[const Gap(16), _ErrorBanner(message: _error!)],
                      const Gap(28),
                      PrimaryButton(
                        label: _registerMode ? 'Créer mon compte' : 'Se connecter',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      const Gap(12),
                      Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _registerMode = !_registerMode;
                                  _error = null;
                                }),
                          child: Text(
                            _registerMode ? 'J\'ai déjà un compte' : 'Créer un compte',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      const Gap(32),
                      const Divider(),
                      const Gap(8),
                      InkWell(
                        borderRadius: AppRadius.input,
                        onTap: () =>
                            showAppSheet<void>(context, builder: (_) => const ServerSheet()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.dns_outlined,
                                size: 18,
                                color: AppColors.textTertiary,
                              ),
                              const Gap(10),
                              Expanded(
                                child: Text(
                                  'Serveur · $serverLabel',
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                                ),
                              ),
                              const Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.tint(AppColors.danger, 0.08),
      borderRadius: AppRadius.input,
      border: Border.all(color: AppColors.tint(AppColors.danger, 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
        const Gap(10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.danger),
          ),
        ),
      ],
    ),
  );
}
