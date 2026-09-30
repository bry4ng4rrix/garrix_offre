import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui.dart';

/// Saisie d'une liste de mots (technologies d'une expérience...) sous forme de pastilles.
/// Entrée ou virgule pour valider ; suggestions en un toucher.
class TagInput extends StatefulWidget {
  const TagInput({
    super.key,
    required this.values,
    required this.onChanged,
    this.label,
    this.hint = 'Ajouter puis Entrée',
    this.suggestions = const [],
    this.maxTags = 50,
    this.optional = false,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String? label;
  final String hint;
  final List<String> suggestions;
  final int maxTags;
  final bool optional;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _contains(String value) =>
      widget.values.any((v) => v.toLowerCase() == value.trim().toLowerCase());

  void _add(String raw) {
    final next = [...widget.values];
    for (final part in raw.split(',')) {
      final value = part.trim();
      if (value.isEmpty || next.length >= widget.maxTags) continue;
      if (next.any((v) => v.toLowerCase() == value.toLowerCase())) continue;
      next.add(value);
    }
    _controller.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  void _remove(String value) => widget.onChanged([...widget.values]..remove(value));

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.suggestions.where((s) => !_contains(s)).take(12).toList();
    final full = widget.values.length >= widget.maxTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) FieldLabel(widget.label!, optional: widget.optional),
        if (widget.values.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in widget.values)
                InputChip(
                  label: Text(value),
                  onDeleted: () => _remove(value),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  deleteButtonTooltipMessage: 'Retirer',
                ),
            ],
          ),
          const Gap(10),
        ],
        TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: !full,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) {
            if (value.contains(',')) _add(value);
          },
          onSubmitted: (value) {
            _add(value);
            _focus.requestFocus();
          },
          decoration: InputDecoration(
            hintText: full ? 'Maximum atteint' : widget.hint,
            prefixIcon: const Icon(Icons.sell_outlined, size: 18),
            suffixIcon: IconButton(
              tooltip: 'Ajouter',
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: full ? null : () => _add(_controller.text),
            ),
          ),
        ),
        if (suggestions.isNotEmpty && !full) ...[
          const Gap(10),
          Text(
            'Suggestions',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          const Gap(6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in suggestions)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: Text(suggestion),
                  onPressed: () => _add(suggestion),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
