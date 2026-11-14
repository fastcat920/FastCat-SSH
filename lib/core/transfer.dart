import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

/// Upload through a temporary sibling. Failed/cancelled transfers never truncate
/// the destination. Servers without overwrite rename may reject replacement.
class UploadTask {
  SftpFileWriter? _writer;
  bool cancelled = false;
  Future<void> cancel() async {
    cancelled = true;
    await _writer?.abort();
  }

  Future<void> upload(
    SftpClient sftp,
    String destination,
    Stream<Uint8List> bytes,
    void Function(int) progress,
  ) async {
    final temporary =
        '$destination.fastcat-${DateTime.now().microsecondsSinceEpoch}.part';
    SftpFile? file;
    bool published = false;
    try {
      file = await sftp.open(
        temporary,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.exclusive |
            SftpFileOpenMode.write,
      );
      if (cancelled) throw StateError('上传已取消');
      _writer = file.write(bytes, onProgress: progress);
      await _writer!.done;
      await file.close();
      file = null;
      if (cancelled) throw StateError('上传已取消');
      await sftp.rename(temporary, destination);
      published = true;
    } finally {
      await file?.close();
      if (!published) {
        try {
          await sftp.remove(temporary);
        } catch (_) {
          /* Connection loss can leave a .part file. */
        }
      }
    }
  }
}
