import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint, helper;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final bool autofocus, enabled;
  final TextInputAction action;
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.onSubmitted,
    this.validator,
    this.autofocus = false,
    this.enabled = true,
    this.action = TextInputAction.done,
  });
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool visible = false;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    enabled: widget.enabled,
    obscureText: !visible,
    autocorrect: false,
    enableSuggestions: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    textInputAction: widget.action,
    onFieldSubmitted: widget.onSubmitted,
    validator: widget.validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      helperText: widget.helper,
      helperMaxLines: 3,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: visible ? '隐藏密码' : '显示密码',
        onPressed: widget.enabled
            ? () => setState(() => visible = !visible)
            : null,
        icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
      ),
    ),
  );
}
