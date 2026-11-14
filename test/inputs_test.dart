import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/ui/input_dialog.dart';
import 'package:fastcat_ssh/ui/host_editor.dart';
import 'package:fastcat_ssh/ui/app_input.dart';

void main() {
  testWidgets(
    'single-line validation keeps invalid draft and Enter submits valid value',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: c,
                    builder: (_) => const InputDialog(title: '分类'),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('请输入内容'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '维护');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, '维护');
    },
  );
  testWidgets(
    'technical fields disable smart input and clear notifies filter',
    (tester) async {
      final controller = TextEditingController(text: '/var/log');
      String? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppInput(
              controller: controller,
              label: '目录',
              code: true,
              onChanged: (v) => changed = v,
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, false);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
      await tester.tap(find.byTooltip('清空目录'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changed, '');
    },
  );
  testWidgets(
    'host form validates fields and preserves passwords after save failure',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var attempts = 0;
      String? password;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HostEditor(
              hosts: const [],
              auth: const {},
              onSave: (h, auth) async {
                attempts++;
                password = auth['password'];
                throw StateError('test failure');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('此项不能为空'), findsOneWidget);
      expect(find.text('请输入服务器地址'), findsOneWidget);
      expect(attempts, 0);
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.enterText(field('名称'), 'Test');
      await tester.enterText(field('地址'), 'server.test');
      await tester.enterText(field('端口'), '70000');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('范围 1–65535'), findsOneWidget);
      expect(attempts, 0);
      await tester.enterText(field('端口'), '22');
      await tester.enterText(field('服务器密码'), ' secret with spaces ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(password, ' secret with spaces ');
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(tester.widget<TextField>(field('名称')).controller!.text, 'Test');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long multiline input remains editable with phone keyboard inset',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputDialog(
              title: '编辑文件',
              initial: List.filled(100, 'line').join('\n'),
              multiline: true,
              code: true,
              allowEmpty: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, isNull);
    },
  );
}
