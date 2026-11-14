import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/backup.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'fixtures/backup_vectors.dart';

void main() {
  test(
    'legacy v1 remains readable and wrong password has localized error',
    () async {
      final payload = await BackupCodec().decode(
        base64Decode(dartBackupVector),
        'Compatibility-only_测试 🔐 123',
      );
      expect(payload.data.hosts.single.name, '跨端测试');
      await expectLater(
        BackupCodec().decode(base64Decode(dartBackupVector), 'wrong-password'),
        throwsA(isA<BackupAuthenticationException>()),
      );
    },
  );
  test(
    'new files include independent checksum; altered envelope fails before import',
    () async {
      final bytes = await BackupCodec().encode(AppData(), 'test-password-123');
      final j = jsonDecode(utf8.decode(bytes));
      expect((j['checksum'] as String).length, 64);
      final payload = await BackupCodec().decode(bytes, 'test-password-123');
      expect(payload.data.hosts, isEmpty);
      final data = base64Decode(j['ciphertext']);
      data[0] ^= 1;
      j['ciphertext'] = base64Encode(data);
      await expectLater(
        BackupCodec().decode(utf8.encode(jsonEncode(j)), 'test-password-123'),
        throwsA(isA<BackupIntegrityException>()),
      );
    },
  );
}
