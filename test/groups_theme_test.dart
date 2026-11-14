import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/ui/workspace.dart';
import 'package:fastcat_ssh/ui/syntax_controller.dart';
import 'package:fastcat_ssh/ui/code_theme.dart';

class GroupStore extends Store {
  final data = AppData(
    groups: ['生产', '空分组'],
    hosts: [
      const Host(
        id: 'a',
        name: '生产一号',
        address: 'localhost',
        username: 'root',
        group: '生产',
      ),
    ],
  );
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData value) async {}
  @override
  Future<String?> backgroundImage() async => null;
  @override
  Future<String?> credential(String id) async => null;
}

void main() {
  test(
    'old favorites merge globally and new empty groups and themes survive backup model',
    () {
      final json = AppData().toJson();
      json['favorites'] = {
        'a': ['/etc', '/var/log'],
        'b': ['/etc', 'C:/Users'],
      };
      json['groups'] = ['空分组'];
      json['themeColor'] = 'rose';
      json['codeTheme'] = 'dracula';
      json['collapsedGroups'] = ['空分组'];
      final restored = AppData.fromJson(json).copy();
      expect(restored.favorites, {
        'global': ['/etc', '/var/log', 'C:/Users'],
      });
      expect(restored.groups, contains('空分组'));
      expect(restored.collapsedGroups, ['空分组']);
      expect(restored.themeColor, 'rose');
      expect(restored.codeTheme, 'dracula');
      restored.merge(
        AppData(
          favorites: {
            'x': ['/etc', '/home'],
          },
          groups: ['其他'],
        ),
      );
      expect(restored.favorites['global'], [
        '/etc',
        '/var/log',
        'C:/Users',
        '/home',
      ]);
      expect(restored.groups, contains('其他'));
    },
  );
  testWidgets(
    'syntax spans preserve all source including quoted comments and composing',
    (tester) async {
      final text =
          'sudo yum install git\nport=14 # 注释\necho "# literal" \${name}';
      final controller = SyntaxController(text: text);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [CodePalette.named('classic', false)]),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(),
        withComposing: true,
      );
      expect(span.toPlainText(), text);
      final children = span.children!.cast<TextSpan>();
      expect(
        children.firstWhere((s) => s.text == 'sudo').style!.color,
        CodePalette.named('classic', false).keyword,
      );
      expect(
        children.firstWhere((s) => s.text == '14').style!.color,
        CodePalette.named('classic', false).number,
      );
      expect(
        children.firstWhere((s) => s.text == '"# literal"').style!.color,
        CodePalette.named('classic', false).string,
      );
      controller.value = TextEditingValue(
        text: '输入中',
        composing: const TextRange(start: 0, end: 3),
      );
      expect(
        controller
            .buildTextSpan(context: context, withComposing: true)
            .toPlainText(),
        '输入中',
      );
      controller.dispose();
    },
  );
  testWidgets(
    'sidebar supports empty groups, collapse and group-targeted host creation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = GroupStore();
      await tester.pumpWidget(MaterialApp(home: Workspace(store: store)));
      await tester.pumpAndSettle();
      expect(find.text('空分组'), findsOneWidget);
      await tester.tap(find.text('生产'));
      await tester.pumpAndSettle();
      expect(find.text('生产一号'), findsNothing);
      expect(store.data.collapsedGroups, contains('生产'));
      await tester.tap(find.byTooltip('展开 生产'));
      await tester.pumpAndSettle();
      expect(find.text('生产一号'), findsOneWidget);
      await tester.tap(find.byTooltip('添加服务器').at(1));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('空分组'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加分组'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '新组');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(store.data.groups, contains('新组'));
      expect(find.text('新组'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
