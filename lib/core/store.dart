import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

class Store {
  final vault = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();
  late Directory directory;
  Future<String?> backgroundImage() async {
    try {
      final f = File('${directory.path}/terminal-background');
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<AppData> load() async {
    directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final f = File('${directory.path}/workspace.json');
    return await f.exists()
        ? AppData.fromJson(jsonDecode(await f.readAsString()))
        : AppData();
  }

  Future<void> _pending = Future.value();
  Future<void> save(AppData data) {
    final snapshot = jsonEncode(data.toJson());
    final task = _pending.then((_) => _write(snapshot));
    _pending = task.catchError((Object _) {});
    return task;
  }

  Future<void> _write(String snapshot) async {
    final f = File('${directory.path}/workspace.tmp');
    await f.writeAsString(snapshot, flush: true);
    await f.rename('${directory.path}/workspace.json');
  }

  Future<void> recovery(AppData data, Map<String, String> creds) async {
    await vault.write(
      key: 'recovery',
      value: jsonEncode({'data': data.toJson(), 'credentials': creds}),
    );
  }

  Future<Map<String, dynamic>?> readRecovery() async {
    final s = await vault.read(key: 'recovery');
    return s == null ? null : jsonDecode(s);
  }

  Future<String?> credential(String id) => vault.read(key: 'credential:$id');
  Future<void> setCredential(String id, String value) =>
      vault.write(key: 'credential:$id', value: value);
  Future<void> deleteCredential(String id) =>
      vault.delete(key: 'credential:$id');
  Future<Map<String, String>> credentials(AppData data) async {
    final result = <String, String>{};
    for (final h in data.hosts) {
      final c = await credential(h.id);
      if (c != null) result[h.id] = c;
    }
    return result;
  }

  Future<String?> fingerprint(String endpoint) =>
      vault.read(key: 'fingerprint:$endpoint');
  Future<void> trust(String endpoint, String value) =>
      vault.write(key: 'fingerprint:$endpoint', value: value);
}
