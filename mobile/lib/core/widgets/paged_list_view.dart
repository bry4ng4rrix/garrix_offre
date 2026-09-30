import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../network/paginated.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Pilote une [PagedListView] depuis l'extérieur (ex. rafraîchir après une action).
class PagedListController {
  _PagedListViewState<dynamic>? _state;

  /// Recharge depuis la page 1.
  Future<void> refresh() async => _state?._reload();

  /// Met à jour un élément déjà chargé sans tout recharger.
  void updateWhere<T>(bool Function(T item) test, T Function(T item) update) =>
      _state?._updateWhere((item) => test(item as T), (item) => update(item as T));

  /// Retire un élément déjà chargé.
  void removeWhere<T>(bool Function(T item) test) => _state?._removeWhere((item) => test(item as T));
}

/// Liste paginée avec chargement infini, pull-to-refresh, états vide et erreur.
///
/// ```dart
/// PagedListView<Job>(
///   fetch: (page) => repo.search(filters, page: page),
///   itemBuilder: (context, job) => JobCard(job: job),
/// )
/// ```
/// Pour recharger quand les filtres changent, donnez une nouvelle `key` (ex. `ValueKey(filters)`).
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.controller,
    this.header,
    this.emptyBuilder,
    this.separator = const Gap(10),
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 96),
    this.onTotal,
  });

  final Future<Paginated<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final PagedListController? controller;

  /// Widgets affichés au-dessus des éléments (filtres, résumé...).
  final List<Widget>? header;
  final Widget Function(BuildContext context)? emptyBuilder;
  final Widget separator;
  final EdgeInsets padding;

  /// Appelé avec le nombre total de résultats après chaque chargement de la page 1.
  final ValueChanged<int>? onTotal;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _items = <T>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _scroll.addListener(_onScroll);
    unawaited(_loadMore());
  }

  @override
  void didUpdateWidget(covariant PagedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.fetch(_page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = result.page;
        _items.addAll(result.items);
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _loading = false;
      });
      if (result.page == 1) widget.onTotal?.call(result.total);
      // Liste plus courte que l'écran : charge la page suivante sans attendre un défilement.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _updateWhere(bool Function(dynamic) test, dynamic Function(dynamic) update) {
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        if (test(_items[i])) _items[i] = update(_items[i]) as T;
      }
    });
  }

  void _removeWhere(bool Function(dynamic) test) => setState(() => _items.removeWhere(test));

  @override
  Widget build(BuildContext context) {
    final header = widget.header ?? const <Widget>[];
    final showEmpty = _items.isEmpty && !_loading && _error == null && !_hasMore;
    final showFirstError = _items.isEmpty && _error != null;

    return RefreshIndicator(
      onRefresh: _reload,
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surfaceHigh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extra = math.max(0.0, (constraints.maxWidth - AppSpacing.maxContentWidth) / 2);
          final padding = widget.padding.copyWith(
            left: widget.padding.left + extra,
            right: widget.padding.right + extra,
          );
          return ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            itemCount: header.length + _items.length + 1,
            itemBuilder: (context, index) {
              if (index < header.length) return header[index];
              final i = index - header.length;
              if (i < _items.length) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (i > 0) widget.separator,
                    widget.itemBuilder(context, _items[i]),
                  ],
                );
              }
              // Pied de liste : chargement, erreur, vide ou fin.
              if (showFirstError) {
                return ErrorState(error: _error!, onRetry: _reload);
              }
              if (showEmpty) {
                return widget.emptyBuilder?.call(context) ??
                    const EmptyState(icon: Icons.inbox_outlined, title: 'Aucun élément');
              }
              if (_error != null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Réessayer'),
                    ),
                  ),
                );
              }
              if (_loading || _hasMore) {
                return LoadingView(
                  padding: EdgeInsets.symmetric(vertical: _items.isEmpty ? 64 : 24),
                );
              }
              return const SizedBox(height: 8);
            },
          );
        },
      ),
    );
  }
}
