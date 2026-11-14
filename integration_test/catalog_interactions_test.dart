import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/ui/code_editor.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import '../test/category_management_test.dart' show CategoryStore;
import '../test/catalog_layout_drag_test.dart' show drag, item;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native folder wrapping long press sorting and top-aligned editor',
    (tester) async {
      final categories = List.generate(8, (i) => '分类 $i');
      final store = CategoryStore()
        ..data = AppData(
          categories: categories,
          snippets: [
            Snippet(
              id: 'a',
              name: '多行命令',
              category: categories.first,
              body:
                  'git clone -b custom --single-branch https://github.com/example/project.git .\nchmod +x init.sh update.sh\n./init.sh',
            ),
            Snippet(
              id: 'b',
              name: '另一个命令',
              body: 'echo two',
              category: categories.first,
            ),
          ],
        );
      await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('命令库'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(item(true, categories[4])).dy,
        greaterThan(tester.getTopLeft(item(true, categories[0])).dy),
      );
      await drag(tester, item(true, categories[0]), item(true, categories[2]));
      expect(store.data.categories.take(3), [
        categories[1],
        categories[2],
        categories[0],
      ]);
      await tester.ensureVisible(item(false, 'a'));
      await drag(tester, item(false, 'a'), item(false, 'b'));
      expect(store.data.snippets.map((s) => s.id), ['b', 'a']);
      await tester.tap(find.byTooltip('预览和编辑 多行命令'));
      await tester.pumpAndSettle();
      final editor = find.byWidgetPredicate(
        (w) => w is CodeEditor && w.label == '命令内容',
      );
      final editable = find.descendant(
        of: editor,
        matching: find.byType(EditableText),
      );
      final render = tester.state<EditableTextState>(editable).renderEditable;
      expect(
        render.localToGlobal(Offset.zero).dy - tester.getTopLeft(editor).dy,
        inInclusiveRange(6, 16),
      );
      final gutter = tester
          .widgetList<CustomPaint>(
            find.descendant(of: editor, matching: find.byType(CustomPaint)),
          )
          .map((w) => w.painter)
          .whereType<LineNumberPainter>()
          .single;
      expect(gutter.starts, hasLength(3));
      expect(gutter.baseline(1) - gutter.baseline(0), greaterThan(19.5));
      expect(store.data.copy().categories, store.data.categories);
      expect(find.text('请先连接服务器'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
