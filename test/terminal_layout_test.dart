import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fastcat_ssh/ui/session_tabs.dart';
import 'package:fastcat_ssh/ui/metrics_strip.dart';

void main() {
  for (final width in [375.0, 900.0]) {
    testWidgets(
      'session tabs wrap at $width and retain selection/close actions',
      (tester) async {
        int? selected, closed;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 250,
                  child: SessionTabs(
                    names: List.generate(16, (i) => '服务器窗口 $i'),
                    active: 0,
                    onSelect: (i) => selected = i,
                    onClose: (i) => closed = i,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('服务器窗口 0')).dy,
          lessThan(tester.getTopLeft(find.text('服务器窗口 8')).dy),
        );
        await tester.tap(find.text('服务器窗口 0'));
        expect(selected, 0);
        await tester.tap(find.byTooltip('关闭会话').first);
        expect(closed, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('metrics wrap onto multiple rows without horizontal scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: MetricsSummary(
              values: const [
                'CPU 4核 · 2.5%',
                '内存 1 GB/4 GB',
                '磁盘 10 GB/50 GB',
                '↓ 20 KB/s',
                '↑ 10 KB/s',
                'SSH 20ms',
              ],
              onDetails: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('SSH 20ms')).dy,
      greaterThan(tester.getTopLeft(find.text('CPU 4核 · 2.5%')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
