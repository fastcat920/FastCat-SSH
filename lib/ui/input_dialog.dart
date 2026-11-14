import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_input.dart';
import 'password_field.dart';
import 'syntax_controller.dart';
import 'code_editor.dart';

class InputDialog extends StatefulWidget {
  final String title, initial;
  final String? hint, helper;
  final bool secret, multiline, code, allowEmpty;
  final FormFieldValidator<String>? validator;
  const InputDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.hint,
    this.helper,
    this.secret = false,
    this.multiline = false,
    this.code = false,
    this.allowEmpty = false,
    this.validator,
  });
  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  late final TextEditingController controller = widget.multiline && widget.code
      ? SyntaxController(text: widget.initial)
      : TextEditingController(text: widget.initial);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String? validate(String? value) {
    if (!widget.allowEmpty && (value ?? '').trim().isEmpty) return '请输入内容';
    return widget.validator?.call(value);
  }

  bool closing = false;
  void submit() {
    if (closing) return;
    if (form.currentState!.validate()) {
      closing = true;
      Navigator.pop(context, controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): submit,
    },
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.multiline ? 640 : 440,
        child: Form(
          key: form,
          child: widget.secret
              ? PasswordField(
                  controller: controller,
                  label: '密码',
                  autofocus: true,
                  helper: widget.helper,
                  validator: validate,
                  onSubmitted: (_) => submit(),
                )
              : SizedBox(
                  height: widget.multiline
                      ? (MediaQuery.sizeOf(context).height * .4).clamp(
                          100.0,
                          360.0,
                        )
                      : null,
                  child: widget.multiline && widget.code
                      ? CodeEditor(
                          controller: controller,
                          label: '文件内容',
                          hint: widget.hint,
                          autofocus: true,
                          validator: validate,
                        )
                      : AppInput(
                          controller: controller,
                          label: widget.multiline ? '内容' : widget.title,
                          hint: widget.hint,
                          helper: widget.helper,
                          autofocus: true,
                          multiline: widget.multiline,
                          expands: widget.multiline,
                          code: widget.code,
                          validator: validate,
                          onSubmitted: widget.multiline
                              ? null
                              : (_) => submit(),
                        ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: submit, child: const Text('确定')),
      ],
    ),
  );
}
