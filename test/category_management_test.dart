import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/workspace.dart';

class CategoryStore extends Store {
  AppData data = AppData(
    categories: ['默认分类', '空分类'],
    snippets: [
      const Snippet(
        id: 'one',
        name: '命令一',
        body: 'echo one',
        os: 'Linux',
        appendNewline: false,
      ),
    ],
  );
  bool failSave = false;
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData next) async {
    if (failSave) throw StateError('fixture save failure');
    data = next;
  }

  @override
  Future<String?> backgroundImage() async => null;
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> open(WidgetTester tester, CategoryStore store) async {
  tester.view.physicalSize = const Size(1280, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('命令库'));
  await tester.pumpAndSettle();
}

Future<void> menu(WidgetTester tester, String category, String action) async {
  await tester.ensureVisible(find.byTooltip('分类菜单 $category'));
  await tester.tap(find.byTooltip('分类菜单 $category'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'explicit empty and renamed categories survive serialization; legacy commands retain defaults',
    () {
      expect(AppData(categories: []).copy().categories, isEmpty);
      expect(AppData(categories: ['改名']).copy().categories, ['改名']);
      final legacy = AppData().toJson()..remove('categories');
      expect(AppData.fromJson(legacy).categories, ['默认分类']);
    },
  );
  testWidgets(
    'rename moves all commands, preserves settings and unsaved edits, validates duplicate names',
    (tester) async {
      final store = CategoryStore();
      await open(tester, store);
      await tester.tap(find.byTooltip('预览和编辑 命令一'));
      await tester.pumpAndSettle();
      await tester.enterText(field('命令内容'), 'echo unsaved');
      await menu(tester, '默认分类', '编辑');
      await tester.enterText(field('编辑命令分类'), '空分类');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('此分类已存在'), findsOneWidget);
      await tester.enterText(field('编辑命令分类'), '生产命令');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(store.data.categories, ['生产命令', '空分类']);
      expect(store.data.copy().categories, ['生产命令', '空分类']);
      expect(store.data.snippets.single.category, '生产命令');
      expect(store.data.snippets.single.appendNewline, false);
      expect(store.data.snippets.single.os, 'Linux');
      expect(
        tester.widget<TextField>(field('命令内容')).controller!.text,
        'echo unsaved',
      );
      final save = find.widgetWithText(TextButton, '保存'),
          delete = find.byTooltip('删除命令');
      expect(tester.getCenter(save).dy, tester.getCenter(delete).dy);
      expect(
        tester.getCenter(save).dx,
        greaterThan(tester.getCenter(delete).dx),
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: delete, matching: find.byType(Icon)),
      );
      expect(icon.color, Theme.of(tester.element(delete)).colorScheme.error);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'populated folder confirms deletion; empty and last folders delete immediately and stay deleted',
    (tester) async {
      final store = CategoryStore();
      await open(tester, store);
      await menu(tester, '默认分类', '删除');
      expect(find.textContaining('1 条命令'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.data.snippets, hasLength(1));
      await menu(tester, '默认分类', '删除');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.data.snippets, isEmpty);
      expect(store.data.categories, ['空分类']);
      await menu(tester, '空分类', '删除');
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.data.copy().categories, isEmpty);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请先新建命令分类'), findsOneWidget);
      await tester.ensureVisible(find.text('新建分类'));
      await tester.tap(find.text('新建分类'));
      await tester.pumpAndSettle();
      await tester.enterText(field('新建命令分类'), '恢复分类');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(store.data.categories, ['恢复分类']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed category save leaves original folder and commands unchanged',
    (tester) async {
      final store = CategoryStore()..failSave = true;
      await open(tester, store);
      await menu(tester, '空分类', '删除');
      expect(store.data.categories, ['默认分类', '空分类']);
      expect(find.byTooltip('分类菜单 空分类'), findsOneWidget);
      expect(find.text('分类修改失败，原数据已保留'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
