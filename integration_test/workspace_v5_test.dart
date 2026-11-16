import 'package:fastcat_ssh/ui/code_editor.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/xterm.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/workspace.dart';

class FixtureStore extends Store {
  AppData data = AppData(
    hosts: [
      const Host(
        id: 'qa',
        name: 'QA server',
        address: '127.0.0.1',
        port: 22345,
        username: 'fastcat-test',
      ),
    ],
  );
  final fingerprints = <String, String>{};
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData value) async {
    data = value;
  }

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
    'hardware, directory panes, command preview, no-enter sending and raw custom command',
    (tester) async {
      final store = FixtureStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Workspace(store: store),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Timed out: $finder');
      }

      expect(find.text('（1）'), findsOneWidget);
      await tester.tap(find.text('QA server'));
      await waitFor(find.text('信任并连接'));
      await tester.tap(find.text('信任并连接'));
      await waitFor(find.text('已连接'));
      await waitFor(find.textContaining('CPU 4核'));
      expect(find.byTooltip('硬件与网络详情'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byTooltip('硬件与网络详情')).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(TerminalView)).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.widgetWithText(TextButton, 'QA server')).dy,
        greaterThan(tester.getTopLeft(find.byTooltip('隐藏终端信息')).dy),
      );
      await tester.tap(find.byTooltip('隐藏终端信息'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('硬件与网络详情'), findsNothing);
      await tester.tap(find.byTooltip('显示终端信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      await waitFor(find.text('logs'));
      expect(
        tester.getTopLeft(find.byTooltip('上一级')).dy,
        tester.getTopLeft(find.byTooltip('刷新目录')).dy,
      );
      expect(
        tester.getTopLeft(find.byTooltip('上一级')).dx,
        lessThan(tester.getTopLeft(find.byTooltip('刷新目录')).dx),
      );
      expect(find.text('目录'), findsOneWidget);
      expect(find.text('hello.txt'), findsOneWidget);
      await tester.tap(find.text('logs').first);
      await waitFor(find.text('example.log'));
      expect(find.text('archive'), findsWidgets);
      for (final column in ['文件名', '大小', '类型', '修改时间', '权限']) {
        expect(find.text(column), findsOneWidget);
      }
      expect(find.text('hello.txt'), findsNothing);
      await tester.tap(find.text('example.log'));
      await waitFor(find.byTooltip('跳转到行'));
      final fileField = find.descendant(
        of: find.byWidgetPredicate((w) => w is CodeEditor && w.label == '文件内容'),
        matching: find.byType(TextField),
      );
      await tester.enterText(fileField, 'one\ntwo\nthree');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('跳转到行'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '行号',
        ),
        '3',
      );
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(find.text('第 3 / 3 行'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建命令'));
      await tester.pumpAndSettle();
      Finder field(String label) => label == '命令内容'
          ? find.descendant(
              of: find.byWidgetPredicate(
                (w) => w is CodeEditor && w.label == label,
              ),
              matching: find.byType(TextField),
            )
          : find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == label,
            );

      await tester.enterText(field('命令名称'), 'Deferred');
      await tester.enterText(field('命令内容'), 'no-enter-marker');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.data.snippets.single.appendNewline, false);
      expect(tester.widget<TextField>(field('命令名称')).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field('命令内容')).controller!.text, isEmpty);
      await tester.tap(find.byTooltip('预览和编辑 Deferred'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('发送全部窗口'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消'),
        ),
      );
      await tester.pumpAndSettle();
      expect(field('命令内容'), findsOneWidget);
      expect(find.byType(TerminalView), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Deferred'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TerminalView), findsOneWidget);
      await tester.pumpAndSettle();
      var terminal = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal;
      expect(
        terminal.buffer.getText(),
        isNot(contains('echo: no-enter-marker')),
      );
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建命令'));
      await tester.pumpAndSettle();
      await tester.enterText(field('命令内容'), 'flush-marker');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TerminalView), findsOneWidget);
      await tester.pumpAndSettle();
      terminal = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal;
      expect(
        terminal.buffer.getText(),
        contains('no-enter-markerflush-marker'),
      );
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      await tester.enterText(field('命令内容'), r'echo ${HOME}');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TerminalView), findsOneWidget);
      await tester.pumpAndSettle();
      expect(terminal.buffer.getText(), contains(r'echo ${HOME}'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
