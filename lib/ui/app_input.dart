import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared text-entry contract: explicit labels, predictable keyboard behaviour,
/// no smart substitutions in technical text, and accessible clear actions.
class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint, helper;
  final bool code, multiline, expands, autofocus, enabled, clearable;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final List<TextInputFormatter>? formatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged, onSubmitted;
  final Widget? prefix;
  final FocusNode? focusNode;
  const AppInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.code = false,
    this.multiline = false,
    this.expands = false,
    this.autofocus = false,
    this.enabled = true,
    this.clearable = true,
    this.maxLength,
    this.keyboardType,
    this.action,
    this.formatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.focusNode,
  });
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      autocorrect: !code,
      enableSuggestions: !code,
      smartDashesType: code
          ? SmartDashesType.disabled
          : SmartDashesType.enabled,
      smartQuotesType: code
          ? SmartQuotesType.disabled
          : SmartQuotesType.enabled,
      keyboardType:
          keyboardType ??
          (multiline
              ? TextInputType.multiline
              : code
              ? TextInputType.visiblePassword
              : TextInputType.text),
      textInputAction:
          action ??
          (multiline ? TextInputAction.newline : TextInputAction.done),
      inputFormatters: formatters,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      maxLines: multiline ? null : 1,
      minLines: multiline && !expands ? 4 : null,
      expands: expands,
      textAlignVertical: multiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      maxLength: maxLength,
      style: code
          ? const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5)
          : null,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        errorMaxLines: 3,
        prefixIcon: prefix,
        alignLabelWithHint: multiline,
        suffixIcon: enabled && clearable && !multiline && value.text.isNotEmpty
            ? IconButton(
                tooltip: '清空$label',
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
                icon: const Icon(Icons.close, size: 18),
              )
            : null,
      ),
    ),
  );
}
