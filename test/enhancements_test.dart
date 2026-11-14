import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import 'package:fastcat_ssh/ui/password_field.dart';

class FixtureStore extends Store {
  AppData data = AppData(
    categories: ['默认分类', '维护'],
    snippets: [
      const Snippet(
        id: 's',
        name: '更新服务',
        body: 'echo update',
        category: '维护',
        directSend: true,
      ),
    ],
  );
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData data) async {
    this.data = data;
  }

  @override
  Future<String?> backgroundImage() async => null;
}

void main() {
  test(
    'old backup commands migrate with default category and safe send mode',
    () {
      final old = {
        'schema': 1,
        'hosts': [],
        'snippets': [
          {'id': 's', 'name': 'old', 'body': 'echo ok', 'os': '通用'},
        ],
      };
      final data = AppData.fromJson(old);
      expect(data.snippets.single.category, '默认分类');
      expect(data.snippets.single.directSend, false);
      expect(data.themeMode, 'system');
    },
  );
  test('appearance, categories and send mode survive serialization', () {
    final data = FixtureStore().data;
    data.themeMode = 'light';
    data.terminalColor = 'amber';
    final restored = data.copy();
    expect(restored.categories, contains('维护'));
    expect(restored.snippets.single.directSend, true);
    expect(restored.themeMode, 'light');
    expect(restored.terminalColor, 'amber');
    final j = data.toJson();
    j['categories'] = [];
    j['terminalColor'] = 'invalid';
    expect(AppData.fromJson(j).categories, isNotEmpty);
    expect(AppData.fromJson(j).terminalColor, 'default');
  });
  testWidgets('password visibility toggles without changing content', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'test-only-password');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordField(controller: controller, label: '密码'),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, false);
    expect(controller.text, 'test-only-password');
    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
  });
  testWidgets('categories, command preview and editor roundtrip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FixtureStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Workspace(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('命令库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '维护'));
    await tester.pumpAndSettle();
    expect(find.text('更新服务'), findsOneWidget);
    await tester.tap(find.byTooltip('预览和编辑 更新服务'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'echo update'))
          .controller!
          .text,
      'echo update',
    );
    expect(find.widgetWithText(TextField, '更新服务'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
    await tester.enterText(find.widgetWithText(TextField, '更新服务'), '新版服务');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.data.snippets.single.name, '新版服务');
    expect(store.data.snippets.length, 1);
    expect(store.data.snippets.single.appendNewline, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('appearance menu selects light dark and system', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FixtureStore();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(
          store: store,
          onAppearanceChanged: (data) => selected = data.themeMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与终端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浅色').last);
    await tester.pumpAndSettle();
    expect(selected, 'light');
    expect(store.data.themeMode, 'light');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compact desktop preserves editor space with terminal-first layout',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FixtureStore();
      store.data.terminalRatio = .85;
      await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      expect(find.text('发送全部窗口'), findsOneWidget);
    },
  );
}
