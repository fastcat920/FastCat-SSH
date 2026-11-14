import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import 'category_management_test.dart' show CategoryStore;

Future<void> drag(WidgetTester tester, Finder source, Finder target) async {
  await tester.ensureVisible(source);
  final start = tester.getCenter(source), end = tester.getCenter(target);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 120));
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder item(bool folder, String id) =>
    find.byKey(ValueKey('catalog-${folder ? 'folder' : 'command'}-$id'));
void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'folders wrap and long press reorders folders and commands at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final categories = List.generate(9, (i) => '常用分类 $i');
        final store = CategoryStore()
          ..data = AppData(
            categories: categories,
            snippets: [
              for (var i = 0; i < 3; i++)
                Snippet(
                  id: '$i',
                  name: '命令 $i',
                  body: 'echo $i',
                  category: categories.first,
                ),
              Snippet(
                id: 'other',
                name: '其他命令',
                body: 'echo other',
                category: categories[1],
              ),
            ],
          );
        await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
        await tester.pumpAndSettle();
        if (width < 760) {
          await tester.tap(find.text('工具'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('命令库'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(item(true, categories[4])).dy,
          greaterThan(tester.getTopLeft(item(true, categories.first)).dy),
        );
        await drag(
          tester,
          item(true, categories[0]),
          item(true, categories[2]),
        );
        expect(store.data.categories.take(3), [
          categories[1],
          categories[2],
          categories[0],
        ]);
        expect(store.data.copy().categories, store.data.categories);
        await tester.ensureVisible(item(false, '0'));
        await drag(tester, item(false, '0'), item(false, '2'));
        expect(store.data.snippets.map((s) => s.id), ['1', '2', '0', 'other']);
        expect(find.text('请先连接服务器'), findsNothing);
        expect(find.byTooltip('分类菜单 ${categories[0]}'), findsOneWidget);
        store.failSave = true;
        await tester.ensureVisible(item(true, categories[1]));
        await drag(
          tester,
          item(true, categories[1]),
          item(true, categories[2]),
        );
        expect(store.data.categories.take(3), [
          categories[1],
          categories[2],
          categories[0],
        ]);
        expect(find.text('排序保存失败，原顺序已保留'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
