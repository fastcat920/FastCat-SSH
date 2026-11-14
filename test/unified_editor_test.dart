import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/app_theme.dart';
import 'package:fastcat_ssh/ui/code_editor.dart';
import 'package:fastcat_ssh/ui/code_theme.dart';
import 'package:fastcat_ssh/ui/syntax_controller.dart';
import 'package:fastcat_ssh/ui/workspace.dart';

class ComposerStore extends Store {
  AppData data = AppData(
    snippets: [
      const Snippet(
        id: 'saved',
        name: '示例命令',
        body: 'echo saved',
        appendNewline: true,
      ),
    ],
  );
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData next) async {
    data = next;
  }

  @override
  Future<String?> backgroundImage() async => null;
}

Finder input(String label) => ['命令内容', '文件内容'].contains(label)
    ? find.descendant(
        of: find.byWidgetPredicate((w) => w is CodeEditor && w.label == label),
        matching: find.byType(TextField),
      )
    : find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
void main() {
  test(
    'all themed surfaces and default syntax background follow accent in both modes',
    () {
      for (final brightness in Brightness.values) {
        final mint = buildAppTheme('mint', brightness),
            purple = buildAppTheme('purple', brightness);
        expect(
          mint.scaffoldBackgroundColor,
          isNot(purple.scaffoldBackgroundColor),
        );
        expect(
          mint.inputDecorationTheme.fillColor,
          isNot(purple.inputDecorationTheme.fillColor),
        );
        expect(
          purple.extension<CodePalette>()!.background,
          purple.colorScheme.surfaceContainerLow,
        );
        expect(
          mint.extension<CodePalette>()!.keyword,
          purple.extension<CodePalette>()!.keyword,
        );
      }
      final data = AppData(showTerminalInfo: false);
      expect(data.copy().showTerminalInfo, false);
    },
  );
  testWidgets(
    'file line numbers account for wrapping, CRLF and jump to logical line',
    (tester) async {
      final text = '${List.filled(100, 'x').join()}\nsecond\r\nthird';
      final controller = SyntaxController(text: text);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme('blue', Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                height: 180,
                child: CodeEditor(controller: controller, label: '文件内容'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gutter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LineNumberPainter>()
          .single;
      expect(gutter.starts, [0, 101, 109]);
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final first = render.getLocalRectForCaret(const TextPosition(offset: 0)),
          second = render.getLocalRectForCaret(const TextPosition(offset: 101));
      expect(second.top - first.top, closeTo(gutter.y(1) - gutter.y(0), 1));
      expect(gutter.y(1), greaterThan(19.5));
      await tester.tap(find.byTooltip('跳转到行'));
      await tester.pumpAndSettle();
      await tester.enterText(input('行号'), '3');
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(controller.selection.extentOffset, 109);
      expect(controller.text, text);
      expect(find.text('第 3 / 3 行'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'desktop uses inline editor on right and preserves unsaved draft on preview selection',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ComposerStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme('purple', Brightness.light),
          home: Workspace(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      expect(find.text('自定义命令'), findsNothing);
      expect(
        tester.getTopLeft(input('命令名称')).dx,
        greaterThan(tester.getTopLeft(find.text('新建命令')).dx),
      );
      await tester.enterText(input('命令内容'), 'unsaved');
      await tester.tap(find.byTooltip('预览和编辑 示例命令'));
      await tester.pumpAndSettle();
      expect(find.text('替换未保存的命令'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('命令内容')).controller!.text,
        'unsaved',
      );
      await tester.tap(find.byTooltip('预览和编辑 示例命令'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester.widget<TextField>(input('命令内容')).controller!.text,
        'echo saved',
      );
      await tester.enterText(input('命令名称'), '已更新');
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.data.snippets.single.name, '已更新');
      expect(store.data.snippets.single.appendNewline, false);
      expect(find.textContaining('选中后发送时补上回车'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mobile composer stays below library and obsolete appearance controls are absent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ComposerStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme('rose', Brightness.dark),
          home: Workspace(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(input('命令名称')).dy,
        greaterThan(tester.getTopLeft(find.text('新建命令')).dy),
      );
      await tester.tap(find.text('新建命令'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(input('命令内容'), 'echo test');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pumpAndSettle();
      expect(find.text('请先连接服务器'), findsOneWidget);
      expect(input('命令内容'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('服务器'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观与终端'));
      await tester.pumpAndSettle();
      expect(find.text('编辑器与终端配色'), findsNothing);
      expect(find.textContaining('终端字体强调色'), findsNothing);
      expect(find.text('应用主题色'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == '应用主题色',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('紫色').last);
      await tester.pumpAndSettle();
      final dialogTheme = Theme.of(tester.element(find.text('终端背景图片')));
      expect(
        dialogTheme.inputDecorationTheme.fillColor,
        buildAppTheme(
          'purple',
          Brightness.light,
        ).inputDecorationTheme.fillColor,
      );
      expect(store.data.themeColor, 'purple');
    },
  );
  testWidgets(
    'send button and catalog clicks explain missing connection inline',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme('mint', Brightness.light),
          home: Workspace(store: ComposerStore()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      await tester.enterText(input('命令内容'), 'echo test');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pumpAndSettle();
      expect(find.text('请先连接服务器'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '示例命令'));
      await tester.pumpAndSettle();
      expect(find.text('请先连接服务器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('terminal info toggle persists visibility preference', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = ComposerStore();
    await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('隐藏终端信息'));
    await tester.pumpAndSettle();
    expect(store.data.showTerminalInfo, false);
    expect(find.byTooltip('显示终端信息'), findsOneWidget);
  });
}
