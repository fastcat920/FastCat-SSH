import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native secure storage and atomic metadata writes', (
    tester,
  ) async {
    final store = Store();
    await store.load();
    final temporary = await Directory.systemTemp.createTemp(
      'fastcat-native-qa-',
    );
    store.directory = temporary;
    final id = 'qa-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await store.setCredential(id, 'test-only-secret');
      expect(await store.credential(id), 'test-only-secret');
      await Future.wait([
        store.save(AppData()),
        store.save(
          AppData(
            hosts: [
              Host(
                id: id,
                name: 'test',
                address: 'localhost',
                username: 'test',
              ),
            ],
          ),
        ),
      ]);
      final json = await File(
        '${temporary.path}/workspace.json',
      ).readAsString();
      expect(json, contains(id));
      await store.deleteCredential(id);
      expect(await store.credential(id), isNull);
    } finally {
      await store.deleteCredential(id);
      await temporary.delete(recursive: true);
    }
  });
}
