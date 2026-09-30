import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/ui.dart';
import 'data/profile_models.dart';
import 'data/profile_providers.dart';
import 'widgets/profile_widgets.dart';

/// Postes recherchés (`/job-titles`) : comparés au titre de chaque offre.
class JobTitlesPage extends ConsumerWidget {
  const JobTitlesPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(jobTitlesProvider);
    try {
      await ref.read(jobTitlesProvider.future);
    } catch (_) {
      // Erreur affichée par la page.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(jobTitlesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Postes recherchés')),
      floatingActionButton: titles.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _openSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            )
          : null,
      body: AsyncValueView<List<JobTitle>>(
        value: titles,
        onRetry: () => ref.invalidate(jobTitlesProvider),
        data: (items) {
          if (items.isEmpty) {
            return PageListView(
              onRefresh: () => _refresh(ref),
              children: [
                EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'Aucun poste recherché',
                  message:
                      'Ajoutez les intitulés que vous visez (« Développeur Python », '
                      '« Backend Developer »…) : ils sont comparés au titre de chaque offre.',
                  actionLabel: 'Ajouter un poste',
                  onAction: () => _openSheet(context),
                ),
              ],
            );
          }
          final active = items.where((t) => t.enabled).toList();
          final inactive = items.where((t) => !t.enabled).toList();
          return PageListView(
            onRefresh: () => _refresh(ref),
            children: [
              const IntroText(
                'Le titre de chaque offre est comparé à ces postes (français et anglais : '
                '« développeur » = « developer »). Ajoutez les variantes que vous visez.',
              ),
              if (active.isNotEmpty) ...[
                SectionHeader('Actifs', trailing: _Count(active.length)),
                _TitlesCard(items: active),
              ],
              if (inactive.isNotEmpty) ...[
                SectionHeader('Désactivés', trailing: _Count(inactive.length)),
                _TitlesCard(items: inactive),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Text(
    '$count',
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
  );
}

class _TitlesCard extends ConsumerWidget {
  const _TitlesCard({required this.items});

  final List<JobTitle> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(indent: AppSpacing.lg),
          ToggleListRow(
            title: items[i].title,
            enabled: items[i].enabled,
            onTap: () => _openSheet(context, item: items[i]),
            onToggle: (value) =>
                runAction(() => ref.read(jobTitlesProvider.notifier).setEnabled(items[i], value)),
            details: [
              if (items[i].priority != Priority.medium) PriorityPill(priority: items[i].priority),
            ],
          ),
        ],
      ],
    ),
  );
}

Future<void> _openSheet(BuildContext context, {JobTitle? item}) =>
    showAppSheet<void>(context, builder: (_) => _JobTitleSheet(item: item));

class _JobTitleSheet extends ConsumerStatefulWidget {
  const _JobTitleSheet({this.item});

  final JobTitle? item;

  @override
  ConsumerState<_JobTitleSheet> createState() => _JobTitleSheetState();
}

class _JobTitleSheetState extends ConsumerState<_JobTitleSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item?.title);
  late Priority _priority = widget.item?.priority ?? Priority.medium;
  late bool _enabled = widget.item?.enabled ?? true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(jobTitlesProvider.notifier);
    final body = {'title': _title.text.trim(), 'priority': _priority.apiValue, 'enabled': _enabled};
    try {
      _editing ? await notifier.edit(widget.item!.id, body) : await notifier.add(body);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(_editing ? 'Poste mis à jour' : 'Poste ajouté', kind: ToastKind.success);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiException.describe(error);
        });
      }
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final confirmed = await confirmDialog(
      context,
      title: 'Supprimer « ${item.title} » ?',
      message: 'Pour l\'ignorer temporairement, vous pouvez aussi le désactiver.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(jobTitlesProvider.notifier).remove(item.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Poste supprimé', kind: ToastKind.success);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiException.describe(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: FormSheet(
      title: _editing ? 'Modifier le poste' : 'Ajouter un poste',
      trailing: _editing
          ? IconButton(
              tooltip: 'Supprimer',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            )
          : null,
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        PrimaryButton(
          label: _editing ? 'Enregistrer' : 'Ajouter',
          loading: _saving,
          onPressed: _submit,
        ),
      ],
      children: [
        AppTextField(
          label: 'Intitulé',
          controller: _title,
          hint: 'Développeur Full Stack',
          autofocus: !_editing,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
          onSubmitted: (_) => _submit(),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.length < 2) return '2 caractères minimum';
            if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
              return 'Lettres ou chiffres attendus';
            }
            return null;
          },
        ),
        formGap,
        const FieldLabel('Priorité'),
        PrioritySelector(value: _priority, onChanged: (p) => setState(() => _priority = p)),
        const Gap(8),
        SwitchRow(
          title: 'Recherche active',
          subtitle: 'Désactivé, le poste est ignoré par le matching.',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        if (_error != null) ...[const Gap(12), InlineError(message: _error!)],
      ],
    ),
  );
}
