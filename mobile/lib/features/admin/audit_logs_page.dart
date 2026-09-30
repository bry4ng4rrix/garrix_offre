import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/paged_list_view.dart';
import '../../core/widgets/ui.dart';
import 'data/admin_labels.dart';
import 'data/admin_providers.dart';
import 'data/admin_repository.dart';
import 'data/audit_models.dart';
import 'widgets/admin_ui.dart';

/// Journal d'audit : opérations sensibles (connexions, candidatures, comptes, collectes...).
class AuditLogsPage extends ConsumerStatefulWidget {
  const AuditLogsPage({super.key});

  @override
  ConsumerState<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends ConsumerState<AuditLogsPage> {
  /// Préfixe d'action (`auth.`), filtré côté serveur.
  String? _action;
  String? _entityType;
  int? _total;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminRepositoryProvider);
    final emails = ref.watch(userEmailsProvider).value ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d\'audit'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Type d\'élément',
            icon: Badge(
              isLabelVisible: _entityType != null,
              smallSize: 8,
              backgroundColor: AppColors.textPrimary,
              child: const Icon(Icons.filter_list_rounded),
            ),
            initialValue: _entityType ?? '',
            onSelected: (value) => setState(() => _entityType = value.isEmpty ? null : value),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Tous les éléments')),
              for (final entry in auditEntityTypes.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
          ),
          const Gap(8),
        ],
      ),
      body: PagedListView<AuditLog>(
        key: ValueKey('$_action|$_entityType'),
        fetch: (page) => repo.auditLogs(page: page, action: _action, entityType: _entityType),
        onTotal: (total) => setState(() => _total = total),
        separator: const Gap(8),
        header: [
          const Gap(4),
          ChipBar<String>(
            values: auditActionGroups.keys.toList(),
            selected: _action,
            labelOf: (prefix) => auditActionGroups[prefix]!,
            allLabel: 'Toutes',
            onSelected: (prefix) => setState(() => _action = prefix),
          ),
          if (_entityType != null) ...[
            const Gap(10),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(entityTypeLabel(_entityType)),
                onDeleted: () => setState(() => _entityType = null),
              ),
            ),
          ],
          ListCount(count: _total, singular: 'entrée', plural: 'entrées'),
        ],
        emptyBuilder: (_) => const EmptyState(
          icon: Icons.history_rounded,
          title: 'Aucune entrée',
          message: 'Aucune opération ne correspond à ces filtres.',
        ),
        itemBuilder: (context, log) => _AuditTile(log: log, actorEmail: emails[log.actorId]),
      ),
    );
  }
}

class _AuditTile extends StatefulWidget {
  const _AuditTile({required this.log, this.actorEmail});

  final AuditLog log;
  final String? actorEmail;

  @override
  State<_AuditTile> createState() => _AuditTileState();
}

class _AuditTileState extends State<_AuditTile> {
  bool _expanded = false;

  (IconData, Color) get _visual {
    final action = widget.log.action;
    if (action.endsWith('failed') || action.endsWith('deleted')) {
      return (Icons.error_outline_rounded, AppColors.danger);
    }
    return switch (action.split('.').first) {
      'auth' => (Icons.login_rounded, AppColors.textSecondary),
      'user' => (Icons.person_outline_rounded, AppColors.violet),
      'application' => (Icons.send_rounded, AppColors.info),
      'document' => (Icons.description_outlined, AppColors.textSecondary),
      'scraping' => (Icons.cloud_sync_outlined, AppColors.success),
      'matching' => (Icons.bolt_rounded, AppColors.warning),
      'webhook' => (Icons.webhook_rounded, AppColors.textSecondary),
      _ => (Icons.history_rounded, AppColors.textSecondary),
    };
  }

  String get _actor {
    final log = widget.log;
    final type = log.actorType?.label ?? log.actorTypeValue;
    if (log.actorType == ActorType.user) {
      if (widget.actorEmail != null) return widget.actorEmail!;
      if (log.actorId != null) return '$type ${_short(log.actorId!)}';
    }
    return type;
  }

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final log = widget.log;
    final (icon, color) = _visual;

    return AppCard(
      onTap: () => setState(() => _expanded = !_expanded),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.tint(color),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            auditActionLabel(log.action),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Gap(8),
                        Text(
                          Fmt.relative(log.createdAt),
                          style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                    const Gap(2),
                    Text(
                      [
                        _actor,
                        if (log.entityType != null) entityTypeLabel(log.entityType),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Gap(4),
              Icon(
                _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(label: 'Action', value: log.action, mono: true),
                        _Line(label: 'Date', value: Fmt.dateTime(log.createdAt)),
                        _Line(label: 'Acteur', value: log.actorType?.label ?? log.actorTypeValue),
                        if (log.actorId != null)
                          _Line(label: 'Id acteur', value: log.actorId!, mono: true),
                        if (log.entityType != null)
                          _Line(label: 'Élément', value: entityTypeLabel(log.entityType)),
                        if (log.entityId != null)
                          _Line(label: 'Id élément', value: log.entityId!, mono: true),
                        const Gap(8),
                        JsonBlock(value: log.details, emptyLabel: 'Aucun détail.'),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
