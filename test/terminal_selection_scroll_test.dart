import 'package:fastcat_ssh/ui/terminal_selection_scroll.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      '$kind selection scrolls both ways, extends and stops on release',
      (tester) async {
        final terminal = Terminal(maxLines: 1000);
        for (var i = 0; i < 200; i++) {
          terminal.write('line $i some text\r\n');
        }
        final controller = TerminalController();
        late ScrollController scroll;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 500,
                height: 240,
                child: TerminalSelectionScroll(
                  terminal: terminal,
                  controller: controller,
                  builder: (key, value) {
                    scroll = value;
                    return TerminalView(
                      terminal,
                      key: key,
                      controller: controller,
                      scrollController: value,
                      hardwareKeyboardOnly: true,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        scroll.jumpTo(scroll.position.maxScrollExtent / 2);
        await tester.pump();
        final rect = tester.getRect(find.byType(TerminalView));
        final gesture = await tester.startGesture(
          Offset(rect.left + 30, rect.center.dy),
          kind: kind,
        );
        if (kind == PointerDeviceKind.touch) {
          await tester.pump(const Duration(milliseconds: 600));
        }
        await gesture.moveTo(Offset(rect.left + 90, rect.center.dy + 10));
        await tester.pump();
        expect(controller.selection, isNotNull);
        final before = scroll.offset;
        final base = controller.selection!.begin;
        await gesture.moveTo(Offset(rect.center.dx, rect.bottom - 2));
        await tester.pump(const Duration(milliseconds: 400));
        expect(scroll.offset, greaterThan(before));
        expect(controller.selection!.begin, base);
        final lower = scroll.offset;
        await gesture.moveTo(Offset(rect.center.dx, rect.top + 2));
        await tester.pump(const Duration(milliseconds: 600));
        expect(scroll.offset, lessThan(lower));
        await gesture.up();
        final stopped = scroll.offset;
        await tester.pump(const Duration(milliseconds: 400));
        expect(scroll.offset, stopped);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
