import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'models.dart';

class BackupAuthenticationException implements Exception {
  const BackupAuthenticationException();
  @override
  String toString() => '无法解密：密码与这份备份不匹配，或备份内容已损坏。请核对导出时设置的备份密码及文件指纹。';
}

class BackupIntegrityException implements Exception {
  const BackupIntegrityException();
  @override
  String toString() => '备份文件完整性检查失败，请从 Mac 原文件重新复制或导出。';
}

Future<String> backupFingerprint(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Future<String> _envelopeChecksum(
  List<int> salt,
  List<int> nonce,
  List<int> ciphertext,
  List<int> mac,
) => backupFingerprint([...salt, ...nonce, ...ciphertext, ...mac]);

class BackupPayload {
  final AppData data;
  final Map<String, String> credentials;
  BackupPayload(this.data, this.credentials);
}

class BackupCodec {
  static const iterations = 600000;
  final cipher = AesGcm.with256bits();
  Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  Future<Uint8List> encode(
    AppData data,
    String password, {
    Map<String, String> credentials = const {},
  }) async {
    if (password.length < 10) throw ArgumentError('备份密码至少 10 个字符');
    final salt = SecretKeyData.random(length: 16).bytes;
    final box = await cipher.encrypt(
      utf8.encode(
        jsonEncode({'data': data.toJson(), 'credentials': credentials}),
      ),
      secretKey: await _key(password, salt),
      aad: utf8.encode('FastCat:1'),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'FastCat',
          'version': 1,
          'kdf': 'PBKDF2-SHA256',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
          'checksum': await _envelopeChecksum(
            salt,
            box.nonce,
            box.cipherText,
            box.mac.bytes,
          ),
        }),
      ),
    );
  }

  Future<BackupPayload> decode(List<int> bytes, String password) async {
    if (bytes.length > 25 * 1024 * 1024) throw const FormatException('备份文件过大');
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['format'] != 'FastCat' ||
        j['version'] != 1 ||
        j['iterations'] != iterations ||
        j['kdf'] != 'PBKDF2-SHA256') {
      throw const FormatException('不支持的备份格式');
    }
    final salt = base64Decode(j['salt'] as String),
        nonce = base64Decode(j['nonce'] as String),
        mac = base64Decode(j['mac'] as String);
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('损坏的备份');
    }
    final ciphertext = base64Decode(j['ciphertext'] as String);
    if (j.containsKey('checksum') &&
        j['checksum'] !=
            await _envelopeChecksum(salt, nonce, ciphertext, mac)) {
      throw const BackupIntegrityException();
    }
    late final List<int> plain;
    try {
      plain = await cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: await _key(password, salt),
        aad: utf8.encode('FastCat:1'),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupAuthenticationException();
    }
    final p = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final data = AppData.fromJson(Map<String, dynamic>.from(p['data']));
    final credentials = Map<String, String>.from(p['credentials'] as Map);
    if (credentials.keys.any((id) => !data.hosts.any((h) => h.id == id))) {
      throw const FormatException('无效凭据引用');
    }
    return BackupPayload(data, credentials);
  }
}

Future<Uint8List> encodeBackupWorker(Map<String, dynamic> request) =>
    BackupCodec().encode(
      AppData.fromJson(Map<String, dynamic>.from(request['data'])),
      request['password'] as String,
      credentials: Map<String, String>.from(request['credentials']),
    );
Future<BackupPayload> decodeBackupWorker(Map<String, dynamic> request) =>
    BackupCodec().decode(
      request['bytes'] as List<int>,
      request['password'] as String,
    );
