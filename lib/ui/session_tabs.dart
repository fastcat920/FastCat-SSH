import 'package:flutter/material.dart';

class SessionTabs extends StatelessWidget {
  final List<String> names;
  final int active;
  final ValueChanged<int> onSelect, onClose;
  const SessionTabs({
    super.key,
    required this.names,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final colors = Theme.of(context).colorScheme;
      return SingleChildScrollView(
        child: SizedBox(
          width: bounds.maxWidth,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < names.length; i++)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: bounds.maxWidth.clamp(0, 240),
                  ),
                  child: Material(
                    color: i == active
                        ? colors.secondaryContainer
                        : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: TextButton(
                            onPressed: () => onSelect(i),
                            child: Text(
                              names[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭会话',
                          onPressed: () => onClose(i),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
