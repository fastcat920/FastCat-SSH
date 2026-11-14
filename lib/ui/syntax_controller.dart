import 'package:flutter/material.dart';
import 'code_theme.dart';

/// Lightweight lexical colouring only; never rewrites source or selection.
/// Active IME composition is delegated to Flutter's own text-span builder.
class SyntaxController extends TextEditingController {
  SyntaxController({super.text});
  static final tokens = RegExp(
    r'''(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?<comment>\#[^\r\n]*)|(?<variable>\$\{[^}\r\n]*\}|\$[\w:]+|\b[A-Za-z_][\w.-]*(?=\s*=))|(?<number>\b\d+(?:\.\d+)?\b)|(?<keyword>\b(?:sudo|apt|apt-get|yum|dnf|install|git|systemctl|service|echo|cd|ls|cat|grep|if|then|else|fi|for|do|done|function|return|true|false|null|Get-Service|Set-Content|Write-Host|Restart-Service)\b)|(?<flag>--?[A-Za-z][\w-]*)''',
    multiLine: true,
  );
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final palette =
        Theme.of(context).extension<CodePalette>() ??
        CodePalette.named(
          'classic',
          Theme.of(context).brightness == Brightness.dark,
        );
    // Bound work during large-file editing rather than scanning megabytes on every keystroke.
    if (text.length > 200000) {
      return TextSpan(
        style: style?.copyWith(color: palette.foreground),
        text: text,
      );
    }
    final spans = <InlineSpan>[];
    var position = 0;
    for (final match in tokens.allMatches(text)) {
      if (match.start > position) {
        spans.add(TextSpan(text: text.substring(position, match.start)));
      }
      final color = match.namedGroup('string') != null
          ? palette.string
          : match.namedGroup('comment') != null
          ? palette.comment
          : match.namedGroup('number') != null
          ? palette.number
          : match.namedGroup('variable') != null
          ? palette.variable
          : palette.keyword;
      spans.add(
        TextSpan(
          text: match[0],
          style: TextStyle(color: color),
        ),
      );
      position = match.end;
    }
    if (position < text.length) {
      spans.add(TextSpan(text: text.substring(position)));
    }
    return TextSpan(
      style: (style ?? const TextStyle()).copyWith(color: palette.foreground),
      children: spans,
    );
  }
}
