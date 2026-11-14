import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import '../test/category_management_test.dart' show CategoryStore;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mobile category menu rename delete and command action layout', (
    tester,
  ) async {
    final store = CategoryStore();
    await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('命令库'));
    await tester.pumpAndSettle();
    Future<void> menu(String category, String action) async {
      final target = find.byTooltip('分类菜单 $category');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }

    await menu('默认分类', '编辑');
    await tester.enterText(field('编辑命令分类'), '常用命令');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(store.data.snippets.single.category, '常用命令');
    await tester.tap(find.byTooltip('预览和编辑 命令一'));
    await tester.pumpAndSettle();
    final delete = find.byTooltip('删除命令');
    final save = find.widgetWithText(TextButton, '保存');
    expect(tester.getCenter(save).dy, tester.getCenter(delete).dy);
    expect(tester.getCenter(save).dx, greaterThan(tester.getCenter(delete).dx));
    await menu('常用命令', '删除');
    expect(find.textContaining('1 条命令'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.data.snippets, hasLength(1));
    await menu('常用命令', '删除');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pumpAndSettle();
    expect(store.data.snippets, isEmpty);
    await menu('空分类', '删除');
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.data.copy().categories, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
