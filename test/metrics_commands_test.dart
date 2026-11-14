import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/core/host_metrics.dart';
import 'package:fastcat_ssh/core/models.dart';

String sample({int cpu = 100, int idle = 850, int rx = 1000, int tx = 2000}) =>
    '''FC_SYSTEM
Linux 6.8 x86_64
FC_MODEL
Test CPU
FC_CORES
4
FC_CPU
cpu $cpu 0 50 $idle 0 0 0 0 0 0
FC_MEMORY
MemTotal: 16384000 kB
MemAvailable: 8192000 kB
FC_DISK
/dev/root 1048576 524288 524288 50% /
FC_NETWORK
Inter-| Receive | Transmit
 lo: 999999 0 0 0 0 0 0 0 999999 0 0 0 0 0 0 0
 eth0: $rx 0 0 0 0 0 0 0 $tx 0 0 0 0 0 0 0
FC_UPTIME
3600.00 0
''';
void main() {
  test(
    'Linux rates use deltas, ignore loopback and reset on counter rollover',
    () {
      final start = DateTime.utc(2026, 11, 14);
      final first = HostMetrics.parse(
        sample(),
        os: 'Linux',
        at: start,
        roundTripMs: 20,
      );
      expect(first.cores, 4);
      expect(first.rxPerSecond, isNull);
      expect(first.memoryTotal, 16384000 * 1024);
      expect(first.diskUsed, 524288 * 1024);
      expect(first.interfaces, ['eth0']);
      final second = HostMetrics.parse(
        sample(cpu: 200, idle: 950, rx: 3000, tx: 6000),
        os: 'Linux',
        at: start.add(const Duration(seconds: 2)),
        roundTripMs: 30,
        previous: first,
      );
      expect(second.cpuPercent, 50);
      expect(second.rxPerSecond, 1000);
      expect(second.txPerSecond, 2000);
      final reset = HostMetrics.parse(
        sample(rx: 1, tx: 1),
        os: 'Linux',
        at: start.add(const Duration(seconds: 4)),
        roundTripMs: 20,
        previous: second,
      );
      expect(reset.rxPerSecond, isNull);
    },
  );
  test('Windows CIM sample and unsupported targets are handled explicitly', () {
    final result = HostMetrics.parse(
      jsonEncode({
        'platform': 'Windows',
        'system': 'Windows Server',
        'model': 'CPU',
        'cores': 8,
        'cpu': 25,
        'memoryTotal': 16000,
        'memoryAvailable': 8000,
        'diskTotal': 100000,
        'diskUsed': 50000,
        'rx': null,
        'tx': null,
        'interfaces': [],
        'uptime': 3600,
      }),
      os: 'Windows',
      at: DateTime.now(),
      roundTripMs: 10,
    );
    expect(result.cpuPercent, 25);
    expect(result.rxPerSecond, isNull);
    expect(
      () => HostMetrics.parse(
        'not supported',
        os: 'Linux',
        at: DateTime.now(),
        roundTripMs: 1,
      ),
      throwsFormatException,
    );
  });
  test(
    'stored return-key option survives old and new backup model roundtrips',
    () {
      final old = Snippet.fromJson({
        'id': 'a',
        'name': 'old',
        'body': 'echo old',
      });
      expect(old.appendNewline, true);
      const typed = Snippet(
        id: 'b',
        name: 'typed',
        body: r'echo ${HOME}',
        appendNewline: false,
      );
      expect(Snippet.fromJson(typed.toJson()).appendNewline, false);
      expect(
        commandWireText(typed.body, appendNewline: false),
        r'echo ${HOME}',
      );
      expect(commandWireText('echo hi', appendNewline: true), 'echo hi\r');
      expect(commandWireText('echo hi\n', appendNewline: true), 'echo hi\n');
    },
  );
}
