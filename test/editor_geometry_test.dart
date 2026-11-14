import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/ui/app_theme.dart';
import 'package:fastcat_ssh/ui/code_editor.dart';
import 'package:fastcat_ssh/ui/syntax_controller.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'editor starts at top and gutter baselines match on $platform scale $scale',
        (tester) async {
          final source =
              'git clone -b custom --single-branch https://github.com/example/project.git .\nchmod +x init.sh update.sh\n./init.sh\n${List.generate(35, (i) => 'echo line $i').join('\n')}';
          final controller = SyntaxController(text: source);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme('purple', Brightness.dark),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 300,
                      height: 260,
                      child: CodeEditor(
                        controller: controller,
                        label: '命令内容',
                        showHeader: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final render = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final origin = render.localToGlobal(Offset.zero);
          final editorTop = tester.getTopLeft(find.byType(CodeEditor)).dy;
          expect(origin.dy - editorTop, inInclusiveRange(6, 16));
          LineNumberPainter gutter() => tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<LineNumberPainter>()
              .single;
          void aligned() {
            final painter = gutter();
            final firstCaret = render
                .getLocalRectForCaret(const TextPosition(offset: 0))
                .top;
            for (final i in [0, 1, 2, 20]) {
              final box = painter.gutter()!;
              final expected =
                  origin.dy +
                  render.getDryBaseline(
                    render.constraints,
                    TextBaseline.alphabetic,
                  )! +
                  render
                      .getLocalRectForCaret(
                        TextPosition(offset: painter.starts[i]),
                      )
                      .top -
                  firstCaret -
                  painter.scroll.offset;
              final actual = box
                  .localToGlobal(Offset(0, painter.baseline(i)))
                  .dy;
              expect(actual, closeTo(expected, .1));
            }
          }

          aligned();
          gutter().scroll.jumpTo(200);
          await tester.pump();
          aligned();
          expect(controller.text, source);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
