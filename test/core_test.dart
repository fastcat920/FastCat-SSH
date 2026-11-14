import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/backup.dart';

void main() {
  AppData fixture() => AppData(
    hosts: [
      const Host(
        id: 'a',
        name: 'Linux',
        address: '127.0.0.1',
        username: 'test',
      ),
      const Host(
        id: 'b',
        name: 'Windows',
        address: 'example.test',
        username: 'admin',
        os: 'Windows',
      ),
    ],
    snippets: [const Snippet(id: 's', name: '服务', body: r'echo ${name}')],
  );
  test('history is shared across servers, deduplicates and caps visits', () {
    final d = fixture();
    for (var i = 0; i < 110; i++) {
      d.visit('a', '/$i');
    }
    d.visit('a', '/109');
    d.visit('b', 'C:/');
    expect(d.history['global']!.length, 100);
    expect(d.history['global']!.first, 'C:/');
    expect(d.history.length, 1);
  });
  test('merge keeps local conflict, includes incoming unique items', () {
    final d = fixture(), other = fixture();
    other.hosts[0] = const Host(
      id: 'a',
      name: 'changed',
      address: 'host',
      username: 'root',
    );
    other.hosts.add(
      const Host(id: 'c', name: 'new', address: 'new', username: 'root'),
    );
    d.merge(other);
    expect(d.hosts.length, 3);
    expect(d.hosts.first.name, 'Linux');
  });
  test(
    'portable encrypted backup preserves data and optional credentials',
    () async {
      final codec = BackupCodec(), d = fixture();
      d.visit('b', 'C:/Users');
      final bytes = await codec.encode(
        d,
        'test-password-123',
        credentials: {'a': 'private-secret'},
      );
      expect(utf8.decode(bytes).contains('private-secret'), false);
      final p = await codec.decode(bytes, 'test-password-123');
      expect(p.data.toJson(), d.toJson());
      expect(p.credentials['a'], 'private-secret');
      final second = await codec.encode(d, 'test-password-123');
      expect(second, isNot(bytes));
      expect(
        (await codec.decode(second, 'test-password-123')).credentials,
        isEmpty,
      );
    },
  );
  test('wrong password and tampered ciphertext rejected', () async {
    final c = BackupCodec();
    final bytes = await c.encode(fixture(), 'test-password-123');
    await expectLater(c.decode(bytes, 'incorrect-password'), throwsA(anything));
    final j = jsonDecode(utf8.decode(bytes));
    final cipher = base64Decode(j['ciphertext']);
    cipher[0] ^= 1;
    j['ciphertext'] = base64Encode(cipher);
    await expectLater(
      c.decode(utf8.encode(jsonEncode(j)), 'test-password-123'),
      throwsA(anything),
    );
  });
  test('future versions and malformed hosts rejected', () {
    expect(() => AppData.fromJson({'schema': 2}), throwsFormatException);
    expect(
      () => Host.fromJson({
        'id': 'a',
        'name': 'a',
        'address': '',
        'username': 'a',
        'port': 0,
      }),
      throwsFormatException,
    );
  });
}
