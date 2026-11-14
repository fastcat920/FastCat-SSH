import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/workspace.dart';

class MemoryStore extends Store {
  final data = AppData(
    hosts: [
      const Host(
        id: 'a',
        name: 'Linux Test',
        address: '127.0.0.1',
        username: 'test',
      ),
    ],
  );
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData value) async {}
  @override
  Future<String?> credential(String id) async => null;
  @override
  Future<void> setCredential(String id, String value) async {}
}

void main() {
  testWidgets('desktop workspace and add-host form fit screen', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Workspace(store: MemoryStore()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Linux Test'), findsOneWidget);
    expect(find.text('文件目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('添加服务器'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  testWidgets('phone navigates server, terminal and tools without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Workspace(store: MemoryStore()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('终端'));
    await tester.pumpAndSettle();
    expect(find.text('你的服务器工作区'), findsOneWidget);
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('目录历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('命令库'));
    await tester.pumpAndSettle();
    expect(find.text('发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
