import 'package:flutter/material.dart';
import 'core/store.dart';
import 'core/models.dart';
import 'ui/workspace.dart';
import 'ui/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FastCatApp());
}

class FastCatApp extends StatefulWidget {
  const FastCatApp({super.key});
  @override
  State<FastCatApp> createState() => _FastCatAppState();
}

class _FastCatAppState extends State<FastCatApp> {
  ThemeMode mode = ThemeMode.system;
  String themeColor = 'mint';
  void appearance(AppData data) {
    final next = switch (data.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (mode != next || themeColor != data.themeColor) {
      setState(() {
        mode = next;
        themeColor = data.themeColor;
      });
    }
  }

  ThemeData theme(Brightness brightness) =>
      buildAppTheme(themeColor, brightness);
  late final store = Store();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FastCat SSH',
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    home: Workspace(store: store, onAppearanceChanged: appearance),
  );
}
