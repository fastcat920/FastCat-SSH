import 'package:flutter/material.dart';
import '../core/connection.dart';
import '../core/host_metrics.dart';

class MetricsStrip extends StatelessWidget {
  final Connection connection;
  const MetricsStrip({super.key, required this.connection});
  Future<void> details(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${connection.host.name} · 系统状态'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: connection,
              builder: (_, _) {
                final m = connection.metrics;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m != null) ...[
                      SelectableText(m.system),
                      const SizedBox(height: 12),
                      SelectableText(
                        m.cpuModel.isEmpty ? '未知 CPU' : m.cpuModel,
                      ),
                      Text('逻辑核心：${m.cores ?? '—'} · CPU：${m.cpuLabel}'),
                      Text(
                        '内存：${formatBytes(m.memoryTotal == null || m.memoryAvailable == null ? null : m.memoryTotal! - m.memoryAvailable!)} / ${formatBytes(m.memoryTotal)}',
                      ),
                      Text(
                        '系统盘：${formatBytes(m.diskUsed)} / ${formatBytes(m.diskTotal)}',
                      ),
                      Text('网络接口：${m.interfaces.join('、')}'),
                      Text(
                        '接收累计：${formatBytes(m.rx)} · 发送累计：${formatBytes(m.tx)}',
                      ),
                      Text(
                        '当前速率：↓ ${formatBytes(m.rxPerSecond)}/s · ↑ ${formatBytes(m.txPerSecond)}/s',
                      ),
                      Text(
                        '运行时间：${m.uptimeSeconds == null ? '—' : '${(m.uptimeSeconds! / 3600).toStringAsFixed(1)} 小时'}',
                      ),
                      Text('SSH 采集往返：${m.roundTripMs} ms（含远端处理）'),
                      Text(
                        '更新：${m.sampledAt.toLocal().toString().split('.').first}',
                      ),
                    ],
                    if (connection.metricsError != null)
                      Text(
                        connection.metricsError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      '连接期间每 5 秒读取一次；CPU 和网络速率需要两次采样。Linux 网络汇总非 lo 接口；Windows 汇总在线网卡，虚拟网卡可能重复计数。',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => connection.refreshMetrics(),
            child: const Text('刷新'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = connection.metrics;
    final values = m == null
        ? [connection.metricsError ?? '正在读取硬件与网络状态…']
        : [
            'CPU ${m.cores ?? '—'}核 · ${m.cpuLabel}',
            '内存 ${formatBytes(m.memoryTotal == null || m.memoryAvailable == null ? null : m.memoryTotal! - m.memoryAvailable!)}/${formatBytes(m.memoryTotal)}',
            '磁盘 ${formatBytes(m.diskUsed)}/${formatBytes(m.diskTotal)}',
            '↓ ${formatBytes(m.rxPerSecond)}/s',
            '↑ ${formatBytes(m.txPerSecond)}/s',
            'SSH ${m.roundTripMs}ms',
            if (connection.metricsError != null) '更新失败',
          ];
    return MetricsSummary(
      values: values,
      onDetails: () => details(context),
      onRefresh: connection.metricsBusy
          ? null
          : () => connection.refreshMetrics(),
    );
  }
}

class MetricsSummary extends StatelessWidget {
  final List<String> values;
  final VoidCallback onDetails;
  final VoidCallback? onRefresh;
  const MetricsSummary({
    super.key,
    required this.values,
    required this.onDetails,
    this.onRefresh,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: '硬件与网络详情',
          onPressed: onDetails,
          icon: const Icon(Icons.monitor_heart_outlined, size: 19),
        ),
        Expanded(
          child: InkWell(
            onTap: onDetails,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final value in values)
                    Text(value, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '刷新系统状态',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
        ),
      ],
    ),
  );
}
