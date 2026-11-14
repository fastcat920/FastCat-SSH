import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Multiline editor with a logical-line gutter. Wrapped continuation rows do not
/// increment file line numbers. Source and line endings are never rewritten.
class CodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled, autofocus, showHeader;
  final FormFieldValidator<String>? validator;
  const CodeEditor({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.enabled = true,
    this.autofocus = false,
    this.showHeader = true,
    this.validator,
  });
  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final scroll = ScrollController();
  final focus = FocusNode();
  final fieldKey = GlobalKey();
  final gutterKey = GlobalKey();
  RenderBox? gutterBox() =>
      gutterKey.currentContext?.findRenderObject() as RenderBox?;

  RenderEditable? editable() {
    RenderEditable? result;
    void visit(Element e) {
      if (e is StatefulElement && e.state is EditableTextState) {
        result = (e.state as EditableTextState).renderEditable;
      } else {
        e.visitChildren(visit);
      }
    }

    fieldKey.currentContext?.visitChildElements(visit);
    return result;
  }

  List<int> starts = [0];
  String? cachedText;
  static const style = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.normal,
    letterSpacing: 0,
    wordSpacing: 0,
  );
  static const strut = StrutStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
    forceStrutHeight: true,
  );
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    focus.addListener(changed);
    updateLines();
  }

  @override
  void didUpdateWidget(covariant CodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(changed);
      widget.controller.addListener(changed);
      cachedText = null;
      updateLines();
    }
  }

  void updateLines() {
    final text = widget.controller.text;
    if (cachedText == text) return;
    cachedText = text;
    starts = [0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) starts.add(i + 1);
    }
  }

  void changed() {
    if (mounted) setState(updateLines);
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    focus.removeListener(changed);
    focus.dispose();
    scroll.dispose();

    super.dispose();
  }

  int get currentLine {
    final offset = widget.controller.selection.extentOffset.clamp(
      0,
      widget.controller.text.length,
    );
    var lo = 0, hi = starts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (starts[mid] <= offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return math.max(0, lo - 1);
  }

  Future<void> jump() async {
    final line = await showDialog<int>(
      context: context,
      builder: (_) => _LineDialog(max: starts.length),
    );
    if (line == null || !mounted) return;
    widget.controller.selection = TextSelection.collapsed(
      offset: starts[line - 1],
    );
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final actual = editable();
      if (actual == null) return;
      final y =
          actual
              .getLocalRectForCaret(TextPosition(offset: starts[line - 1]))
              .top +
          scroll.offset;
      scroll.jumpTo(
        y.clamp(
          scroll.position.minScrollExtent,
          scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final line = currentLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader)
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  '第 ${line + 1} / ${starts.length} 行',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                IconButton(
                  tooltip: '跳转到行',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 30,
                  ),
                  onPressed: jump,
                  icon: const Icon(Icons.format_list_numbered, size: 17),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focus.hasFocus ? colors.primary : colors.outlineVariant,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, bounds) {
                final gutter =
                    (starts.length.toString().length * scaler.scale(8) + 24)
                        .clamp(36.0, 90.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: gutter,
                      child: ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: ClipRect(
                          child: Semantics(
                            label: '行号，当前第 ${line + 1} 行，共 ${starts.length} 行',
                            child: CustomPaint(
                              key: gutterKey,
                              painter: LineNumberPainter(
                                gutter: gutterBox,
                                editable: editable,
                                starts: starts,
                                scroll: scroll,
                                currentLine: line,
                                color: colors.onSurfaceVariant,
                                active: colors.primary,
                                scaler: scaler,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        label: widget.label,
                        child: TextFormField(
                          key: fieldKey,
                          controller: widget.controller,
                          focusNode: focus,
                          enabled: widget.enabled,
                          autofocus: widget.autofocus,
                          scrollController: scroll,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          autocorrect: false,
                          enableSuggestions: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          textDirection: TextDirection.ltr,
                          style: style.copyWith(color: colors.onSurface),
                          strutStyle: strut,
                          validator: widget.validator,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          onTapOutside: (_) => focus.unfocus(),
                          decoration: InputDecoration(
                            hintText: widget.hint ?? widget.label,
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: colors.surfaceContainerLow,
                            isDense: true,
                            contentPadding: const EdgeInsets.all(12),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            errorMaxLines: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class LineNumberPainter extends CustomPainter {
  final RenderBox? Function() gutter;
  final RenderEditable? Function() editable;
  final List<int> starts;
  final ScrollController scroll;
  final int currentLine;
  final Color color, active;
  final TextScaler scaler;
  LineNumberPainter({
    required this.gutter,
    required this.editable,
    required this.starts,
    required this.scroll,
    required this.currentLine,
    required this.color,
    required this.active,
    required this.scaler,
  }) : super(repaint: scroll);
  double y(int line) {
    final actual = editable();
    if (actual != null && actual.hasSize) {
      return actual
              .getLocalRectForCaret(TextPosition(offset: starts[line]))
              .top +
          (scroll.hasClients ? scroll.offset : 0);
    }
    return 0;
  }

  double baseline(int line) {
    final actual = editable(), box = gutter();
    if (actual == null || box == null) return 0;
    final first = actual
        .getLocalRectForCaret(const TextPosition(offset: 0))
        .top;
    final caret = actual
        .getLocalRectForCaret(TextPosition(offset: starts[line]))
        .top;
    final baseline =
        actual.getDryBaseline(actual.constraints, TextBaseline.alphabetic)! +
        caret -
        first -
        (scroll.hasClients ? scroll.offset : 0);
    return box.globalToLocal(actual.localToGlobal(Offset(0, baseline))).dy;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (editable() == null || gutter() == null) return;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    var lo = 0, hi = starts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (y(mid) < offset - 32) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = math.max(0, lo - 1); i < starts.length; i++) {
      final top = baseline(i);
      if (top > size.height) break;
      if (top < -32) continue;
      final number = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
            color: i == currentLine ? active : color,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      number.paint(
        canvas,
        Offset(
          size.width - number.width - 10,
          top - number.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        ),
      );
      number.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant LineNumberPainter old) =>
      old.starts != starts ||
      old.currentLine != currentLine ||
      old.color != color ||
      old.active != active ||
      old.scaler != scaler;
}

class _LineDialog extends StatefulWidget {
  final int max;
  const _LineDialog({required this.max});
  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  final input = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, int.parse(input.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('跳转到行'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: input,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: '行号',
          hintText: '1–${widget.max}',
        ),
        validator: (v) {
          final value = int.tryParse(v ?? '');
          return value == null || value < 1 || value > widget.max
              ? '请输入 1–${widget.max} 的行号'
              : null;
        },
        onFieldSubmitted: (_) => submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: submit, child: const Text('跳转')),
    ],
  );
}
