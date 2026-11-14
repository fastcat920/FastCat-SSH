import 'dart:convert';

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class Host {
  final String id, name, address, username, group, os, directory;
  final int port;
  final String? jumpId;
  const Host({
    required this.id,
    required this.name,
    required this.address,
    required this.username,
    this.port = 22,
    this.group = '个人设备',
    this.os = 'Linux',
    this.directory = '.',
    this.jumpId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'username': username,
    'port': port,
    'group': group,
    'os': os,
    'directory': directory,
    'jumpId': jumpId,
  };
  factory Host.fromJson(Map<String, dynamic> j) {
    final port = j['port'] as int? ?? 22;
    if (port < 1 || port > 65535 || (j['address'] as String).trim().isEmpty) {
      throw const FormatException('无效服务器');
    }
    return Host(
      id: j['id'] as String,
      name: j['name'] as String,
      address: j['address'] as String,
      username: j['username'] as String,
      port: port,
      group: j['group'] as String? ?? '个人设备',
      os: j['os'] as String? ?? 'Linux',
      directory: j['directory'] as String? ?? '.',
      jumpId: j['jumpId'] as String?,
    );
  }
}

class Snippet {
  final String id, name, body, os, category;
  final bool directSend, appendNewline;
  const Snippet({
    required this.id,
    required this.name,
    required this.body,
    this.os = '通用',
    this.category = '默认分类',
    this.directSend = false,
    this.appendNewline = true,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'body': body,
    'category': category,
    'directSend': directSend,
    'appendNewline': appendNewline,
    'os': os,
  };
  factory Snippet.fromJson(Map<String, dynamic> j) => Snippet(
    id: j['id'] as String,
    name: j['name'] as String,
    body: j['body'] as String,
    os: j['os'] as String? ?? '通用',
    category: j['category'] as String? ?? '默认分类',
    directSend: j['directSend'] as bool? ?? false,
    appendNewline: j['appendNewline'] as bool? ?? true,
  );
}

class AppData {
  List<Host> hosts;
  List<Snippet> snippets;
  Map<String, List<String>> history, favorites;
  double sidebar, terminalRatio;
  String themeMode, terminalColor, themeColor, codeTheme;
  List<String> groups, collapsedGroups;
  List<String> categories;
  bool showTerminalInfo;

  AppData({
    List<Host>? hosts,
    List<Snippet>? snippets,
    Map<String, List<String>>? history,
    Map<String, List<String>>? favorites,
    this.showTerminalInfo = true,
    this.themeMode = 'system',
    this.themeColor = 'mint',
    this.codeTheme = 'classic',
    List<String>? groups,
    List<String>? collapsedGroups,
    this.terminalColor = 'default',
    List<String>? categories,
    this.sidebar = 250,
    this.terminalRatio = .60,
  }) : groups = {
         ...?groups,
         ...?hosts?.map((h) => h.group),
         if (groups == null) '个人设备',
       }.toList(),
       collapsedGroups = collapsedGroups ?? [],
       categories = categories ?? ['默认分类'],
       hosts = hosts ?? [],
       snippets = snippets ?? [],
       history = history ?? {},
       favorites = {
         'global': {...?(favorites?.values.expand((v) => v))}.toList(),
       };
  void visit(String id, String path) {
    final h = history.putIfAbsent('global', () => []);
    h.remove(path);
    h.insert(0, path);
    if (h.length > 100) h.removeRange(100, h.length);
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'themeMode': themeMode,
    'showTerminalInfo': showTerminalInfo,
    'themeColor': themeColor,
    'codeTheme': codeTheme,
    'groups': groups,
    'collapsedGroups': collapsedGroups,
    'terminalColor': terminalColor,
    'categories': categories,
    'hosts': hosts.map((h) => h.toJson()).toList(),
    'snippets': snippets.map((s) => s.toJson()).toList(),
    'history': history,
    'favorites': favorites,
    'sidebar': sidebar,
    'terminalRatio': terminalRatio,
  };
  factory AppData.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1) throw const FormatException('不支持的备份版本');
    Map<String, List<String>> paths(dynamic value) => (value as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, (v as List).cast<String>()),
    );
    return AppData(
      showTerminalInfo: j['showTerminalInfo'] as bool? ?? true,
      themeColor:
          ['mint', 'blue', 'amber', 'purple', 'rose'].contains(j['themeColor'])
          ? j['themeColor'] as String
          : 'mint',
      codeTheme: ['classic', 'ocean', 'dracula'].contains(j['codeTheme'])
          ? j['codeTheme'] as String
          : 'classic',
      groups: <String>{
        ...((j['groups'] as List?)?.cast<String>() ?? []),
        ...(j['hosts'] as List).map((h) => h['group'] as String? ?? '个人设备'),
        if (j['groups'] == null) '个人设备',
      }.toList(),
      collapsedGroups: (j['collapsedGroups'] as List?)?.cast<String>() ?? [],
      themeMode: ['system', 'light', 'dark'].contains(j['themeMode'])
          ? j['themeMode'] as String
          : 'system',
      terminalColor:
          [
            'default',
            'mint',
            'blue',
            'amber',
            'purple',
          ].contains(j['terminalColor'])
          ? j['terminalColor'] as String
          : 'default',
      categories: {
        ...((j['categories'] as List?)?.cast<String>() ?? ['默认分类']),
        ...(j['snippets'] as List).map(
          (e) => e['category'] as String? ?? '默认分类',
        ),
      }.toList(),
      hosts: (j['hosts'] as List)
          .map((e) => Host.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      snippets: (j['snippets'] as List)
          .map((e) => Snippet.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      history: {
        'global': paths(
          j['history'],
        ).values.expand((e) => e).toSet().take(100).toList(),
      },
      favorites: paths(j['favorites']),
      sidebar: (j['sidebar'] as num? ?? 250).toDouble().clamp(200, 400),
      terminalRatio: (j['terminalRatio'] as num? ?? .6).toDouble().clamp(
        .25,
        .85,
      ),
    );
  }
  AppData copy() => AppData.fromJson(jsonDecode(jsonEncode(toJson())));
  void merge(AppData other) {
    categories = {...categories, ...other.categories}.toList();
    groups = {
      ...groups,
      ...other.groups,
      ...other.hosts.map((h) => h.group),
    }.toList();
    final hs = {for (final h in hosts) h.id: h};
    for (final h in other.hosts) {
      hs.putIfAbsent(h.id, () => h);
    }
    hosts = hs.values.toList();
    final ss = {for (final s in snippets) s.id: s};
    for (final s in other.snippets) {
      ss.putIfAbsent(s.id, () => s);
    }
    snippets = ss.values.toList();
    for (final e in other.history.entries) {
      for (final p in e.value.reversed) {
        visit(e.key, p);
      }
    }
    favorites = {
      'global': {
        ...favorites.values.expand((v) => v),
        ...other.favorites.values.expand((v) => v),
      }.toList(),
    };
  }
}
