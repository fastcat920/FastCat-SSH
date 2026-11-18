import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// Adds edge scrolling without competing with the terminal's selection gestures.
class TerminalSelectionScroll extends StatefulWidget {
  const TerminalSelectionScroll({
    super.key,
    required this.terminal,
    required this.controller,
    required this.builder,
  });
  final Terminal terminal;
  final TerminalController controller;
  final Widget Function(GlobalKey<TerminalViewState>, ScrollController) builder;

  @override
  State<TerminalSelectionScroll> createState() =>
      _TerminalSelectionScrollState();
}

class _TerminalSelectionScrollState extends State<TerminalSelectionScroll> {
  final viewKey = GlobalKey<TerminalViewState>();
  final scroll = ScrollController();
  Timer? timer;
  int? pointer;
  Offset? position;
  CellAnchor? base;
  bool scrolled = false;

  void stop() {
    timer?.cancel();
    timer = null;
    pointer = null;
    position = null;
    base?.dispose();
    base = null;
    scrolled = false;
  }

  void updateSelection() {
    final view = viewKey.currentState;
    if (view == null || position == null || base?.attached != true) return;
    final render = view.renderTerminal;
    final local = render.globalToLocal(position!);
    final cell = render.getCellOffset(
      Offset(
        local.dx.clamp(0, render.size.width - 1),
        local.dy.clamp(0, render.size.height - 1),
      ),
    );
    widget.controller.setSelection(
      widget.terminal.buffer.createAnchorFromOffset(base!.offset),
      widget.terminal.buffer.createAnchorFromOffset(cell),
    );
  }

  void tick() {
    final view = viewKey.currentState;
    if (pointer == null ||
        position == null ||
        view == null ||
        !scroll.hasClients ||
        widget.controller.selection == null) {
      return;
    }
    final render = view.renderTerminal;
    final y = render.globalToLocal(position!).dy;
    final edge = (render.size.height / 4).clamp(1.0, 36.0);
    final double speed;
    if (y < edge) {
      speed = -((edge - y) / edge).clamp(0.0, 3.0) * 12;
    } else if (y > render.size.height - edge) {
      speed = ((y - render.size.height + edge) / edge).clamp(0.0, 3.0) * 12;
    } else {
      return;
    }
    base ??= widget.terminal.buffer.createAnchorFromOffset(
      widget.controller.selection!.begin,
    );
    final next = (scroll.offset + speed).clamp(
      scroll.position.minScrollExtent,
      scroll.position.maxScrollExtent,
    );
    if (next == scroll.offset) return;
    scroll.jumpTo(next);
    scrolled = true;
    updateSelection();
  }

  @override
  void dispose() {
    stop();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (pointer != null || event.buttons != kPrimaryButton) return;
      pointer = event.pointer;
      position = event.position;
      timer = Timer.periodic(const Duration(milliseconds: 16), (_) => tick());
    },
    onPointerMove: (event) {
      if (event.pointer != pointer) return;
      position = event.position;
      // Run after xterm's gesture handler, which uses a viewport-relative base.
      if (scrolled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && pointer != null) updateSelection();
        });
      }
    },
    onPointerUp: (event) {
      if (event.pointer == pointer) {
        if (scrolled) updateSelection();
        stop();
      }
    },
    onPointerCancel: (event) {
      if (event.pointer == pointer) {
        if (scrolled) updateSelection();
        stop();
      }
    },
    child: widget.builder(viewKey, scroll),
  );
}
