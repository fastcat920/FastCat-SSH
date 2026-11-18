import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TerminalMobileKeys extends StatelessWidget {
  const TerminalMobileKeys({super.key, required this.onSend});

  final ValueChanged<String>? onSend;

  static const rows = [
    [
      ('Esc', '\x1b'),
      ('Tab', '\t'),
      ('Ctrl+C', '\x03'),
      ('Ctrl+D', '\x04'),
      ('Ctrl+Z', '\x1a'),
      ('回车', '\r'),
    ],
    [
      ('Home', '\x1b[H'),
      ('End', '\x1b[F'),
      ('←', '\x1b[D'),
      ('↑', '\x1b[A'),
      ('↓', '\x1b[B'),
      ('→', '\x1b[C'),
      ('退格', '\x7f'),
    ],
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < rows.length; row++)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (final key in rows[row])
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        minimumSize: Size.zero,
                      ),
                      onPressed: onSend == null ? null : () => onSend!(key.$2),
                      child: FittedBox(child: Text(key.$1, maxLines: 1)),
                    ),
                  ),
                if (row == 0)
                  Expanded(
                    child: IconButton(
                      tooltip: '收起键盘',
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        SystemChannels.textInput.invokeMethod<void>(
                          'TextInput.hide',
                        );
                      },
                      icon: const Icon(Icons.keyboard_hide_outlined, size: 22),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
