// Synthetic compatibility data only. Contains no real servers or credentials.
import 'dart:io';
import 'package:fastcat_ssh/core/models.dart';
import 'package:fastcat_ssh/core/backup.dart';
Future<void> main()async{
 final data=AppData(hosts:[const Host(id:'fixture-host',name:'跨端测试',address:'example.invalid',username:'fixture')],groups:['测试分组'],snippets:[const Snippet(id:'fixture-command',name:'测试命令',body:'echo hello')]);
 final bytes=await BackupCodec().encode(data,'Compatibility-only_测试 🔐 123',credentials:{'fixture-host':'synthetic-secret-only'});
 await File('test/fixtures/dart_v1.fastcatbackup').writeAsBytes(bytes);
}
