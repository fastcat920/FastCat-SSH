import 'package:fastcat_ssh/ui/terminal_mobile_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('two rows fit phone and send terminal control sequences', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalMobileKeys(onSend: sent.add)),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Esc')).dy,
      closeTo(tester.getTopLeft(find.text('回车')).dy, 1),
    );
    expect(
      tester.getTopLeft(find.text('Home')).dy,
      greaterThan(tester.getTopLeft(find.text('Esc')).dy),
    );
    for (final name in ['回车', 'Ctrl+Z', '退格', '↑', 'Home']) {
      await tester.tap(find.text(name));
    }
    expect(sent, ['\r', '\x1a', '\x7f', '\x1b[A', '\x1b[H']);
    tester.testTextInput.log.clear();
    await tester.tap(find.byTooltip('收起键盘'));
    expect(
      tester.testTextInput.log.any((call) => call.method == 'TextInput.hide'),
      isTrue,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TerminalMobileKeys(onSend: null))),
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '回车'))
          .onPressed,
      isNull,
    );
  });
}
