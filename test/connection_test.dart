import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/store.dart';
import 'package:fastcat_ssh/core/connection.dart';

class TestStore extends Store {
  final fingerprints = <String, String>{};
  @override
  Future<String?> credential(String id) async =>
      jsonEncode({'password': 'loopback-only-test'});
  @override
  Future<String?> fingerprint(String endpoint) async => fingerprints[endpoint];
  @override
  Future<void> trust(String endpoint, String value) async {
    fingerprints[endpoint] = value;
  }
}

void main() {
  test(
    'application session, trusted reconnect, jump and SOCKS lifecycle',
    () async {
      const direct = Host(
        id: 'a',
        name: 'Fixture',
        address: '127.0.0.1',
        port: 22345,
        username: 'fastcat-test',
      );
      const target = Host(
        id: 'b',
        name: 'Jump target',
        address: '127.0.0.1',
        port: 22345,
        username: 'fastcat-test',
        jumpId: 'a',
      );
      final data = AppData(hosts: [direct, target]), store = TestStore();
      final first = Connection(direct);
      addTearDown(first.dispose);
      var prompts = 0;
      await first.connect(store, data, (_, _, _) async {
        prompts++;
        return true;
      });
      expect(first.status, '已连接');
      expect(first.files.any((f) => f.filename == 'hello.txt'), true);
      expect(prompts, 1);
      first.send('hello\n');
      final port = await first.startTunnel();
      final socket = await Socket.connect('127.0.0.1', port);
      socket.add([5, 1, 0]);
      expect(await socket.first, [5, 0]);
      socket.destroy();
      final next = Connection(target);
      addTearDown(next.dispose);
      await next.connect(store, data, (_, _, _) async {
        fail('trusted endpoint should not ask again');
      });
      expect(next.status, '已连接');
      expect(next.files, isNotEmpty);
      next.close();
      first.close();
      expect(first.status, '已断开');
    },
    skip: const bool.fromEnvironment('SSH_INTEGRATION')
        ? false
        : 'Loopback fixture required',
  );
}
