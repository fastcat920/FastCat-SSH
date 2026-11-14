import 'dart:async';
import 'dart:convert';
import 'package:fastcat_ssh/core/transfer.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';

void main() {
  test(
    'loopback SSH authentication, command, SFTP CRUD and jump transport',
    () async {
      var verified = false;
      final client = SSHClient(
        await SSHSocket.connect('127.0.0.1', 22345),
        username: 'fastcat-test',
        onPasswordRequest: () => 'loopback-only-test',
        onVerifyHostKey: (type, fp) {
          verified = true;
          return fp.isNotEmpty;
        },
      );
      addTearDown(client.close);
      await client.authenticated;
      expect(verified, true);
      expect(
        utf8.decode(await client.run('uname -a')),
        contains('FastCat fixture'),
      );
      final sftp = await client.sftp();
      expect(
        (await sftp.listdir('.')).any((e) => e.filename == 'hello.txt'),
        true,
      );
      final upload = UploadTask();
      var progress = 0;
      await upload.upload(
        sftp,
        'uploaded.txt',
        Stream.value(Uint8List.fromList(utf8.encode('streamed'))),
        (n) => progress = n,
      );
      expect(progress, 8);
      final uploaded = await sftp.open('uploaded.txt');
      expect(utf8.decode(await uploaded.readBytes()), 'streamed');
      await uploaded.close();
      final cancelled = UploadTask();
      await cancelled.cancel();
      await expectLater(
        cancelled.upload(
          sftp,
          'uploaded.txt',
          Stream.value(Uint8List.fromList([0])),
          (_) => {},
        ),
        throwsStateError,
      );
      final original = await sftp.open('uploaded.txt');
      expect(utf8.decode(await original.readBytes()), 'streamed');
      await original.close();
      expect(
        (await sftp.listdir('.')).any((f) => f.filename.endsWith('.part')),
        false,
      );
      await sftp.remove('uploaded.txt');
      await sftp.mkdir('test-dir');
      final f = await sftp.open(
        'test-dir/new.txt',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
      );
      await f.writeBytes(Uint8List.fromList(utf8.encode('你好 FastCat')));
      await f.close();
      final read = await sftp.open('test-dir/new.txt');
      expect(utf8.decode(await read.readBytes()), '你好 FastCat');
      await read.close();
      await sftp.rename('test-dir/new.txt', 'test-dir/renamed.txt');
      await sftp.remove('test-dir/renamed.txt');
      await sftp.rmdir('test-dir');
    },
    skip: const bool.fromEnvironment('SSH_INTEGRATION')
        ? false
        : 'Run with loopback fixture and --dart-define=SSH_INTEGRATION=true',
  );
  test(
    'host verification denial prevents login',
    () async {
      final c = SSHClient(
        await SSHSocket.connect('127.0.0.1', 22345),
        username: 'fastcat-test',
        onPasswordRequest: () => 'loopback-only-test',
        onVerifyHostKey: (_, _) => false,
      );
      addTearDown(c.close);
      await expectLater(c.authenticated, throwsA(anything));
    },
    skip: const bool.fromEnvironment('SSH_INTEGRATION')
        ? false
        : 'Loopback fixture required',
  );
}
