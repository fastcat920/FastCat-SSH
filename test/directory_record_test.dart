import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import 'category_management_test.dart' show CategoryStore;

void main() {
  testWidgets(
    'history deletes immediately; favorites confirm and cancel independently',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CategoryStore()
        ..data = AppData(
          history: {
            'global': ['/one', '/two'],
          },
          favorites: {
            'global': ['/one', '/two'],
          },
        );
      await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('目录历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除历史 /one'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.data.history['global'], ['/two']);
      expect(store.data.favorites['global'], ['/one', '/two']);
      await tester.tap(find.byTooltip('收藏目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除收藏 /one'));
      await tester.pumpAndSettle();
      expect(find.text('删除收藏目录'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.data.favorites['global'], ['/one', '/two']);
      await tester.tap(find.byTooltip('收藏目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除收藏 /one'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(store.data.copy().favorites['global'], ['/two']);
      expect(store.data.history['global'], ['/two']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed removal retains the record', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = CategoryStore()
      ..data = AppData(
        history: {
          'global': ['/keep'],
        },
      )
      ..failSave = true;
    await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('目录历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除历史 /keep'));
    await tester.pumpAndSettle();
    expect(store.data.history['global'], ['/keep']);
    expect(tester.takeException(), isNull);
  });
}
