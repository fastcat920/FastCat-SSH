import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/backup.dart';
import 'password_field.dart';

class BackupImportDialog extends StatefulWidget {
  final String filename;
  final Uint8List bytes;
  const BackupImportDialog({
    super.key,
    required this.filename,
    required this.bytes,
  });
  @override
  State<BackupImportDialog> createState() => _BackupImportDialogState();
}

class _BackupImportDialogState extends State<BackupImportDialog> {
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  late final fingerprint = backupFingerprint(widget.bytes);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> decrypt() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payload = await compute(decodeBackupWorker, {
        'bytes': widget.bytes,
        'password': password.text,
      });
      if (mounted) {
        setState(() => busy = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, payload);
      }
    } on BackupAuthenticationException catch (e) {
      if (mounted) setState(() => error = e.toString());
    } on BackupIntegrityException catch (e) {
      if (mounted) setState(() => error = e.toString());
    } on FormatException {
      if (mounted) {
        setState(() => error = '备份格式无效或文件未完整下载，请重新选择原始 .fastcatbackup 文件。');
      }
    } on TypeError {
      if (mounted) setState(() => error = '备份字段无效，请重新导出或选择完整的备份文件。');
    } catch (_) {
      if (mounted) setState(() => error = '无法读取备份，请重新选择文件后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('解密备份'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.filename,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('${widget.bytes.length} 字节'),
                FutureBuilder<String>(
                  future: fingerprint,
                  builder: (_, snapshot) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SelectableText(
                      '文件指纹 SHA-256：${snapshot.data?.substring(0, 16) ?? '计算中…'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                PasswordField(
                  controller: password,
                  label: '备份密码',
                  autofocus: true,
                  enabled: !busy,
                  helper: '填写导出这份文件时设置的密码，与系统解锁和服务器密码无关。密码前后空格也会参与校验。',
                  validator: (v) => v == null || v.isEmpty ? '请输入备份密码' : null,
                  onSubmitted: (_) => decrypt(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text('解密成功并确认导入前，不会更改本地数据。'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : decrypt,
          child: Text(
            busy
                ? '正在解密…'
                : error == null
                ? '解密并预览'
                : '重新解密',
          ),
        ),
      ],
    ),
  );
}
