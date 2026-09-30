import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/reference.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';
import '../data/profile_labels.dart';
import '../data/profile_repository.dart';

/// Suggestion rapide (nom + catégorie éventuelle), affichée quand la recherche est vide.
class CatalogSuggestion {
  const CatalogSuggestion(this.name, [this.category]);
  final String name;
  final String? category;
}

/// Recherche dans le catalogue de compétences avec autocomplétion
/// (`GET /skills/catalog?search=`), ou saisie libre d'un nom hors catalogue.
class CatalogSearchPanel extends ConsumerStatefulWidget {
  const CatalogSearchPanel({
    super.key,
    required this.onSelected,
    this.existing = const {},
    this.suggestions = const [],
    this.suggestionsLabel = 'Suggestions',
    this.hint = 'Rechercher : Python, React, Docker…',
    this.existingLabel = 'Déjà ajoutée',
    this.initialQuery,
  });

  /// Appelé avec le nom choisi et sa catégorie (null si inconnue).
  final void Function(String name, String? category) onSelected;

  /// Noms déjà présents (en minuscules) : affichés mais non sélectionnables.
  final Set<String> existing;
  final List<CatalogSuggestion> suggestions;
  final String suggestionsLabel;
  final String hint;
  final String existingLabel;
  final String? initialQuery;

  @override
  ConsumerState<CatalogSearchPanel> createState() => _CatalogSearchPanelState();
}

class _CatalogSearchPanelState extends ConsumerState<CatalogSearchPanel> {
  late final TextEditingController _query;
  Timer? _debounce;
  List<CatalogSkill> _results = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    if ((widget.initialQuery ?? '').trim().isNotEmpty) _search(widget.initialQuery!);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {});
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(profileRepositoryProvider).searchCatalog(value);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = ApiException.describe(error);
      });
    }
  }

  bool _isExisting(String name) => widget.existing.contains(name.trim().toLowerCase());

  void _submitFreeText() {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    // Correspondance exacte dans les résultats : on garde la catégorie du catalogue.
    for (final skill in _results) {
      if (skill.name.toLowerCase() == text.toLowerCase()) {
        if (!_isExisting(skill.name)) widget.onSelected(skill.name, skill.category);
        return;
      }
    }
    if (!_isExisting(text)) widget.onSelected(text, null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final categories = ref.watch(skillCategoriesProvider).value ?? const <SkillCategory>[];
    final query = _query.text.trim();
    final exact = _results.any((s) => s.name.toLowerCase() == query.toLowerCase());
    final suggestions = widget.suggestions.where((s) => !_isExisting(s.name)).take(16).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _query,
          hint: widget.hint,
          prefixIcon: Icons.search_rounded,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: _onChanged,
          onSubmitted: (_) => _submitFreeText(),
          suffix: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _query.clear();
                    _onChanged('');
                  },
                ),
        ),
        const Gap(12),
        if (query.isEmpty && suggestions.isNotEmpty) ...[
          FieldLabel(widget.suggestionsLabel),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in suggestions)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: Text(suggestion.name),
                  onPressed: () => widget.onSelected(suggestion.name, suggestion.category),
                ),
            ],
          ),
        ],
        if (query.isEmpty && suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Tapez quelques lettres pour chercher dans le catalogue. '
              'Un nom absent du catalogue peut aussi être ajouté.',
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: theme.bodySmall?.copyWith(color: AppColors.danger)),
          ),
        if (query.isNotEmpty)
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _results.length; i++) ...[
                  if (i > 0) const Divider(indent: AppSpacing.lg),
                  _ResultRow(
                    name: _results[i].name,
                    subtitle: _results[i].category == null
                        ? null
                        : categoryLabel(_results[i].category, categories),
                    existingLabel: _isExisting(_results[i].name) ? widget.existingLabel : null,
                    onTap: () => widget.onSelected(_results[i].name, _results[i].category),
                  ),
                ],
                if (!exact && !_loading) ...[
                  if (_results.isNotEmpty) const Divider(indent: AppSpacing.lg),
                  _ResultRow(
                    name: 'Ajouter « $query »',
                    subtitle: 'Hors catalogue',
                    icon: Icons.add_circle_outline_rounded,
                    existingLabel: _isExisting(query) ? widget.existingLabel : null,
                    onTap: () => widget.onSelected(query, null),
                  ),
                ],
                if (_results.isEmpty && _loading)
                  const LoadingView(padding: EdgeInsets.symmetric(vertical: 20)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.name,
    required this.onTap,
    this.subtitle,
    this.existingLabel,
    this.icon = Icons.add_rounded,
  });

  final String name;
  final String? subtitle;
  final String? existingLabel;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final disabled = existingLabel != null;
    return InkWell(
      onTap: disabled ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.bodyLarge?.copyWith(
                        color: disabled ? AppColors.textTertiary : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ),
              if (disabled)
                Pill(existingLabel!, dense: true, icon: Icons.check_rounded)
              else
                Icon(icon, size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
