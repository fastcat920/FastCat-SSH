import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fastcat_ssh/ui/backup_import_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fastcat_ssh/core/backup.dart';
import '../test/fixtures/backup_vectors.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'macOS Dart and independent Python v1 backups decrypt on native platform',
    (tester) async {
      for (final fixture in [dartBackupVector, pythonBackupVector]) {
        final payload = await compute(decodeBackupWorker, {
          'bytes': base64Decode(fixture),
          'password': 'Compatibility-only_测试 🔐 123',
        });
        expect(payload.data.hosts.single.name, '跨端测试');
        expect(payload.credentials['fixture-host'], 'synthetic-secret-only');
      }
    },
  );
  testWidgets('native exported encrypted fixture remains portable', (
    tester,
  ) async {
    final payload = await BackupCodec().decode(
      base64Decode(pythonBackupVector),
      'Compatibility-only_测试 🔐 123',
    );
    final bytes = await compute(encodeBackupWorker, {
      'data': payload.data.toJson(),
      'credentials': payload.credentials,
      'password': 'Compatibility-only_测试 🔐 123',
    });
    final file = File(
      '${Directory.systemTemp.path}/fastcat-compat-export.fastcatbackup',
    );
    await file.writeAsBytes(bytes);
    // Only a path to a synthetic fixture is reported. Never log passwords or payloads.
    debugPrint('SYNTHETIC_COMPAT_PATH=${file.path}');
  });
  testWidgets(
    'backup dialog keeps file and password editable after authentication failure',
    (tester) async {
      BackupPayload? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<BackupPayload>(
                    context: context,
                    builder: (_) => BackupImportDialog(
                      filename: 'synthetic-v1.fastcatbackup',
                      bytes: base64Decode(dartBackupVector),
                    ),
                  );
                },
                child: const Text('打开测试备份'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开测试备份'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong-password');
      await tester.tap(find.text('解密并预览'));
      for (var i = 0; i < 450 && find.text('重新解密').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('重新解密'), findsOneWidget);
      expect(find.textContaining('无法解密'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'wrong-password',
      );
      expect(find.textContaining('SecretBox'), findsNothing);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Compatibility-only_测试 🔐 123',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Compatibility-only_测试 🔐 123',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新解密'));
      await tester.pump();
      for (var i = 0; i < 450 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (result == null) {
        for (final widget in tester.widgetList<Text>(find.byType(Text))) {
          if (widget.data?.startsWith('无法') == true) {
            debugPrint('SYNTHETIC_RETRY_ERROR=${widget.data}');
          }
        }
      }
      expect(result?.data.hosts.single.name, '跨端测试');
    },
  );
}
