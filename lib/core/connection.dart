import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'models.dart';
import 'store.dart';
import 'host_metrics.dart';
import 'dart:typed_data';

class Connection extends ChangeNotifier {
  final Host host;
  final terminal = Terminal(maxLines: 10000);
  SSHClient? client, jump;
  SSHSession? shell;
  SftpClient? sftp;
  String status = '未连接', path = '.';
  List<SftpName> files = [];
  bool closed = false;
  bool directoryReady = false;
  SSHDynamicForward? tunnel;
  HostMetrics? metrics;
  String? metricsError;
  bool metricsBusy = false;
  Timer? _metricsTimer;
  final directoryCache = <String, List<SftpName>>{};
  final expandedDirectories = <String>{};
  String? directoryRoot;
  Connection(this.host);
  Future<void> connect(
    Store store,
    AppData data,
    Future<bool> Function(String, String, bool) verify,
  ) async {
    status = '连接中';
    notifyListeners();
    try {
      Future<SSHClient> open(Host h, SSHSocket socket) async {
        final secret = await store.credential(h.id);
        final auth = secret == null
            ? <String, dynamic>{}
            : jsonDecode(secret) as Map<String, dynamic>;
        final pem = auth['key'] as String?;
        final c = SSHClient(
          socket,
          username: h.username,
          identities: pem == null || pem.isEmpty
              ? null
              : SSHKeyPair.fromPem(pem, auth['passphrase'] as String?),
          onPasswordRequest: () => auth['password'] as String? ?? '',
          keepAliveInterval: const Duration(seconds: 25),
          onVerifyHostKey: (type, bytes) async {
            if (closed) return false;
            final fp = '$type ${utf8.decode(bytes)}',
                endpoint = '${h.address}:${h.port}';
            final known = await store.fingerprint(endpoint);
            if (known == fp) return true;
            final ok = await verify('${h.name} ($endpoint)', fp, known != null);
            if (ok) await store.trust(endpoint, fp);
            return ok;
          },
        );
        try {
          await c.authenticated.timeout(const Duration(seconds: 30));
          if (closed) throw StateError('会话已关闭');
          return c;
        } catch (_) {
          c.close();
          rethrow;
        }
      }

      SSHSocket socket;
      if (host.jumpId != null) {
        final h = data.hosts.where((h) => h.id == host.jumpId).firstOrNull;
        if (h == null || h.id == host.id || h.jumpId != null) {
          throw StateError('跳板机必须存在且不能嵌套');
        }
        jump = await open(
          h,
          await SSHSocket.connect(
            h.address,
            h.port,
            timeout: const Duration(seconds: 15),
          ),
        );
        socket = await jump!.forwardLocal(host.address, host.port);
      } else {
        socket = await SSHSocket.connect(
          host.address,
          host.port,
          timeout: const Duration(seconds: 15),
        );
      }
      if (closed) {
        socket.close();
        return;
      }
      client = await open(host, socket);
      shell = await client!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      if (closed) {
        close();
        return;
      }
      shell!.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            terminal.write,
            onError: (Object error) {
              if (!closed) terminal.write("\r\n$error\r\n");
            },
          );
      shell!.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            terminal.write,
            onError: (Object error) {
              if (!closed) terminal.write("\r\n$error\r\n");
            },
          );
      terminal.onOutput = (s) => shell?.write(utf8.encode(s));
      terminal.onResize = (w, h, pw, ph) {
        if (closed || status != '已连接') return;
        try {
          shell?.resizeTerminal(w, h, pw, ph);
        } catch (_) {
          /* A failed socket is reported by shell.done; layout must remain usable. */
        }
      };
      status = '已连接';
      unawaited(refreshMetrics());
      _metricsTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(refreshMetrics()),
      );
      notifyListeners();
      unawaited(
        shell!.done.then(
          (_) {
            if (!closed) {
              _metricsTimer?.cancel();
              status = '连接已关闭';
              notifyListeners();
            }
          },
          onError: (Object error) {
            if (!closed) {
              _metricsTimer?.cancel();
              status = '连接中断：$error';
              notifyListeners();
            }
          },
        ),
      );
      if (closed) {
        close();
        return;
      }
      try {
        sftp = await client!.sftp();
        await list(host.directory);
      } catch (e) {
        terminal.write('\r\n文件浏览不可用：$e\r\n');
      }
    } catch (e) {
      status = '连接失败：$e';
      client?.close();
      jump?.close();
      if (!closed) notifyListeners();
      rethrow;
    }
  }

  Future<void> list(String p) async {
    final resolved = await sftp!.absolute(p);
    final result = await sftp!.listdir(resolved);
    files =
        result.where((f) => f.filename != '.' && f.filename != '..').toList()
          ..sort((a, b) {
            if (a.attr.isDirectory != b.attr.isDirectory) {
              return a.attr.isDirectory ? -1 : 1;
            }
            return a.filename.compareTo(b.filename);
          });
    directoryCache[resolved] = files.where((f) => f.attr.isDirectory).toList();
    if (directoryRoot == null ||
        !(resolved == directoryRoot ||
            resolved.startsWith(
              '${directoryRoot!.endsWith('/') ? directoryRoot : '$directoryRoot/'}',
            ))) {
      directoryRoot = resolved;
    }
    expandedDirectories.add(resolved);
    path = resolved;
    directoryReady = true;
    if (!closed) notifyListeners();
  }

  Future<void> toggleDirectory(String directory) async {
    if (expandedDirectories.contains(directory)) {
      expandedDirectories.remove(directory);
    } else {
      if (!directoryCache.containsKey(directory)) {
        final entries = await sftp!.listdir(directory);
        directoryCache[directory] =
            entries
                .where(
                  (e) =>
                      e.filename != '.' &&
                      e.filename != '..' &&
                      e.attr.isDirectory,
                )
                .toList()
              ..sort((a, b) => a.filename.compareTo(b.filename));
      }
      expandedDirectories.add(directory);
    }
    if (!closed) notifyListeners();
  }

  Future<void> refreshMetrics() async {
    if (closed || metricsBusy || client == null || status != '已连接') return;
    metricsBusy = true;
    notifyListeners();
    SSHSession? session;
    var acceptingSession = true;
    final timer = Stopwatch()..start();
    try {
      final opening = client!.execute(
        host.os == 'Windows' ? windowsMetricsCommand() : linuxMetricsCommand,
      );
      unawaited(
        opening.then<void>((opened) {
          if (!acceptingSession) opened.close();
        }, onError: (Object _, StackTrace _) {}),
      );
      session = await opening.timeout(const Duration(seconds: 8));
      final stdout = session.stdout.fold<BytesBuilder>(BytesBuilder(), (
        builder,
        chunk,
      ) {
        if (builder.length + chunk.length > 128 * 1024) {
          throw const FormatException('系统状态输出过大');
        }
        builder.add(chunk);
        return builder;
      });
      final results = await Future.wait<dynamic>([
        stdout,
        session.stderr.drain<void>(),
      ], eagerError: true).timeout(const Duration(seconds: 12));
      timer.stop();
      final output = utf8.decode(
        (results.first as BytesBuilder).takeBytes(),
        allowMalformed: true,
      );
      if (!closed && status == '已连接') {
        metrics = HostMetrics.parse(
          output,
          os: host.os,
          at: DateTime.now(),
          roundTripMs: timer.elapsedMilliseconds,
          previous: metrics,
        );
        metricsError = null;
      }
    } catch (_) {
      if (!closed) metricsError = '状态采集不可用，请检查系统类型、命令支持及读取权限';
    } finally {
      acceptingSession = false;
      session?.close();
      metricsBusy = false;
      if (!closed) notifyListeners();
    }
  }

  String child(String name) => '${path.endsWith('/') ? path : '$path/'}$name';
  void send(String value) {
    if (status != '已连接') throw StateError('请先连接服务器');
    shell!.write(utf8.encode(value));
  }

  Future<int> startTunnel() async {
    tunnel ??= await client!.forwardDynamic(bindHost: '127.0.0.1');
    return tunnel!.port;
  }

  void close() {
    closed = true;
    _metricsTimer?.cancel();
    tunnel?.close();
    shell?.close();
    client?.close();
    jump?.close();
    status = '已断开';
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
