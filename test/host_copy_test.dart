import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import 'category_management_test.dart' show CategoryStore;

class CopyStore extends CategoryStore {
  final savedCredentials = <String, String>{
    'source': jsonEncode({'password': 'fixture-password'}),
  };
  @override
  Future<String?> credential(String id) async => savedCredentials[id];
  @override
  Future<void> setCredential(String id, String value) async {
    savedCredentials[id] = value;
  }

  @override
  Future<void> deleteCredential(String id) async {
    savedCredentials.remove(id);
  }
}

void main() {
  testWidgets(
    'copy cancels without changes and saves independent host and savedCredentials',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CopyStore()
        ..data = AppData(
          hosts: [
            const Host(
              id: 'source',
              name: '原服务器',
              address: 'example.invalid',
              username: 'root',
              group: '生产',
              port: 2222,
              directory: '/srv',
              os: 'Windows',
            ),
          ],
        );
      await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
      await tester.pumpAndSettle();
      Future<void> copy() async {
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('复制'));
        await tester.pumpAndSettle();
      }

      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await copy();
      expect(find.text('复制服务器'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<String> &&
                    w.decoration.labelText == '分组',
              ),
            )
            .initialValue,
        '生产',
      );
      expect(tester.widget<TextField>(field('端口')).controller!.text, '2222');
      expect(
        tester.widget<TextField>(field('服务器密码')).controller!.text,
        'fixture-password',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.data.hosts, hasLength(1));
      expect(store.savedCredentials, hasLength(1));
      await copy();
      await tester.enterText(field('名称'), '新服务器');
      store.failSave = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.data.hosts, hasLength(1));
      expect(store.savedCredentials.keys, ['source']);
      store.failSave = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.data.hosts, hasLength(2));
      final copied = store.data.hosts.last;
      expect(copied.id, isNot('source'));
      expect(copied.name, '新服务器');
      expect(copied.group, '生产');
      expect(copied.os, 'Windows');
      expect(copied.directory, '/srv');
      expect(
        jsonDecode(store.savedCredentials[copied.id]!)['password'],
        'fixture-password',
      );
      expect(store.data.hosts.first.name, '原服务器');
      expect(tester.takeException(), isNull);
    },
  );
}
