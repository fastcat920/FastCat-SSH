import 'dart:convert';

const linuxMetricsCommand = r'''# FASTCAT_METRICS_V1
LC_ALL=C
printf 'FC_SYSTEM\n'; uname -srm
printf 'FC_MODEL\n'; awk -F: '/model name|Hardware|Processor/ {sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo
printf 'FC_CORES\n'; getconf _NPROCESSORS_ONLN
printf 'FC_CPU\n'; head -n 1 /proc/stat
printf 'FC_MEMORY\n'; cat /proc/meminfo
printf 'FC_DISK\n'; df -Pk / | tail -n 1
printf 'FC_NETWORK\n'; cat /proc/net/dev
printf 'FC_UPTIME\n'; cat /proc/uptime
''';
const windowsMetricsScript = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$os=Get-CimInstance Win32_OperatingSystem
$cpu=@(Get-CimInstance Win32_Processor)
$disk=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='"+$os.SystemDrive+"'")
$rx=$null;$tx=$null;$interfaces=@()
try{$adapters=@(Get-NetAdapter | Where-Object Status -eq 'Up');$interfaces=@($adapters | Select-Object -ExpandProperty Name);$stats=@($adapters | Get-NetAdapterStatistics);$rx=($stats | Measure-Object ReceivedBytes -Sum).Sum;$tx=($stats | Measure-Object SentBytes -Sum).Sum}catch{}
@{platform='Windows';system=$os.Caption+' '+$os.Version+' '+$os.OSArchitecture;model=($cpu | Select-Object -First 1).Name;cores=($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum;cpu=($cpu | Measure-Object LoadPercentage -Average).Average;memoryTotal=[double]$os.TotalVisibleMemorySize*1024;memoryAvailable=[double]$os.FreePhysicalMemory*1024;diskTotal=[double]$disk.Size;diskUsed=[double]$disk.Size-[double]$disk.FreeSpace;rx=$rx;tx=$tx;interfaces=$interfaces;uptime=((Get-Date)-$os.LastBootUpTime).TotalSeconds}|ConvertTo-Json -Compress
''';
String windowsMetricsCommand() {
  final units = windowsMetricsScript.codeUnits;
  final bytes = <int>[
    for (final c in units) ...[c & 255, (c >> 8) & 255],
  ];
  return 'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ${base64Encode(bytes)}';
}

class HostMetrics {
  final String platform, system, cpuModel;
  final int? cores,
      memoryTotal,
      memoryAvailable,
      diskTotal,
      diskUsed,
      rx,
      tx,
      cpuTotal,
      cpuIdle;
  final double? cpuPercent, uptimeSeconds, rxPerSecond, txPerSecond;
  final List<String> interfaces;
  final DateTime sampledAt;
  final int roundTripMs;
  HostMetrics({
    required this.platform,
    required this.system,
    required this.cpuModel,
    required this.sampledAt,
    required this.roundTripMs,
    this.cores,
    this.memoryTotal,
    this.memoryAvailable,
    this.diskTotal,
    this.diskUsed,
    this.rx,
    this.tx,
    this.cpuTotal,
    this.cpuIdle,
    this.cpuPercent,
    this.uptimeSeconds,
    this.rxPerSecond,
    this.txPerSecond,
    this.interfaces = const [],
  });
  String get cpuLabel =>
      cpuPercent == null ? '采样中' : '${cpuPercent!.toStringAsFixed(1)}%';
  static HostMetrics parse(
    String output, {
    required String os,
    required DateTime at,
    required int roundTripMs,
    HostMetrics? previous,
  }) {
    int? number(dynamic n) => n is num ? n.toInt() : int.tryParse('$n');
    String platform, system, model;
    int? cores, total, idle, mem, available, disk, used, rx, tx;
    double? cpu, uptime;
    final interfaces = <String>[];
    if (os == 'Windows') {
      final j =
          jsonDecode(output.trim().replaceFirst('\ufeff', ''))
              as Map<String, dynamic>;
      if (j['platform'] != 'Windows') throw const FormatException('不是系统采样结果');
      platform = 'Windows';
      system = j['system'] as String;
      model = j['model'] as String? ?? '未知 CPU';
      cores = number(j['cores']);
      cpu = (j['cpu'] as num?)?.toDouble();
      mem = number(j['memoryTotal']);
      available = number(j['memoryAvailable']);
      disk = number(j['diskTotal']);
      used = number(j['diskUsed']);
      rx = number(j['rx']);
      tx = number(j['tx']);
      uptime = (j['uptime'] as num?)?.toDouble();
      interfaces.addAll((j['interfaces'] as List? ?? []).map((e) => '$e'));
    } else {
      final sections = <String, List<String>>{};
      String? current;
      for (final line in const LineSplitter().convert(output)) {
        if (line.startsWith('FC_')) {
          current = line;
          sections.putIfAbsent(current, () => []);
        } else if (current != null) {
          sections[current]!.add(line);
        }
      }
      String first(String key) =>
          (sections[key] ?? [])
              .where((s) => s.trim().isNotEmpty)
              .firstOrNull
              ?.trim() ??
          '';
      system = first('FC_SYSTEM');
      if (!system.startsWith('Linux')) {
        throw const FormatException('目标不是可读取 /proc 的 Linux 系统');
      }
      platform = 'Linux';
      model = first('FC_MODEL');
      cores = int.tryParse(first('FC_CORES'));
      final counters = first('FC_CPU')
          .split(RegExp(r'\s+'))
          .skip(1)
          .take(8)
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      if (counters.length >= 4) {
        total = counters.fold(0, (a, b) => a! + b);
        idle = counters[3] + (counters.length > 4 ? counters[4] : 0);
      }
      final memory = <String, int>{};
      for (final line in sections['FC_MEMORY'] ?? <String>[]) {
        final m = RegExp(r'^(\w+):\s+(\d+)').firstMatch(line);
        if (m != null) memory[m[1]!] = int.parse(m[2]!) * 1024;
      }
      mem = memory['MemTotal'];
      available =
          memory['MemAvailable'] ??
          (memory.containsKey('MemFree')
              ? (memory['MemFree']! +
                    (memory['Buffers'] ?? 0) +
                    (memory['Cached'] ?? 0))
              : null);
      final diskParts = first('FC_DISK').split(RegExp(r'\s+'));
      if (diskParts.length >= 6) {
        disk = number(diskParts[1]);
        used = number(diskParts[2]);
        if (disk != null) disk *= 1024;
        if (used != null) used *= 1024;
      }
      var hasNetwork = false;
      var received = 0, sent = 0;
      for (final line in sections['FC_NETWORK'] ?? <String>[]) {
        final split = line.split(':');
        if (split.length != 2) continue;
        final name = split.first.trim();
        if (name == 'lo') continue;
        final values = split.last.trim().split(RegExp(r'\s+'));
        if (values.length >= 9) {
          final r = int.tryParse(values[0]), t = int.tryParse(values[8]);
          if (r != null && t != null) {
            received += r;
            sent += t;
            interfaces.add(name);
            hasNetwork = true;
          }
        }
      }
      if (hasNetwork) {
        rx = received;
        tx = sent;
      }
      uptime = double.tryParse(first('FC_UPTIME').split(' ').first);
      if (previous?.cpuTotal != null &&
          total != null &&
          idle != null &&
          previous?.cpuIdle != null) {
        final delta = total - previous!.cpuTotal!;
        if (delta > 0) {
          cpu = (100 * (1 - (idle - previous.cpuIdle!) / delta)).clamp(0, 100);
        }
      }
    }
    double? rate(int? value, int? old) {
      final seconds = previous == null
          ? 0
          : at.difference(previous.sampledAt).inMicroseconds / 1000000;
      if (value == null || old == null || seconds <= 0 || value < old) {
        return null;
      }
      return (value - old) / seconds;
    }

    return HostMetrics(
      platform: platform,
      system: system,
      cpuModel: model,
      sampledAt: at,
      roundTripMs: roundTripMs,
      cores: cores,
      cpuPercent: cpu,
      memoryTotal: mem,
      memoryAvailable: available,
      diskTotal: disk,
      diskUsed: used,
      rx: rx,
      tx: tx,
      cpuTotal: total,
      cpuIdle: idle,
      uptimeSeconds: uptime,
      interfaces: interfaces,
      rxPerSecond: rate(rx, previous?.rx),
      txPerSecond: rate(tx, previous?.tx),
    );
  }
}

String formatBytes(num? bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value.abs() >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}

String commandWireText(String text, {required bool appendNewline}) =>
    appendNewline && !text.endsWith('\r') && !text.endsWith('\n')
    ? '$text\r'
    : text;
