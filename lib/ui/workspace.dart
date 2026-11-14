import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'app_input.dart';
import 'app_theme.dart';
import 'input_dialog.dart';
import 'host_editor.dart';
import 'syntax_controller.dart';
import 'code_theme.dart';
import 'backup_import_dialog.dart';
import 'metrics_strip.dart';
import 'code_editor.dart';
import 'session_tabs.dart';
import '../core/host_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/backup.dart';
import '../core/connection.dart';
import '../core/transfer.dart';

class _CatalogDrag {
  final bool folder;
  final String id;
  const _CatalogDrag(this.folder, this.id);
}

class Workspace extends StatefulWidget {
  final Store store;
  final ValueChanged<AppData>? onAppearanceChanged;
  const Workspace({super.key, required this.store, this.onAppearanceChanged});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  AppData data = AppData();
  bool loaded = false, busy = false;
  String? loadError;
  String search = '';
  int mobilePage = 0, tool = 0, active = 0;
  bool split = false;
  bool settingsExpanded = true, groupSaving = false;
  String selectedCategory = '默认分类';
  String? previewSnippetId;
  String draftCategory = '默认分类';
  bool draftAppendNewline = true, composerSaving = false;
  String? composerError;
  String? sendFeedback;
  bool sendFailed = false, commandSending = false;
  final composerName = TextEditingController();
  final composerNameFocus = FocusNode();
  String? backgroundPath;
  final searchInput = TextEditingController();
  final terminalControllers = <Connection, TerminalController>{};
  String transfer = '';
  UploadTask? uploadTask;
  Future<void> Function()? retryUpload;
  final sessions = <Connection>[];
  final path = TextEditingController();
  final command = SyntaxController();
  final catalogScroll = ScrollController();
  final catalogKey = GlobalKey();
  Timer? catalogDragTimer;
  Offset? catalogDragPosition;
  Connection? get current =>
      sessions.isEmpty ? null : sessions[active.clamp(0, sessions.length - 1)];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      data = await widget.store.load();
      backgroundPath = await widget.store.backgroundImage();
      if (!data.categories.contains(selectedCategory)) {
        selectedCategory = data.categories.firstOrNull ?? '';
      }
      draftCategory = selectedCategory;
      if (mounted) {
        setState(() => loaded = true);
        widget.onAppearanceChanged?.call(data);
      }
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  @override
  void dispose() {
    uploadTask?.cancel();
    for (final s in sessions) {
      s.dispose();
    }
    path.dispose();
    command.dispose();
    catalogDragTimer?.cancel();
    catalogScroll.dispose();
    composerName.dispose();
    composerNameFocus.dispose();
    searchInput.dispose();
    for (final c in terminalControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      message('$e');
    }
  }

