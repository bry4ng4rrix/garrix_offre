/// Page de résultats : `{"items": [...], "pagination": {total, page, page_size, pages}}`.
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.pages,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final int pages;

  bool get hasMore => page < pages;

  factory Paginated.fromJson(Object? json, T Function(Map<String, dynamic> item) itemFromJson) {
    final map = (json as Map).cast<String, dynamic>();
    final meta = (map['pagination'] as Map? ?? const {}).cast<String, dynamic>();
    final items = (map['items'] as List? ?? const [])
        .map((e) => itemFromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return Paginated(
      items: items,
      total: (meta['total'] as num?)?.toInt() ?? items.length,
      page: (meta['page'] as num?)?.toInt() ?? 1,
      pageSize: (meta['page_size'] as num?)?.toInt() ?? items.length,
      pages: (meta['pages'] as num?)?.toInt() ?? 1,
    );
  }

  static Paginated<T> empty<T>() =>
      Paginated<T>(items: const [], total: 0, page: 1, pageSize: 20, pages: 0);
}
