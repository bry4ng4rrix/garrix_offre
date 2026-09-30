import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'ui.dart';

/// Libellé au-dessus d'un champ (style moderne : pas de libellé flottant).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        text: text,
        children: [
          if (optional)
            const TextSpan(
              text: '  facultatif',
              style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w400),
            ),
        ],
      ),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
    ),
  );
}

/// Champ texte avec libellé au-dessus.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helper,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.enabled = true,
    this.optional = false,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
  });

  final String? label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helper;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool optional;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label != null) FieldLabel(label!, optional: optional),
      TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        minLines: minLines,
        maxLength: maxLength,
        validator: validator,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        autofillHints: autofillHints,
        inputFormatters: inputFormatters,
        enabled: enabled,
        autofocus: autofocus,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
          suffixIcon: suffix,
        ),
      ),
    ],
  );
}

/// Validateurs courants.
abstract final class Validators {
  static String? required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Champ obligatoire' : null;

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Champ obligatoire';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim()) ? null : 'Email invalide';
  }

  /// Même règle que le serveur : 8 caractères, au moins une lettre et un chiffre.
  static String? password(String? value) {
    if (value == null || value.length < 8) return '8 caractères minimum';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Au moins une lettre et un chiffre';
    }
    return null;
  }

  static String? optionalUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    return (uri != null && uri.hasScheme && uri.host.isNotEmpty)
        ? null
        : 'URL invalide (https://...)';
  }

  static String? optionalInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return int.tryParse(value.trim()) == null ? 'Nombre entier attendu' : null;
  }
}

/// Choix unique parmi des pastilles.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.allowDeselect = false,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onSelected;
  final bool allowDeselect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(labelOf(value)),
          selected: value == selected,
          labelStyle: TextStyle(
            color: value == selected ? AppColors.onAccent : AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          onSelected: (on) => onSelected(on ? value : (allowDeselect ? null : value)),
        ),
    ],
  );
}

/// Choix multiple parmi des pastilles.
class MultiChoiceChips<T> extends StatelessWidget {
  const MultiChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T value) labelOf;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        FilterChip(
          label: Text(labelOf(value)),
          selected: selected.contains(value),
          labelStyle: TextStyle(
            color: selected.contains(value) ? AppColors.onAccent : AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          onSelected: (on) {
            final next = {...selected};
            on ? next.add(value) : next.remove(value);
            onChanged(next);
          },
        ),
    ],
  );
}

/// Liste déroulante avec libellé.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.label,
    this.hint,
    this.optional = false,
    this.allowNull = false,
    this.nullLabel = 'Aucun',
  });

  final List<T> values;
  final T? value;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final bool optional;
  final bool allowNull;
  final String nullLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label != null) FieldLabel(label!, optional: optional),
      DropdownButtonFormField<T?>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(Icons.expand_more_rounded, color: AppColors.textTertiary),
        hint: hint == null ? null : Text(hint!),
        items: [
          if (allowNull) DropdownMenuItem<T?>(value: null, child: Text(nullLabel)),
          for (final item in values)
            DropdownMenuItem<T?>(
              value: item,
              child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}

/// Sélecteur de date (champ en lecture seule qui ouvre le calendrier).
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.optional = false,
    this.firstDate,
    this.lastDate,
    this.clearable = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;
  final bool optional;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool clearable;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label != null) FieldLabel(label!, optional: optional),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: firstDate ?? DateTime(1970),
            lastDate: lastDate ?? DateTime(now.year + 10),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            suffixIcon: clearable && value != null
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => onChanged(null),
                  )
                : null,
          ),
          child: Text(
            value == null ? 'Choisir une date' : Fmt.date(value),
            style: TextStyle(color: value == null ? AppColors.textTertiary : AppColors.textPrimary),
          ),
        ),
      ),
    ],
  );
}

/// Ligne avec interrupteur.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.bodyLarge),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                ],
              ),
            ),
            const Gap(12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Curseur avec libellé et valeur (poids du matching, seuil...).
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.format,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value)? format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.bodyMedium)),
            Text(
              format?.call(value) ?? value.round().toString(),
              style: theme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

/// Espace standard entre deux champs de formulaire.
const formGap = Gap(18);