  Future<void> save() => widget.store.save(data);
  Future<bool> confirm(
    String title,
    String body, {
    String action = '确认',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<String?> input(
    String title, {
    String initial = '',
    bool secret = false,
    bool multiline = false,
    bool code = false,
    bool allowEmpty = false,
    String? helper,
    FormFieldValidator<String>? validator,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InputDialog(
      title: title,
      initial: initial,
      secret: secret,
      multiline: multiline,
      code: code,
      allowEmpty: allowEmpty,
      helper: helper,
      validator: validator,
    ),
  );

  Future<void> editHost([Host? existing, String? defaultGroup]) async {
    final old = existing == null
        ? null
        : await widget.store.credential(existing.id);
    if (!mounted) return;
    final auth = old == null
        ? <String, dynamic>{}
        : jsonDecode(old) as Map<String, dynamic>;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HostEditor(
        host: existing,
        groups: data.groups,
        defaultGroup: defaultGroup,
        hosts: data.hosts,
        auth: auth,
        onSave: (host, credentials) async {
          final before = old;
          final next = data.copy();
          next.hosts.removeWhere((h) => h.id == host.id);
          next.hosts.add(host);
          if (!next.groups.contains(host.group)) next.groups.add(host.group);
          await widget.store.setCredential(host.id, jsonEncode(credentials));
          try {
            await widget.store.save(next);
          } catch (_) {
            if (before == null) {
              await widget.store.deleteCredential(host.id);
            } else {
              await widget.store.setCredential(host.id, before);
            }
            rethrow;
          }
          if (mounted) setState(() => data = next);
        },
      ),
    );
  }

  Future<void> connect(Host h) async {
    final s = Connection(h);
    terminalControllers[s] = TerminalController();
    s.addListener(refresh);
    setState(() {
      sessions.add(s);
      active = sessions.length - 1;
      mobilePage = 1;
    });
    await run(() async {
      await s.connect(
        widget.store,
        data,
        (name, fp, changed) => confirm(
          changed ? '服务器指纹已变化' : '首次连接：确认服务器指纹',
          '$name\n\n$fp\n\n请通过可信途径核对指纹。${changed ? '旧指纹不匹配，请确认服务器是否重装或密钥已更换。' : ''}',
          action: '信任并连接',
        ),
      );
      if (s.directoryReady) data.visit(h.id, s.path);
      if (mounted && current == s) path.text = s.path;
      await save();
    });
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void close(int i) {
    final s = sessions.removeAt(i);
    s.removeListener(refresh);
    s.dispose();
    terminalControllers.remove(s)?.dispose();
    setState(
      () =>
          active = active.clamp(0, sessions.isEmpty ? 0 : sessions.length - 1),
    );
    path.text = current?.path ?? '';
  }

  Future<void> navigate(String p, {Connection? target}) async {
    final s = target ?? current;
    if (s == null || s.sftp == null) return;
    await run(() async {
      await s.list(p);
      if (mounted && current == s) path.text = s.path;
      data.visit(s.host.id, s.path);
      await save();
    });
  }

  Widget icon(IconData i, String tip, VoidCallback f) =>
      IconButton(tooltip: tip, onPressed: f, icon: Icon(i, size: 20));
  Future<void> toggleGroup(String group) async {
    setState(() {
      if (data.collapsedGroups.contains(group)) {
        data.collapsedGroups.remove(group);
      } else {
        data.collapsedGroups.add(group);
      }
    });
    await save();
  }

  Future<void> renameGroup(String group) async {
    if (groupSaving) return;
    final name = (await input(
      '修改服务器分组',
      initial: group,
      validator: (v) => v?.trim() != group && data.groups.contains(v?.trim())
          ? '此分组已存在'
          : null,
    ))?.trim();
    if (name == null || name == group || !mounted) return;
    await updateGroups((next) {
      next.groups[next.groups.indexOf(group)] = name;
      next.hosts = [
        for (final host in next.hosts)
          if (host.group == group)
            Host.fromJson({...host.toJson(), 'group': name})
          else
            host,
      ];
      next.collapsedGroups = [
        for (final value in next.collapsedGroups) value == group ? name : value,
      ];
    });
  }

  Future<void> updateGroups(void Function(AppData) change) async {
    if (groupSaving) return;
    setState(() => groupSaving = true);
    try {
      final next = data.copy();
      change(next);
      await widget.store.save(next);
      if (mounted) setState(() => data = next);
    } catch (_) {
      message('分组保存失败，原数据已保留');
    } finally {
      if (mounted) setState(() => groupSaving = false);
    }
  }

  Widget groupDrag(String group, Widget child) => DragTarget<String>(
    onWillAcceptWithDetails: (d) =>
        !groupSaving && d.data != group && data.groups.contains(d.data),
    onAcceptWithDetails: (d) => run(
      () => updateGroups((next) {
        final from = next.groups.indexOf(d.data),
            to = next.groups.indexOf(group);
        if (from >= 0 && to >= 0) {
          next.groups.insert(to, next.groups.removeAt(from));
        }
      }),
    ),
    builder: (context, candidates, _) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary,
        ),
      ),
      child: LongPressDraggable<String>(
        key: ValueKey('server-group-$group'),
        data: group,
        maxSimultaneousDrags: groupSaving ? 0 : 1,
        feedback: Material(
          elevation: 4,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(group)),
        ),
        childWhenDragging: Opacity(opacity: .35, child: child),
        child: child,
      ),
    ),
  );

  List<Widget> settingsItems() => [
    ListTile(
      leading: const Icon(Icons.lock_outline),
      title: const Text('备份与恢复'),
      onTap: backupMenu,
    ),
    ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('外观与终端'),
      onTap: () => run(appearanceMenu),
    ),
    ListTile(
      leading: const Icon(Icons.dashboard_customize_outlined),
      title: const Text('工作区布局'),
      onTap: layoutMenu,
    ),
  ];
  Widget settingsPage() => ListView(
    children: [
      const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          '设置',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      ...settingsItems(),
    ],
  );

  Future<void> addGroup() async {
    final name = (await input(
      '添加分组',
      validator: (v) => data.groups.contains(v?.trim()) ? '此分组已存在' : null,
    ))?.trim();
    if (name == null) return;
    setState(() => data.groups.add(name));
    await save();
  }

  Widget hostTile(Host h) => ListTile(
    leading: Icon(
      h.os == 'Windows' ? Icons.desktop_windows : Icons.dns_outlined,
      size: 21,
    ),
    title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${h.username}@${h.address}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => connect(h),
    trailing: PopupMenuButton<String>(
      onSelected: (v) => run(() async {
        if (v == 'edit') {
          await editHost(h);
        } else if (await confirm('删除服务器', h.name)) {
          if (data.hosts.any((x) => x.jumpId == h.id)) {
            throw StateError('请先解除使用此服务器的跳板机配置');
          }
          setState(() => data.hosts.remove(h));
          await widget.store.deleteCredential(h.id);
          await save();
        }
      }),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ),
  );
  Widget sidebar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.terminal,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'FastCat SSH',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                ),
              ),
              icon(
                Icons.create_new_folder_outlined,
                '添加分组',
                () => run(addGroup),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: AppInput(
            controller: searchInput,
            label: '搜索服务器',
            hint: '名称、地址或用户名',
            prefix: Icon(Icons.search),
            action: TextInputAction.search,
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final group in {
                ...data.groups,
                ...data.hosts.map((h) => h.group),
              }) ...[
                groupDrag(
                  group,
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => run(() => toggleGroup(group)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    group,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  '（${data.hosts.where((h) => h.group == group).length}）',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        icon(
                          data.collapsedGroups.contains(group)
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          data.collapsedGroups.contains(group)
                              ? '展开 $group'
                              : '折叠 $group',
                          () => run(() => toggleGroup(group)),
                        ),
                        icon(
                          Icons.edit_outlined,
                          '修改分组 $group',
                          () => run(() => renameGroup(group)),
                        ),
                        icon(
                          Icons.add,
                          '添加服务器',
                          () => run(() => editHost(null, group)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!data.collapsedGroups.contains(group) ||
                    search.isNotEmpty) ...[
                  for (final h in data.hosts.where(
                    (h) =>
                        h.group == group &&
                        '${h.name} ${h.address} ${h.username}'
                            .toLowerCase()
                            .contains(search.toLowerCase()),
                  ))
                    hostTile(h),
                  if (!data.hosts.any((h) => h.group == group) &&
                      search.isEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 12, 12),
                      child: Text(
                        '暂无服务器，点击分组右侧 ＋ 添加',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 760) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            trailing: Icon(
              settingsExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => settingsExpanded = !settingsExpanded),
          ),
          if (settingsExpanded) ...settingsItems(),
        ],
      ],
    ),
  );
  Widget terminalPanel() => LayoutBuilder(
    builder: (context, bounds) => Column(
      children: [
        SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (current != null) ...[
                icon(
                  Icons.copy,
                  '复制终端选中内容',
                  () => run(() => copyTerminal(current!)),
                ),
                icon(
                  Icons.paste,
                  '粘贴到终端',
                  () => run(() => pasteTerminal(current!)),
                ),
              ],
              icon(
                data.showTerminalInfo
                    ? Icons.monitor_heart
                    : Icons.monitor_heart_outlined,
                data.showTerminalInfo ? '隐藏终端信息' : '显示终端信息',
                () => run(() async {
                  setState(
                    () => data.showTerminalInfo = !data.showTerminalInfo,
                  );
                  await save();
                }),
              ),
              icon(
                Icons.vertical_split_outlined,
                '切换双会话分屏',
                () => setState(() => split = !split),
              ),
              icon(Icons.refresh, '重新连接', () {
                final h = current?.host;
                if (h != null) {
                  close(active);
                  connect(h);
                }
              }),
            ],
          ),
        ),
        if (sessions.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (bounds.maxHeight * .25).clamp(48.0, 140.0),
            ),
            child: SessionTabs(
              names: sessions.map((s) => s.host.name).toList(),
              active: active,
              onSelect: (i) => setState(() {
                active = i;
                path.text = current!.path;
              }),
              onClose: close,
            ),
          ),
        Expanded(
          child: current == null
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.terminal,
                          size: 52,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        SizedBox(height: 16),
                        Text('你的服务器工作区', style: TextStyle(fontSize: 24)),
                        SizedBox(height: 8),
                        Text(
                          '选择服务器连接，或添加新的连接',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => run(() => editHost()),
                          icon: Icon(Icons.add),
                          label: Text('添加服务器'),
                        ),
                      ],
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(child: terminalView(current!)),
                    if (split && sessions.length > 1) ...[
                      VerticalDivider(width: 1),
                      Expanded(
                        child: terminalView(
                          sessions[(active + 1) % sessions.length],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if (data.showTerminalInfo && current?.status == '已连接')
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bounds.maxHeight * .3),
            child: SingleChildScrollView(
              child: MetricsStrip(connection: current!),
            ),
          ),
        if (current != null && MediaQuery.sizeOf(context).width < 760)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final key in {
                  'Esc': '\x1b',
                  'Tab': '\t',
                  'Ctrl+C': '\x03',
                  'Ctrl+D': '\x04',
                  '←': '\x1b[D',
                  '↑': '\x1b[A',
                  '↓': '\x1b[B',
                  '→': '\x1b[C',
                }.entries)
                  TextButton(
                    onPressed: current!.status != '已连接'
                        ? null
                        : () => run(() async {
                            current!.send(key.value);
                          }),
                    child: Text(key.key),
                  ),
              ],
            ),
          ),
        if (current != null)
          Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: 12),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 7,
                  color: current!.status == '已连接'
                      ? Theme.of(context).colorScheme.primary
                      : Colors.orange,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current!.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                Text(
                  '${current!.host.os} · SSH',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget tools() => Column(
    children: [
      Row(
        children: [
          for (var i = 0; i < 2; i++)
            TextButton(
              onPressed: () => setState(() => tool = i),
              child: Text(
                ['文件目录', '命令库'][i],
                style: TextStyle(
                  color: tool == i
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Spacer(),
          if (current?.client != null)
            icon(
              Icons.route_outlined,
              '启动本地 SOCKS5 隧道',
              () => run(() async {
                final p = await current!.startTunnel();
                message('SOCKS5：127.0.0.1:$p（关闭会话时停止）');
              }),
            ),
        ],
      ),
      Divider(height: 1),
      Expanded(child: tool == 0 ? filesPanel() : snippetsPanel()),
    ],
  );
  Widget filesPanel() {
    final s = current;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: AppInput(
                  controller: path,
                  label: '远程目录',
                  hint: s?.path ?? '连接后浏览目录',
                  code: true,
                  enabled: s?.sftp != null,
                  action: TextInputAction.go,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) navigate(value);
                  },
                  prefix: Icon(Icons.folder_outlined, size: 18),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '目录历史',
                icon: Icon(Icons.history),
                onSelected: (p) => run(() async {
                  if (p == '__clear') {
                    data.history.clear();
                    await save();
                    setState(() {});
                  } else {
                    await navigate(p);
                  }
                }),
                itemBuilder: (_) => [
                  for (final p in data.history['global'] ?? <String>[])
                    PopupMenuItem(value: p, child: Text(p)),
                  PopupMenuItem(value: '__clear', child: Text('清空目录历史')),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: '收藏目录',
                icon: Icon(Icons.star_outline),
                onSelected: (p) => run(() async {
                  if (s == null) return;
                  if (p == '__add') {
                    data.favorites.putIfAbsent('global', () => []);
                    if (!data.favorites['global']!.contains(s.path)) {
                      data.favorites['global']!.add(s.path);
                    }
                    await save();
                    setState(() {});
                  } else {
                    await navigate(p);
                  }
                }),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: '__add',
                    enabled: s?.directoryReady == true,
                    child: Text('收藏当前目录'),
                  ),
                  for (final p in data.favorites['global'] ?? <String>[])
                    PopupMenuItem(value: p, child: Text(p)),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: s?.sftp == null ? null : () => run(upload),
              icon: Icon(Icons.upload, size: 18),
              label: Text('上传'),
            ),
            TextButton.icon(
              onPressed: s?.sftp == null
                  ? null
                  : () => run(() async {
                      final name = await input(
                        '新建目录',
                        code: true,
                        validator: fileNameError,
                      );
                      if (name == null || name.isEmpty) return;
                      validateName(name);
                      await s!.sftp!.mkdir(s.child(name));
                      await navigate(s.path, target: s);
                    }),
              icon: Icon(Icons.create_new_folder_outlined, size: 18),
              label: Text('新建目录'),
            ),
            IconButton(
              tooltip: '上一级',
              onPressed: () => navigate('${s?.path ?? '.'}/..'),
              icon: const RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.subdirectory_arrow_left, size: 20),
              ),
            ),
            icon(Icons.refresh, '刷新目录', () => navigate(s?.path ?? '.')),
            Expanded(
              child: Text(
                transfer,
                style: TextStyle(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (uploadTask != null || retryUpload != null)
          Row(
            children: [
              if (uploadTask != null)
                TextButton.icon(
                  onPressed: () => run(() => uploadTask!.cancel()),
                  icon: Icon(Icons.cancel_outlined),
                  label: Text('取消上传'),
                ),
              if (retryUpload != null)
                TextButton.icon(
                  onPressed: () => run(retryUpload!),
                  icon: Icon(Icons.refresh),
                  label: Text('重新上传'),
                ),
            ],
          ),
        Expanded(
          child: s?.sftp == null
              ? Center(
                  child: Text(
                    '连接后查看远程文件',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : directoryFiles(s!),
        ),
      ],
    );
  }

  Widget directoryFiles(Connection s) => LayoutBuilder(
    builder: (context, bounds) {
      final files = s.files.where((f) => !f.attr.isDirectory).toList();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: (bounds.maxWidth * .35).clamp(100.0, 260.0),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(6),
                  child: Text(
                    '目录',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: directoryNodes(
                      s,
                      s.directoryRoot ?? s.path,
                      0,
                      <String>{},
                    ),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(6),
                  child: Text(
                    '当前目录文件 · ${files.length}',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: files.isEmpty
                      ? Center(child: Text('此目录没有文件'))
                      : ListView.builder(
                          itemCount: files.length,
                          itemBuilder: (_, i) {
                            final file = files[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: Icon(
                                Icons.insert_drive_file_outlined,
                                size: 18,
                              ),
                              title: Text(
                                file.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                formatBytes(file.attr.size),
                                style: TextStyle(fontSize: 10),
                              ),
                              onTap: () => run(() => editFile(s, file)),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) =>
                                    run(() => fileAction(s, file, v)),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'download',
                                    child: Text('下载'),
                                  ),
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('重命名'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
  List<Widget> directoryNodes(
    Connection s,
    String directory,
    int depth,
    Set<String> visited,
  ) {
    if (depth > 12 || !visited.add(directory)) return [];
    final expanded = s.expandedDirectories.contains(directory);
    final label = depth == 0
        ? directory
        : directory.split('/').where((p) => p.isNotEmpty).lastOrNull ??
              directory;
    return [
      Material(
        color: s.path == directory
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(left: (depth * 10.0).clamp(0, 60)),
          child: Row(
            children: [
              IconButton(
                constraints: BoxConstraints.tightFor(width: 30, height: 38),
                padding: EdgeInsets.zero,
                tooltip: expanded ? '折叠目录 $directory' : '展开目录 $directory',
                onPressed: () => run(() => s.toggleDirectory(directory)),
                icon: Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: directory,
                  child: InkWell(
                    onTap: () => navigate(directory, target: s),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (expanded)
        for (final entry in s.directoryCache[directory] ?? <SftpName>[])
          ...directoryNodes(
            s,
            '${directory.endsWith('/') ? directory : '$directory/'}${entry.filename}',
            depth + 1,
            visited,
          ),
    ];
  }

  String? fileNameError(String? value) {
    try {
      validateName(value ?? '');
      return null;
    } catch (_) {
      return '名称不能为 . 或 ..，也不能包含路径分隔符';
    }
  }

  void validateName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\x00')) {
      throw FormatException('请输入文件名，不包含路径分隔符');
    }
  }

  Future<void> fileAction(Connection s, SftpName f, String action) async {
    final remote = s.child(f.filename);
    if (action == 'download') {
      final file = await s.sftp!.open(remote);
      Uint8List bytes;
      try {
        if ((f.attr.size ?? 0) > 100 * 1024 * 1024) {
          throw StateError('当前下载限制为 100 MB');
        }
        bytes = await file.readBytes(length: 100 * 1024 * 1024 + 1);
        if (bytes.length > 100 * 1024 * 1024) throw StateError('文件超过 100 MB');
      } finally {
        await file.close();
      }
      await FilePicker.saveFile(fileName: f.filename, bytes: bytes);
      message('下载已完成或取消');
    }
    if (action == 'rename') {
      final name = await input(
        '重命名',
        initial: f.filename,
        code: true,
        validator: fileNameError,
      );
      if (name == null || name.isEmpty) return;
      validateName(name);
      await s.sftp!.rename(remote, s.child(name));
    }
    if (action == 'delete' &&
        await confirm('删除远程文件', '确定删除 $remote？目录仅支持删除空目录。', action: '删除')) {
      if (f.attr.isDirectory) {
        await s.sftp!.rmdir(remote);
      } else {
        await s.sftp!.remove(remote);
      }
    }
    await navigate(s.path, target: s);
  }

  Future<void> upload() async {
    if (uploadTask != null) throw StateError('请等待当前上传完成');
    final s = current!;
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final f = picked;
    validateName(f.name);
    if ((await f.length() ?? 0) > 100 * 1024 * 1024) {
      throw StateError('当前上传限制为 100 MB');
    }
    if (s.files.any((e) => e.filename == f.name) &&
        !await confirm('覆盖文件', '远程存在 ${f.name}，是否覆盖？')) {
      return;
    }
    final destination = s.child(f.name);
    final total = await f.length();
    Future<void> perform() async {
      if (uploadTask != null) return;
      final task = UploadTask();
      setState(() {
        uploadTask = task;
        transfer = '上传 ${f.name}…';
        retryUpload = null;
      });
      try {
        await task.upload(s.sftp!, destination, f.readAsByteStream(), (count) {
          if (mounted) {
            setState(
              () => transfer = '${f.name} · $count / ${total ?? '?'} bytes',
            );
          }
        });
        if (mounted) setState(() => transfer = '上传完成：${f.name}');
        if (current == s) await navigate(s.path, target: s);
      } catch (e) {
        if (mounted) {
          setState(() {
            transfer = '上传未完成：$e';
            retryUpload = perform;
          });
        }
        rethrow;
      } finally {
        if (mounted) setState(() => uploadTask = null);
      }
    }

    await perform();
  }

  Future<void> editFile(Connection s, SftpName f) async {
    if ((f.attr.size ?? 0) > 1024 * 1024) {
      throw StateError('文本编辑限制为 1 MB，请下载文件');
    }
    final remote = s.child(f.filename);
    final before = await s.sftp!.stat(remote);
    final file = await s.sftp!.open(remote);
    late Uint8List bytes;
    try {
      bytes = await file.readBytes(length: 1024 * 1024 + 1);
      if (bytes.length > 1024 * 1024) throw StateError('文件超过文本编辑限制');
    } finally {
      await file.close();
    }
    final text = utf8.decode(bytes);
    final edited = await input(
      '编辑 ${f.filename}',
      initial: text,
      multiline: true,
      code: true,
      allowEmpty: true,
      helper: '多行编辑；Ctrl / ⌘ + Enter 确认，换行不会提交。',
    );
    if (edited == null || edited == text) return;
    final after = await s.sftp!.stat(remote);
    if (before.modifyTime != after.modifyTime || before.size != after.size) {
      throw StateError('远程文件已变化，请重新打开后编辑');
    }
    if (!await confirm('保存远程文件', '将覆盖 $remote，确定保存？')) return;
    final out = await s.sftp!.open(
      remote,
      mode: SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    try {
      await out.writeBytes(Uint8List.fromList(utf8.encode(edited)));
    } finally {
      await out.close();
    }
    await navigate(s.path, target: s);
  }

  Snippet? get previewSnippet =>
      data.snippets.where((s) => s.id == previewSnippetId).firstOrNull;
  bool get composerDirty {
    final original = previewSnippet;
    if (original == null) {
      return composerName.text.isNotEmpty || command.text.isNotEmpty;
    }
    return original.name != composerName.text ||
        original.body != command.text ||
        original.category != draftCategory ||
        original.appendNewline != draftAppendNewline;
  }

  Future<bool> discardDraft() async =>
      !composerDirty ||
      await confirm('替换未保存的命令', '当前编辑内容尚未保存，是否放弃这些修改？', action: '放弃修改');
  Future<void> newComposer() async {
    if (composerSaving || !await discardDraft()) return;
    setState(() {
      previewSnippetId = null;
      composerName.clear();
      command.clear();
      draftCategory = selectedCategory;
      draftAppendNewline = true;
      composerError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) composerNameFocus.requestFocus();
    });
  }

  Future<void> selectComposer(Snippet snippet) async {
    if (composerSaving ||
        previewSnippetId == snippet.id ||
        !await discardDraft()) {
      return;
    }
    setState(() {
      previewSnippetId = snippet.id;
      composerName.text = snippet.name;
      command.text = snippet.body;
      draftCategory = snippet.category;
      draftAppendNewline = snippet.appendNewline;
      composerError = null;
    });
  }

  Future<void> newCategory() async {
    if (composerSaving) return;
    setState(() => composerSaving = true);
    try {
      final name = (await input(
        '新建命令分类',
        validator: (v) => data.categories.contains(v?.trim()) ? '此分类已存在' : null,
      ))?.trim();
      if (name == null || !mounted) return;
      final next = data.copy()..categories.add(name);
      await widget.store.save(next);
      if (!mounted) return;
      setState(() {
        data = next;
        selectedCategory = name;
        if (draftCategory.isEmpty ||
            (previewSnippetId == null && !composerDirty)) {
          draftCategory = name;
        }
        composerError = null;
      });
    } catch (_) {
      if (mounted) setState(() => composerError = '分类保存失败，原数据已保留');
    } finally {
      if (mounted) setState(() => composerSaving = false);
    }
  }

  Future<void> manageCategory(String category, String action) async {
    if (composerSaving || !data.categories.contains(category)) return;
    setState(() => composerSaving = true);
    try {
      final next = data.copy();
      String? renamed;
      final removedIds = <String>{};
      if (action == 'edit') {
        renamed = (await input(
          '编辑命令分类',
          initial: category,
          validator: (v) =>
              v?.trim() != category && data.categories.contains(v?.trim())
              ? '此分类已存在'
              : null,
        ))?.trim();
        if (renamed == null || renamed == category || !mounted) return;
        next.categories[next.categories.indexOf(category)] = renamed;
        next.snippets = [
          for (final snippet in next.snippets)
            if (snippet.category == category)
              Snippet.fromJson({...snippet.toJson(), 'category': renamed})
            else
              snippet,
        ];
      } else if (action == 'delete') {
        removedIds.addAll(
          next.snippets.where((s) => s.category == category).map((s) => s.id),
        );
        if (removedIds.isNotEmpty &&
            !await confirm(
              '删除命令分类',
              '“$category”下有 ${removedIds.length} 条命令，删除分类将同时删除这些命令，确定继续？',
              action: '删除',
            )) {
          return;
        }
        if (!mounted) return;
        next.snippets.removeWhere((s) => s.category == category);
        next.categories.remove(category);
      } else {
        return;
      }
      await widget.store.save(next);
      if (!mounted) return;
      final dirty = composerDirty;
      setState(() {
        data = next;
        final fallback = next.categories.firstOrNull ?? '';
        if (selectedCategory == category) {
          selectedCategory = renamed ?? fallback;
        }
        if (draftCategory == category) draftCategory = renamed ?? fallback;
        if (removedIds.contains(previewSnippetId)) {
          previewSnippetId = null;
          if (!dirty) {
            composerName.clear();
            command.clear();
            draftAppendNewline = true;
          }
        }
        composerError = null;
      });
    } catch (_) {
      if (mounted) setState(() => composerError = '分类修改失败，原数据已保留');
    } finally {
      if (mounted) setState(() => composerSaving = false);
    }
  }

  Future<void> saveComposer() async {
    if (composerSaving) return;
    if (!data.categories.contains(draftCategory)) {
      setState(() => composerError = '请先新建命令分类');
      return;
    }
    if (composerName.text.trim().isEmpty || command.text.trim().isEmpty) {
      setState(() => composerError = '保存前请填写命令名称和内容');
      if (composerName.text.trim().isEmpty) composerNameFocus.requestFocus();
      return;
    }
    final original = previewSnippet;
    final value = Snippet(
      id: original?.id ?? newId(),
      name: composerName.text.trim(),
      body: command.text,
      category: draftCategory,
      os: original?.os ?? '通用',
      directSend: true,
      appendNewline: draftAppendNewline,
    );
    setState(() {
      composerSaving = true;
      composerError = null;
    });
    try {
      final next = data.copy();
      final index = next.snippets.indexWhere((s) => s.id == value.id);
      if (index < 0) {
        next.snippets.add(value);
      } else {
        next.snippets[index] = value;
      }
      await widget.store.save(next);
      if (mounted) {
        setState(() {
          data = next;
          previewSnippetId = null;
          selectedCategory = value.category;
          draftCategory = value.category;
          composerName.clear();
          command.clear();
          sendFeedback = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => composerError = '保存失败，编辑内容已保留，请重试');
    } finally {
      if (mounted) setState(() => composerSaving = false);
    }
  }

  Future<void> deleteComposer() async {
    final selected = previewSnippet;
    if (composerSaving ||
        selected == null ||
        !await confirm('删除命令', selected.name)) {
      return;
    }
    setState(() => composerSaving = true);
    try {
      final next = data.copy();
      next.snippets.removeWhere((s) => s.id == selected.id);
      await widget.store.save(next);
      if (mounted) {
        setState(() {
          data = next;
          previewSnippetId = null;
          composerName.clear();
          command.clear();
          composerError = null;
          draftAppendNewline = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => composerError = '删除失败，编辑内容已保留');
    } finally {
      if (mounted) setState(() => composerSaving = false);
    }
  }

  Future<void> sendCatalogSnippet(Snippet snippet) => sendText(
    previewSnippetId == snippet.id ? command.text : snippet.body,
    direct: true,
    appendNewline: previewSnippetId == snippet.id
        ? draftAppendNewline
        : snippet.appendNewline,
  );
  void endCatalogDrag() {
    catalogDragTimer?.cancel();
    catalogDragTimer = null;
    catalogDragPosition = null;
  }

  void startCatalogDrag() {
    FocusManager.instance.primaryFocus?.unfocus();
    endCatalogDrag();
    catalogDragTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final box = catalogKey.currentContext?.findRenderObject() as RenderBox?;
      final point = catalogDragPosition;
      if (!mounted ||
          box == null ||
          point == null ||
          !catalogScroll.hasClients) {
        return;
      }
      final local = box.globalToLocal(point);
      if (local.dx < 0 || local.dx > box.size.width) return;
      final delta = local.dy < 40
          ? -12.0
          : local.dy > box.size.height - 40
          ? 12.0
          : 0.0;
      if (delta == 0) return;
      catalogScroll.jumpTo(
        (catalogScroll.offset + delta).clamp(
          catalogScroll.position.minScrollExtent,
          catalogScroll.position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> moveCatalogItem(_CatalogDrag source, String target) async {
    if (composerSaving || source.id == target) return;
    final next = data.copy();
    if (source.folder) {
      final from = next.categories.indexOf(source.id),
          to = next.categories.indexOf(target);
      if (from < 0 || to < 0) return;
      next.categories.insert(to, next.categories.removeAt(from));
    } else {
      final from = next.snippets.indexWhere((s) => s.id == source.id);
      final to = next.snippets.indexWhere((s) => s.id == target);
      if (from < 0 ||
          to < 0 ||
          next.snippets[from].category != next.snippets[to].category) {
        return;
      }
      next.snippets.insert(to, next.snippets.removeAt(from));
    }
    setState(() => composerSaving = true);
    try {
      await widget.store.save(next);
      if (mounted) {
        setState(() {
          data = next;
          composerError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => composerError = '排序保存失败，原顺序已保留');
    } finally {
      if (mounted) setState(() => composerSaving = false);
    }
  }

  Widget catalogReorderItem(
    bool folder,
    String id,
    String label,
    Widget child,
  ) => DragTarget<_CatalogDrag>(
    onWillAcceptWithDetails: (details) =>
        !composerSaving &&
        details.data.folder == folder &&
        details.data.id != id,
    onAcceptWithDetails: (details) =>
        run(() => moveCatalogItem(details.data, id)),
    builder: (context, candidates, rejected) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: LongPressDraggable<_CatalogDrag>(
        key: ValueKey('catalog-${folder ? 'folder' : 'command'}-$id'),
        data: _CatalogDrag(folder, id),
        maxSimultaneousDrags: composerSaving ? 0 : 1,
        onDragStarted: startCatalogDrag,
        onDragUpdate: (details) => catalogDragPosition = details.globalPosition,
        onDragEnd: (_) => endCatalogDrag(),
        onDraggableCanceled: (_, _) => endCatalogDrag(),
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: child),
        child: child,
      ),
    ),
  );

  Widget commandCatalog() => AbsorbPointer(
    absorbing: composerSaving,
    child: SingleChildScrollView(
      key: catalogKey,
      controller: catalogScroll,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, bounds) => Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final category in data.categories)
                  catalogReorderItem(
                    true,
                    category,
                    category,
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: bounds.maxWidth),
                      child: Material(
                        color: selectedCategory == category
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: selectedCategory == category
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Semantics(
                                selected: selectedCategory == category,
                                child: InkWell(
                                  onTap: () => setState(() {
                                    selectedCategory = category;
                                    if (previewSnippetId == null &&
                                        !composerDirty) {
                                      draftCategory = category;
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      2,
                                      10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.folder_outlined,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            category,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '分类菜单 $category',
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 40),
                                maximumSize: const Size(32, 40),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.more_vert, size: 18),
                              onSelected: (action) =>
                                  run(() => manageCategory(category, action)),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('编辑')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => run(newCategory),
                  icon: Icon(Icons.create_new_folder_outlined),
                  label: Text('新建分类'),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => run(newComposer),
                icon: Icon(Icons.add),
                label: Text('新建命令'),
              ),
              for (final snippet in data.snippets.where(
                (s) => s.category == selectedCategory,
              ))
                catalogReorderItem(
                  false,
                  snippet.id,
                  snippet.name,
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 300),
                    child: Material(
                      color: previewSnippetId == snippet.id
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
                                minimumSize: const Size(0, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () =>
                                  run(() => sendCatalogSnippet(snippet)),
                              child: Text(
                                snippet.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '预览和编辑 ${snippet.name}',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 40),
                              maximumSize: const Size(32, 40),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            onPressed: () => run(() => selectComposer(snippet)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget snippetsPanel() => LayoutBuilder(
    builder: (context, bounds) {
      final desktop =
          MediaQuery.sizeOf(context).width >= 760 && bounds.maxWidth >= 500;
      if (desktop) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: commandCatalog()),
            VerticalDivider(width: 1),
            SizedBox(
              width: (bounds.maxWidth * .32).clamp(300.0, 360.0),
              child: commandComposer(),
            ),
          ],
        );
      }
      if (MediaQuery.viewInsetsOf(context).bottom > 0) return commandComposer();
      final height = (bounds.maxHeight * .32).clamp(220.0, 240.0);
      if (bounds.maxHeight < 310) return commandComposer();
      return Column(
        children: [
          Expanded(child: commandCatalog()),
          Divider(height: 1),
          SizedBox(height: height, child: commandComposer()),
        ],
      );
    },
  );
  Widget commandComposer() => LayoutBuilder(
    builder: (context, bounds) {
      Widget content() => Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppInput(
                    controller: composerName,
                    focusNode: composerNameFocus,
                    label: '命令名称',
                    hint: '保存时填写名称',
                    enabled: !composerSaving,
                    action: TextInputAction.next,
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('composer-$draftCategory'),
                    initialValue: data.categories.contains(draftCategory)
                        ? draftCategory
                        : data.categories.firstOrNull,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: '分类'),
                    hint: Text('请新建分类'),
                    items: data.categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: composerSaving
                        ? null
                        : (v) => setState(() => draftCategory = v!),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Expanded(
              child: CodeEditor(
                controller: command,
                label: '命令内容',
                hint: r'直接编写命令，空名称也可发送',
                enabled: !composerSaving,
                showHeader: false,
              ),
            ),
            if (composerError != null)
              Text(
                composerError!,
                maxLines: 2,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 11,
                ),
              ),
            if (sendFeedback != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Tooltip(
                  message: sendFeedback!,
                  child: Text(
                    sendFeedback!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: sendFailed
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Checkbox(
                    visualDensity: VisualDensity.compact,
                    value: draftAppendNewline,
                    onChanged: composerSaving
                        ? null
                        : (v) => setState(() => draftAppendNewline = v!),
                  ),
                  Text('末尾添加回车符', style: Theme.of(context).textTheme.bodySmall),
                  Spacer(),
                  if (previewSnippet != null)
                    IconButton(
                      tooltip: '删除命令',
                      constraints: BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: composerSaving
                          ? null
                          : () => run(deleteComposer),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: composerSaving ? null : () => run(saveComposer),
                    icon: Icon(Icons.save_outlined, size: 18),
                    label: Text(composerSaving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: command,
              builder: (context, value, _) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilledButton(
                      onPressed:
                          composerSaving ||
                              commandSending ||
                              value.text.trim().isEmpty
                          ? null
                          : () => run(
                              () => sendText(
                                command.text,
                                direct: true,
                                appendNewline: draftAppendNewline,
                                expandParameters: previewSnippetId != null,
                              ),
                            ),
                      child: Text('发送'),
                    ),
                    SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed:
                          composerSaving ||
                              commandSending ||
                              value.text.trim().isEmpty
                          ? null
                          : () => run(
                              () => sendText(
                                command.text,
                                all: true,
                                appendNewline: draftAppendNewline,
                                expandParameters: previewSnippetId != null,
                              ),
                            ),
                      child: Text('发送全部窗口'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      if (bounds.maxHeight < 200) {
        return SingleChildScrollView(
          child: SizedBox(height: 260, child: content()),
        );
      }
      return content();
    },
  );

  void showSendFeedback(String value, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      sendFeedback = value;
      sendFailed = error;
    });
  }

  Future<void> sendText(
    String body, {
    bool direct = false,
    bool all = false,
    bool appendNewline = true,
    bool expandParameters = true,
  }) async {
    if (commandSending) return;
    setState(() => commandSending = true);
    try {
      await performCommandSend(
        body,
        direct: direct,
        all: all,
        appendNewline: appendNewline,
        expandParameters: expandParameters,
      );
    } catch (e) {
      showSendFeedback('$e'.replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => commandSending = false);
    }
  }

  Future<void> performCommandSend(
    String body, {
    bool direct = false,
    bool all = false,
    bool appendNewline = true,
    bool expandParameters = true,
  }) async {
    final targets = all
        ? sessions.where((s) => s.status == '已连接').toList()
        : [if (current?.status == '已连接') current!];
    if (targets.isEmpty) throw StateError('请先连接服务器');
    var text = body;
    if (text.trim().isEmpty) throw StateError('请输入命令内容');
    showSendFeedback('准备发送到 ${targets.map((s) => s.host.name).join('、')}');
    if (expandParameters) {
      for (final v in RegExp(
        r'\$\{([^}]+)\}',
      ).allMatches(text).map((m) => m[1]!).toSet()) {
        final value = await input(
          '参数 $v',
          code: true,
          allowEmpty: true,
          helper: '值将原样替换，请按目标 shell 的规则转义。',
        );
        if (value == null) {
          showSendFeedback('已取消发送');
          return;
        }
        text = text.replaceAll('\${$v}', value);
      }
    }
    if ((all || !direct) &&
        !await confirm(
          all ? '发送到全部窗口（${targets.length}）' : '执行到 ${targets.first.host.name}',
          '${targets.map((s) => s.host.name).join('、')}\n\n$text\n\n${appendNewline ? '末尾自动添加回车' : '不自动添加回车'}',
          action: '发送',
        )) {
      showSendFeedback('已取消发送');
      return;
    }
    final failed = <String>[];
    for (final s in targets) {
      try {
        s.send(commandWireText(text, appendNewline: appendNewline));
      } catch (_) {
        failed.add(s.host.name);
      }
    }
    if (failed.isNotEmpty) throw StateError('发送失败：${failed.join('、')}，请检查连接');
    showSendFeedback(
      '已发送到 ${targets.map((s) => s.host.name).join('、')} · ${appendNewline ? '已附加回车' : '未附加回车'}',
    );
    if (mounted && MediaQuery.sizeOf(context).width < 760) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => mobilePage = 1);
    }
  }

  Future<void> appearanceMenu() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => Theme(
          data: buildAppTheme(data.themeColor, switch (data.themeMode) {
            'light' => Brightness.light,
            'dark' => Brightness.dark,
            _ => MediaQuery.platformBrightnessOf(c),
          }),
          child: AlertDialog(
            title: Text('外观与终端'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: data.themeMode,
                      decoration: InputDecoration(labelText: '应用主题'),
                      items: [
                        DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                        DropdownMenuItem(value: 'light', child: Text('浅色')),
                        DropdownMenuItem(value: 'dark', child: Text('深色')),
                      ],
                      onChanged: (v) => run(() async {
                        setState(() => data.themeMode = v!);
                        widget.onAppearanceChanged?.call(data);
                        update(() {});
                        await save();
                      }),
                    ),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: data.themeColor,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: '应用主题色'),
                      items: [
                        for (final e in brandNames.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 14,
                                  color: brandColors[e.key],
                                ),
                                SizedBox(width: 8),
                                Text(e.value),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => run(() async {
                        setState(() => data.themeColor = v!);
                        widget.onAppearanceChanged?.call(data);
                        update(() {});
                        await save();
                      }),
                    ),
                    SizedBox(height: 16),
                    Text('终端背景图片'),
                    Text('背景仅保存于当前设备，不随备份导出。图片上叠加遮罩以保证文字可读性。'),
                    Wrap(
                      children: [
                        TextButton.icon(
                          onPressed: () => run(() async {
                            final f = await FilePicker.pickFile(
                              type: FileType.image,
                            );
                            if (f == null) return;
                            if ((await f.length() ?? 0) > 10 * 1024 * 1024) {
                              throw StateError('请选择 10 MB 以内图片');
                            }
                            final bytes = await f.readAsBytes();
                            final codec = await PaintingBinding.instance
                                .instantiateImageCodecWithSize(
                                  await ImmutableBuffer.fromUint8List(bytes),
                                );
                            final frame = await codec.getNextFrame();
                            frame.image.dispose();
                            codec.dispose();
                            final target = File(
                              '${widget.store.directory.path}/terminal-background',
                            );
                            await target.writeAsBytes(bytes, flush: true);
                            await FileImage(target).evict();
                            if (mounted) {
                              setState(() => backgroundPath = target.path);
                            }
                            update(() {});
                          }),
                          icon: Icon(Icons.image_outlined),
                          label: Text('选择背景图片'),
                        ),
                        TextButton(
                          onPressed: backgroundPath == null
                              ? null
                              : () => run(() async {
                                  await File(backgroundPath!).delete();
                                  if (mounted) {
                                    setState(() => backgroundPath = null);
                                  }
                                  update(() {});
                                }),
                          child: Text('移除背景'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: Text('完成')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> copyTerminal(Connection s) async {
    final selection = terminalControllers[s]?.selection;
    if (selection == null) {
      message('请先拖动选择终端文字');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: s.terminal.buffer.getText(selection)),
    );
  }

  Future<void> pasteTerminal(Connection s) async {
    if (s.status != '已连接') throw StateError('请先连接服务器');
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return;
    if ((text.contains('\n') || text.contains('\r') || text.contains('\x1b')) &&
        !await confirm(
          '粘贴到 ${s.host.name}',
          '粘贴包含换行或控制字符，可能执行命令：\n\n$text',
          action: '粘贴',
        )) {
      return;
    }
    s.terminal.paste(text);
  }

  Widget terminalView(Connection s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = TerminalThemes.defaultTheme;
    final palette =
        Theme.of(context).extension<CodePalette>() ??
        CodePalette.named('classic', dark);
    final foreground = palette.foreground;
    final theme = TerminalTheme(
      cursor: foreground,
      selection: Theme.of(context).colorScheme.primary.withValues(alpha: .3),
      foreground: foreground,
      background: palette.background,
      black: base.black,
      white: palette.foreground,
      red: dark ? Color(0xffff8b8b) : Color(0xffb4232d),
      green: palette.string,
      yellow: palette.keyword,
      blue: dark ? Color(0xff82baff) : Color(0xff175cad),
      magenta: palette.variable,
      cyan: palette.comment,
      brightBlack: base.brightBlack,
      brightRed: dark ? Color(0xffffaaaa) : Color(0xffc42c38),
      brightGreen: palette.string,
      brightYellow: palette.keyword,
      brightBlue: dark ? Color(0xffafd4ff) : Color(0xff266cc0),
      brightMagenta: palette.variable,
      brightCyan: palette.comment,
      brightWhite: palette.foreground,
      searchHitBackground: base.searchHitBackground,
      searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
      searchHitForeground: base.searchHitForeground,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backgroundPath != null)
          Image.file(
            File(backgroundPath!),
            fit: BoxFit.cover,
            cacheWidth: 1920,
            errorBuilder: (_, _, _) => SizedBox.shrink(),
          ),
        TerminalView(
          s.terminal,
          controller: terminalControllers[s],
          keyboardAppearance: dark ? Brightness.dark : Brightness.light,
          onKeyEvent: (node, event) {
            final keyboard = HardwareKeyboard.instance;
            final apple =
                defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.iOS;
            final modifier = apple
                ? keyboard.isMetaPressed
                : keyboard.isControlPressed;
            if (event is KeyDownEvent &&
                modifier &&
                event.logicalKey == LogicalKeyboardKey.keyV) {
              run(() => pasteTerminal(s));
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                modifier &&
                event.logicalKey == LogicalKeyboardKey.keyC &&
                (apple || keyboard.isShiftPressed)) {
              run(() => copyTerminal(s));
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          theme: theme,
          backgroundOpacity: backgroundPath == null ? 1 : .85,
          padding: EdgeInsets.all(12),
          onSecondaryTapUp: (details, offset) async {
            final action = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                0,
                0,
              ),
              items: [
                PopupMenuItem(value: 'copy', child: Text('复制选中文字')),
                PopupMenuItem(value: 'paste', child: Text('粘贴')),
              ],
            );
            if (action == 'copy') await run(() => copyTerminal(s));
            if (action == 'paste') await run(() => pasteTerminal(s));
          },
        ),
      ],
    );
  }

  Future<void> layoutMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in ['终端优先', '文件优先', '恢复默认'])
              ListTile(title: Text(name), onTap: () => Navigator.pop(c, name)),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() {
      data.sidebar = 250;
      data.terminalRatio = choice == '终端优先'
          ? .78
          : choice == '文件优先'
          ? .35
          : .6;
    });
    await save();
  }

  Future<void> backupMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '加密备份 · Apple 设备可在文件选择器中选择 iCloud Drive\n自动 iCloud 备份尚未启用',
                textAlign: TextAlign.center,
              ),
            ),
            for (final item in {
              'export': '导出加密备份',
              'import': '导入备份',
              'recovery': '恢复上一次导入前的数据',
            }.entries)
              ListTile(
                title: Text(item.value),
                onTap: () => Navigator.pop(c, item.key),
              ),
          ],
        ),
      ),
    );
    if (choice != null) {
      await run(() async {
        if (choice == 'export') {
          await exportBackup();
        } else if (choice == 'import') {
          await importBackup();
        } else {
          await restoreRecovery();
        }
      });
    }
  }

  Future<void> exportBackup() async {
    if (busy) return;
    final password = await input(
      '设置备份密码',
      secret: true,
      helper: '至少 10 个字符，丢失后无法恢复。',
      validator: (v) => (v?.length ?? 0) < 10 ? '密码至少需要 10 个字符' : null,
    );
    if (password == null) return;
    final repeat = await input(
      '再次输入备份密码',
      secret: true,
      validator: (v) => v != password ? '两次密码不一致' : null,
    );
    if (repeat == null) return;
    if (password != repeat) throw StateError('两次密码不一致');
    final include = await confirm(
      '包含登录凭据？',
      '选择包含将把密码和私钥放入加密备份。取消则仅导出主机、命令和设置。',
      action: '包含凭据',
    );
    setState(() => busy = true);
    try {
      final request = {
        'data': data.toJson(),
        'password': password,
        'credentials': include
            ? await widget.store.credentials(data)
            : <String, String>{},
      };
      final bytes = await compute(encodeBackupWorker, request);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final saved = await FilePicker.saveFile(
        dialogTitle: '导出加密备份（可选择 iCloud Drive）',
        fileName: 'FastCat-$timestamp.fastcatbackup',
        bytes: bytes,
      );
      if (saved != null) {
        final digest = await backupFingerprint(bytes);
        message('备份已导出，文件指纹：${digest.substring(0, 16)}');
      } else {
        message('已取消导出');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importBackup() async {
    if (busy) return;
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final f = picked;
    if ((await f.length() ?? 0) > 25 * 1024 * 1024) throw StateError('备份文件过大');
    final bytes = await f.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) throw StateError('备份文件过大');
    if (!mounted) return;
    final payload = await showDialog<BackupPayload>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BackupImportDialog(filename: f.name, bytes: bytes),
    );
    if (payload == null || !mounted) return;
    setState(() => busy = true);
    try {
      final mode = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('导入预览'),
          content: Text(
            '${payload.data.hosts.length} 台服务器\n${payload.data.snippets.length} 条命令\n${payload.credentials.length} 份凭据\n\n合并时同 ID 保留本地资料与凭据。\n替换前保存本地恢复点，所有会话将关闭。',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(c, 'replace'),
              child: Text('替换'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'merge'),
              child: Text('合并'),
            ),
          ],
        ),
      );
      if (mode == null) return;
      await applyImport(payload, mode == 'replace');
      message('备份导入完成');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> applyImport(BackupPayload p, bool replace) async {
    final original = data.copy(), creds = await widget.store.credentials(data);
    await widget.store.recovery(original, creds);
    final existing = data.hosts.map((h) => h.id).toSet();
    final next = replace ? p.data.copy() : data.copy()
      ..merge(p.data);
    try {
      for (final e in p.credentials.entries) {
        if (replace || !existing.contains(e.key)) {
          await widget.store.setCredential(e.key, e.value);
        }
      }
      if (replace) {
        for (final id in existing) {
          if (!p.credentials.containsKey(id)) {
            await widget.store.deleteCredential(id);
          }
        }
      }
      await widget.store.save(next);
    } catch (_) {
      for (final h in next.hosts) {
        await widget.store.deleteCredential(h.id);
      }
      for (final e in creds.entries) {
        await widget.store.setCredential(e.key, e.value);
      }
      await widget.store.save(original);
      rethrow;
    }
    while (sessions.isNotEmpty) {
      close(0);
    }
    setState(() {
      data = next;
      selectedCategory = data.categories.firstOrNull ?? '';
      previewSnippetId = null;
      command.clear();
      composerName.clear();
      draftCategory = selectedCategory;
      draftAppendNewline = true;
      composerError = null;
    });
    widget.onAppearanceChanged?.call(data);
  }

  Future<void> restoreRecovery() async {
    final p = await widget.store.readRecovery();
    if (p == null) throw StateError('暂无恢复点');
    if (!await confirm('恢复本地数据', '将替换当前配置并关闭所有会话，是否继续？')) return;
    await applyImport(
      BackupPayload(
        AppData.fromJson(Map<String, dynamic>.from(p['data'])),
        Map<String, String>.from(p['credentials']),
      ),
      true,
    );
    message('已恢复');
  }

  @override
  Widget build(BuildContext context) {
    if (loadError != null) {
      return Scaffold(
        body: Center(child: SelectableText('本地数据无法读取，未覆盖原文件。\n$loadError')),
      );
    }
    if (!loaded) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
          ? NavigationBar(
              selectedIndex: mobilePage,
              onDestinationSelected: (i) => setState(() => mobilePage = i),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.dns_outlined),
                  label: '服务器',
                ),
                NavigationDestination(icon: Icon(Icons.terminal), label: '终端'),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  label: '工具',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (busy) LinearProgressIndicator(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  if (bounds.maxWidth < 760) {
                    return mobilePage == 0
                        ? sidebar()
                        : mobilePage == 1
                        ? terminalPanel()
                        : mobilePage == 2
                        ? tools()
                        : settingsPage();
                  }
                  return Row(
                    children: [
                      SizedBox(width: data.sidebar, child: sidebar()),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(
                            () => data.sidebar = (data.sidebar + d.delta.dx)
                                .clamp(200, 400),
                          ),
                          onHorizontalDragEnd: (_) => run(save),
                          child: Container(
                            width: 5,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, b) {
                            final top = ((b.maxHeight - 5) * data.terminalRatio)
                                .clamp(
                                  sessions.isEmpty ? 100.0 : 220.0,
                                  (b.maxHeight - (tool == 1 ? 300 : 210)).clamp(
                                    sessions.isEmpty ? 100.0 : 220.0,
                                    double.infinity,
                                  ),
                                );
                            return Column(
                              children: [
                                SizedBox(height: top, child: terminalPanel()),
                                MouseRegion(
                                  cursor: SystemMouseCursors.resizeRow,
                                  child: GestureDetector(
                                    onVerticalDragUpdate: (d) => setState(
                                      () => data.terminalRatio =
                                          (data.terminalRatio +
                                                  d.delta.dy / b.maxHeight)
                                              .clamp(.25, .85),
                                    ),
                                    onVerticalDragEnd: (_) => run(save),
                                    child: Container(
                                      height: 5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                Expanded(child: tools()),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
