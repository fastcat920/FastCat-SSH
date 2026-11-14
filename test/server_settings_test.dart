import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import 'category_management_test.dart' show CategoryStore;
import 'catalog_layout_drag_test.dart' show drag;

void main() {
  testWidgets('mobile settings and persistent group rename and reorder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = CategoryStore()
      ..data = AppData(
        groups: ['甲组', '乙组'],
        collapsedGroups: ['甲组'],
        hosts: [
          const Host(
            id: 'a',
            name: '主机',
            address: 'localhost',
            username: 'test',
            group: '甲组',
          ),
        ],
      );
    await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('备份与恢复'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('备份与恢复'), findsOneWidget);
    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('修改分组 甲组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新组');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(store.data.hosts.single.group, '新组');
    expect(store.data.collapsedGroups, ['新组']);
    await drag(
      tester,
      find.byKey(const ValueKey('server-group-新组')),
      find.byKey(const ValueKey('server-group-乙组')),
    );
    expect(store.data.copy().groups, ['乙组', '新组']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('desktop settings collapse', (tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Workspace(store: CategoryStore())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('备份与恢复'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('备份与恢复'), findsOneWidget);
  });
}
