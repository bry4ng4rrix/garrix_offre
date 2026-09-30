import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';

/// Choix de l'adresse du serveur, avec test de connexion (`GET /ready`).
/// Utilisée par l'écran de connexion et les réglages.
class ServerSheet extends ConsumerStatefulWidget {
  const ServerSheet({super.key});

  @override
  ConsumerState<ServerSheet> createState() => _ServerSheetState();
}

enum _TestState { idle, testing, ok, failed }

class _ServerSheetState extends ConsumerState<ServerSheet> {
  late final TextEditingController _url;
  _TestState _test = _TestState.idle;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final url = ServerUrlNotifier.normalize(_url.text);
    setState(() {
      _test = _TestState.testing;
      _detail = null;
    });
    try {
      final response = await Dio(
        BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)),
      ).get<dynamic>('$url/ready');
      final data = response.data;
      final ok = data is Map && data['status'] == 'ready';
      setState(() {
        _test = ok ? _TestState.ok : _TestState.failed;
        _detail = ok ? 'Serveur prêt (base de données et Redis joignables).' : 'Réponse inattendue.';
      });
    } on DioException catch (error) {
      setState(() {
        _test = _TestState.failed;
        _detail = error.response != null
            ? 'Le serveur répond mais n\'est pas prêt (HTTP ${error.response!.statusCode}).'
            : 'Serveur injoignable à cette adresse.';
      });
    }
  }

  Future<void> _save() async {
    final url = ServerUrlNotifier.normalize(_url.text);
    if (url == ref.read(serverUrlProvider)) {
      Navigator.of(context).pop();
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (auth.isSignedIn) {
      // La session appartient à l'ancien serveur : on la ferme là-bas avant de changer d'adresse.
      final confirmed = await confirmDialog(
        context,
        title: 'Changer de serveur ?',
        message: 'Vous serez déconnecté puis devrez vous reconnecter sur le nouveau serveur.',
        confirmLabel: 'Changer',
      );
      if (!confirmed || !mounted) return;
      await ref.read(authControllerProvider.notifier).logout();
    }
    await ref.read(serverUrlProvider.notifier).update(url);
    if (mounted) Navigator.of(context).maybePop();
    showToast('Serveur enregistré', kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final (color, icon) = switch (_test) {
      _TestState.ok => (AppColors.success, Icons.check_circle_outline_rounded),
      _TestState.failed => (AppColors.danger, Icons.error_outline_rounded),
      _ => (AppColors.textTertiary, Icons.info_outline_rounded),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Serveur', style: theme.titleLarge),
            const Gap(6),
            Text(
              'Adresse de l\'API Garrix Offre (avec le port).',
              style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const Gap(20),
            AppTextField(
              controller: _url,
              hint: kDefaultServerUrl,
              keyboardType: TextInputType.url,
              prefixIcon: Icons.dns_outlined,
              onChanged: (_) => setState(() => _test = _TestState.idle),
            ),
            if (_detail != null || _test == _TestState.testing) ...[
              const Gap(12),
              Row(
                children: [
                  if (_test == _TestState.testing)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(icon, size: 16, color: color),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      _test == _TestState.testing ? 'Test en cours...' : _detail!,
                      style: theme.bodySmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ],
            const Gap(20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _test == _TestState.testing ? null : _check,
                    child: const Text('Tester'),
                  ),
                ),
                const Gap(10),
                Expanded(child: FilledButton(onPressed: _save, child: const Text('Enregistrer'))),
              ],
            ),
            const Gap(4),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _url.text = kDefaultServerUrl;
                  _test = _TestState.idle;
                  _detail = null;
                }),
                child: const Text(
                  'Revenir au serveur par défaut',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
