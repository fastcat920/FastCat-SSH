import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import '../core/models.dart';
import 'app_input.dart';
import 'password_field.dart';

class HostEditor extends StatefulWidget {
  final Host? host;
  final bool copying;
  final List<String> groups;
  final String? defaultGroup;
  final List<Host> hosts;
  final Map<String, dynamic> auth;
  final Future<void> Function(Host, Map<String, String>) onSave;
  const HostEditor({
    super.key,
    this.host,
    this.copying = false,
    this.groups = const [],
    this.defaultGroup,
    required this.hosts,
    required this.auth,
    required this.onSave,
  });
  @override
  State<HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends State<HostEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late String os;
  String? jump, error, keyError;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final h = widget.host;
    os = h?.os ?? 'Linux';
    jump = h?.jumpId;
    fields = {
      for (final e in {
        '名称': h?.name ?? '',
        '地址': h?.address ?? '',
        '端口': '${h?.port ?? 22}',
        '用户名': h?.username ?? 'root',
        '分组': h?.group ?? widget.defaultGroup ?? '个人设备',
        '默认目录': h?.directory ?? '.',
        '密码': widget.auth['password'] as String? ?? '',
        '私钥 PEM': widget.auth['key'] as String? ?? '',
        '私钥口令': widget.auth['passphrase'] as String? ?? '',
      }.entries)
        e.key: TextEditingController(text: e.value),
    };
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? requiredText(String? value) =>
      (value ?? '').trim().isEmpty ? '此项不能为空' : null;
  Widget field(
    String name, {
    String? hint,
    String? helper,
    bool code = false,
    FormFieldValidator<String>? validator,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) => AppInput(
    controller: fields[name]!,
    label: name,
    autofocus: name == '名称',
    hint: hint,
    helper: helper,
    code: code,
    enabled: !saving,
    validator: validator,
    keyboardType: keyboard,
    formatters: formatters,
    action: TextInputAction.next,
  );
  Future<void> submit() async {
    if (saving || !form.currentState!.validate()) return;
    if (fields['私钥 PEM']!.text.trim().isNotEmpty) {
      try {
        SSHKeyPair.fromPem(
          fields['私钥 PEM']!.text,
          fields['私钥口令']!.text.isEmpty ? null : fields['私钥口令']!.text,
        );
      } catch (_) {
        setState(() => keyError = '无法读取私钥，请检查 PEM 格式及私钥口令');
        return;
      }
    }
    setState(() {
      saving = true;
      error = null;
      keyError = null;
    });
    try {
      final h = Host(
        id: widget.host?.id ?? newId(),
        name: fields['名称']!.text.trim(),
        address: fields['地址']!.text.trim(),
        port: int.parse(fields['端口']!.text),
        username: fields['用户名']!.text.trim(),
        group: fields['分组']!.text.trim().isEmpty
            ? '个人设备'
            : fields['分组']!.text.trim(),
        directory: fields['默认目录']!.text.isEmpty ? '.' : fields['默认目录']!.text,
        os: os,
        jumpId: jump,
      );
      await widget.onSave(h, {
        'password': fields['密码']!.text,
        'key': fields['私钥 PEM']!.text,
        'passphrase': fields['私钥口令']!.text,
      });
      if (mounted) {
        setState(() => saving = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '保存失败，输入内容已保留。$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): submit,
    },
    child: PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(
          widget.copying
              ? '复制服务器'
              : widget.host == null
              ? '添加服务器'
              : '编辑服务器',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field('名称', hint: '例如：生产服务器', validator: requiredText),
                  const SizedBox(height: 14),
                  field(
                    '地址',
                    hint: 'IP 地址或域名，不包含 ssh://',
                    code: true,
                    keyboard: TextInputType.url,
                    validator: (v) {
                      if (requiredText(v) != null) return '请输入服务器地址';
                      if (RegExp(r'\s|/').hasMatch(v!.trim())) {
                        return '请输入 IP 或域名，不包含空格、协议和路径';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: field(
                          '端口',
                          hint: '22',
                          code: true,
                          keyboard: TextInputType.number,
                          validator: (v) {
                            final port = int.tryParse(v ?? '');
                            return port == null || port < 1 || port > 65535
                                ? '范围 1–65535'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: field(
                          '用户名',
                          hint: os == 'Windows' ? 'Administrator' : 'root',
                          code: true,
                          validator: requiredText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: fields['分组']!.text,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '分组'),
                    items: {...widget.groups, fields['分组']!.text}
                        .map(
                          (g) => DropdownMenuItem(
                            value: g,
                            child: Text(g, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: saving ? null : (v) => fields['分组']!.text = v!,
                  ),
                  const SizedBox(height: 14),
                  field('默认目录', hint: '留空使用登录目录', code: true),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: fields['密码']!,
                    label: '服务器密码',
                    helper: '使用私钥登录时可留空；密码中的空格将原样保留。',
                    enabled: !saving,
                    action: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: os,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '远程系统'),
                    items: ['Linux', 'Windows']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: saving ? null : (v) => setState(() => os = v!),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: jump ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '跳板机'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('直接连接')),
                      for (final h in widget.hosts.where(
                        (h) => h.id != widget.host?.id && h.jumpId == null,
                      ))
                        DropdownMenuItem(
                          value: h.id,
                          child: Text(h.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: saving ? null : (v) => jump = v == '' ? null : v,
                  ),
                  ExpansionTile(
                    title: const Text('私钥登录（可选）'),
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded:
                        fields['私钥 PEM']!.text.isNotEmpty || keyError != null,
                    children: [
                      AppInput(
                        controller: fields['私钥 PEM']!,
                        label: '私钥 PEM',
                        hint: '粘贴完整的 BEGIN / END 私钥内容',
                        code: true,
                        multiline: true,
                        enabled: !saving,
                        helper: keyError,
                      ),
                      const SizedBox(height: 14),
                      PasswordField(
                        controller: fields['私钥口令']!,
                        label: '私钥口令',
                        helper: '仅加密私钥需要填写。',
                        enabled: !saving,
                      ),
                    ],
                  ),
                  if (keyError != null)
                    Text(
                      keyError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: saving ? null : submit,
            child: Text(saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    ),
  );
}
