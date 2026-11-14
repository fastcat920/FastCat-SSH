import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/xterm.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/workspace.dart';

class UiFixtureStore extends Store {
  final fingerprints = <String, String>{};
  @override
  Future<AppData> load() async => AppData(
    hosts: [
      for (final id in ['One', 'Two'])
        Host(
          id: id,
          name: 'QA $id',
          address: '127.0.0.1',
          port: 22345,
          username: 'fastcat-test',
        ),
    ],
  );
  @override
  Future<void> save(AppData data) async {}
  @override
  Future<String?> backgroundImage() async => null;
  @override
  Future<String?> credential(String id) async =>
      jsonEncode({'password': 'loopback-only-test'});
  @override
  Future<String?> fingerprint(String endpoint) async => fingerprints[endpoint];
  @override
  Future<void> trust(String endpoint, String value) async {
    fingerprints[endpoint] = value;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two-session broadcast confirms targets; clipboard paste and copy work',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Workspace(store: UiFixtureStore()),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Timed out waiting for $finder');
      }

      await tester.tap(find.text('QA One'));
      await waitFor(find.text('信任并连接'));
      await tester.tap(find.text('信任并连接'));
      await waitFor(find.text('已连接'));
      if (find.text('QA Two').evaluate().isEmpty) {
        await tester.tap(find.text('服务器'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('QA Two'));
      await waitFor(find.text('已连接'));
      // Wait for the second session shell to finish setup.
      await tester.pump(const Duration(seconds: 1));
      if (find.text('命令库').evaluate().isEmpty) {
        await tester.tap(find.text('工具'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      final fields = find.byType(
        TextField,
      ); // server search, command name, command body
      await tester.enterText(fields.last, 'broadcast-test');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送全部窗口'));
      await tester.pumpAndSettle();
      expect(find.text('发送到全部窗口（2）'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('QA One、QA Two'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '发送'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(TerminalView).evaluate().isEmpty) {
        await tester.tap(find.text('终端'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('切换双会话分屏'));
      await tester.pumpAndSettle();
      final terminals = tester
          .widgetList<TerminalView>(find.byType(TerminalView))
          .toList();
      expect(terminals.length, 2);
      for (final terminal in terminals) {
        expect(terminal.terminal.buffer.getText(), contains('broadcast-test'));
      }
      await Clipboard.setData(const ClipboardData(text: 'clipboard-test\n'));
      await tester.tap(find.byTooltip('粘贴到终端'));
      await tester.pumpAndSettle();
      expect(find.text('粘贴到 QA Two'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '粘贴'));
      await tester.pumpAndSettle();
      // Copy a known range from the active terminal using the same toolbar action.
      final terminal = terminals.first.terminal,
          controller = terminals.first.controller!;
      terminal.write('\r\nCOPY-ME');
      final row = 0;
      controller.setSelection(
        terminal.buffer.createAnchor(0, row),
        terminal.buffer.createAnchor(7, row),
      );
      final expected = terminal.buffer.getText(controller.selection!);
      expect(expected, isNotEmpty);
      await tester.tap(find.byTooltip('复制终端选中内容'));
      await tester.pumpAndSettle();
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, expected);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
