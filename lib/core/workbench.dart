import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'document.dart';

const sampleData = '''{
  "request_id": "jlens_demo_001",
  "success": true,
  "data": {
    "station": "上海 · 生鲜精选",
    "products": [
      {"id": 9007199254740993, "name": "阳光玫瑰葡萄", "price": 29.9, "stock": 128, "tags": ["当季", "直采"], "remark": null},
      {"id": 9007199254740994, "name": "新疆阿克苏苹果", "price": 18.8, "stock": 86, "tags": ["脆甜"], "remark": ""},
      {"id": 9007199254740995, "name": "海南金煌芒", "price": 35.5, "stock": 42, "tags": ["热带水果"]}
    ],
    "pagination": {"page": 1, "total": 3, "has_more": false}
  }
}''';

enum LensView { tree, table, source }

abstract interface class HistoryStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class LocalHistoryStorage implements HistoryStorage {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'jlens.history.v1';
  @override
  Future<String?> read() => _preferences.getString(_key);
  @override
  Future<void> write(String value) => _preferences.setString(_key, value);
}

class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.raw,
    required this.title,
    required this.visited,
    this.view = LensView.tree,
    this.selected = r'$',
    this.focus = r'$',
    Set<String>? expanded,
  }) : expanded = expanded ?? {r'$'};
  final String id;
  final String raw;
  late final int byteLength = utf8.encode(raw).length;
  String title;
  DateTime visited;
  LensView view;
  String selected;
  String focus;
  Set<String> expanded;
  Map<String, Object> toMap() => {
    'id': id,
    'raw': raw,
    'title': title,
    'visited': visited.toIso8601String(),
    'view': view.name,
    'selected': selected,
    'focus': focus,
    'expanded': expanded.toList(),
  };
  factory HistoryEntry.fromMap(Map<String, Object?> map) => HistoryEntry(
    id: map['id'] as String,
    raw: map['raw'] as String,
    title: map['title'] as String,
    visited: DateTime.parse(map['visited'] as String),
    view: LensView.values.byName(map['view'] as String),
    selected: map['selected'] as String,
    focus: map['focus'] as String,
    expanded: (map['expanded'] as List<Object?>).cast<String>().toSet(),
  );
}

class Workbench extends ChangeNotifier {
  Workbench(this.storage);
  final HistoryStorage storage;
  final _browseChanges = ChangeNotifier();
  Listenable get browseChanges => _browseChanges;
  int treeRevision = 0;
  // 仅单个节点切换可局部更新；批量展开、定位和聚焦仍重建可见行。
  String? treeTogglePath;
  DataDocument? document;
  String draft = '';
  DataParseException? parseError;
  String? storageError;
  bool ready = false;
  bool _disposed = false;
  bool _storageReadable = true;
  LensView view = LensView.tree;
  String selectedPath = r'$';
  String focusPath = r'$';
  Set<String> expanded = {r'$'};
  List<HistoryEntry> history = [];
  String? currentId;
  Future<void> _pendingWrite = Future.value();
  bool _writing = false;
  bool _writeRequested = false;
  Timer? _saveTimer;
  DataNode? get selected => document?.nodes[selectedPath];
  DataNode? get focused => document?.nodes[focusPath];
  bool get dirty =>
      document == null ? draft.isNotEmpty : draft != document!.raw;

  Future<void> initialize() async {
    try {
      final saved = await storage.read();
      if (saved != null) {
        final entries = jsonDecode(saved) as List<Object?>;
        final loaded = entries
            .map((e) => HistoryEntry.fromMap(e as Map<String, Object?>))
            .toList();
        for (final entry in loaded) {
          final parsed = DataDocument.parse(entry.raw);
          if (!parsed.nodes.containsKey(entry.selected) ||
              !parsed.nodes.containsKey(entry.focus) ||
              entry.expanded.any((path) => !parsed.nodes.containsKey(path))) {
            throw const FormatException('历史中的节点路径与原文不匹配');
          }
        }
        history = loaded;
      }
    } catch (error) {
      _storageReadable = false;
      storageError = '历史读取失败，原存储未覆盖：$error';
    }
    if (_disposed) return;
    if (history.isNotEmpty) {
      _restore(history.first);
    } else {
      draft = sampleData;
      document = DataDocument.parse(sampleData);
      expanded = {r'$', r'$.data', r'$.data.products'};
    }
    ready = true;
    notifyListeners();
  }

  void edit(String value) {
    draft = value;
    parseError = null;
    notifyListeners();
  }

  bool parse() {
    try {
      final next = DataDocument.parse(draft);
      _capture();
      final existing = history.where((entry) => entry.raw == draft).firstOrNull;
      document = next;
      parseError = null;
      selectedPath = r'$';
      focusPath = r'$';
      expanded = {r'$'};
      final summary = next.root.children.isEmpty
          ? next.root.preview
          : next.root.children.take(3).map((n) => n.label).join(' · ');
      final entry =
          existing ??
          HistoryEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            raw: draft,
            title: String.fromCharCodes(summary.runes.take(60)),
            visited: DateTime.now(),
            view: view,
          );
      if (existing != null) {
        view = entry.view;
        selectedPath = entry.selected;
        focusPath = entry.focus;
        expanded = {...entry.expanded};
      }
      entry.visited = DateTime.now();
      history.remove(entry);
      history.insert(0, entry);
      currentId = entry.id;
      _capture();
      _trim();
      persist();
      notifyListeners();
      return true;
    } on DataParseException catch (error) {
      parseError = error;
      notifyListeners();
      return false;
    }
  }

  void _trim() {
    var size = 0;
    history = history
        .where((e) {
          size += e.byteLength;
          return size <= 5 * 1024 * 1024;
        })
        .take(50)
        .toList();
  }

  void _restore(HistoryEntry entry) {
    document = DataDocument.parse(entry.raw);
    draft = entry.raw;
    currentId = entry.id;
    view = entry.view;
    selectedPath = entry.selected;
    focusPath = entry.focus;
    expanded = {...entry.expanded};
    parseError = null;
  }

  void restore(HistoryEntry entry) {
    _capture();
    _restore(entry);
    entry.visited = DateTime.now();
    history.remove(entry);
    history.insert(0, entry);
    persist();
    notifyListeners();
  }

  void _capture() {
    final entry = history.where((e) => e.id == currentId).firstOrNull;
    if (entry == null) return;
    entry.view = view;
    entry.selected = selectedPath;
    entry.focus = focusPath;
    entry.expanded = {...expanded};
  }

  void _changed({bool viewChanged = false}) {
    // 浏览状态在落盘或离开文档时捕获，连续点击不反复复制展开节点。
    _saveTimer?.cancel();
    if (currentId != null) {
      _saveTimer = Timer(const Duration(milliseconds: 250), persist);
    }
    if (viewChanged) {
      notifyListeners();
    } else {
      _browseChanges.notifyListeners();
    }
  }

  void select(String path) {
    final previousPath = selectedPath;
    final previousFocus = focusPath;
    final expandedCount = expanded.length;
    selectedPath = path;
    var parent = document!.parents[path];
    while (parent != null) {
      expanded.add(parent);
      parent = document!.parents[parent];
    }
    if (!path.startsWith('$focusPath.') &&
        !path.startsWith('$focusPath[') &&
        path != focusPath) {
      focusPath = r'$';
    }
    if (expanded.length != expandedCount) {
      treeTogglePath = null;
      treeRevision++;
    }
    if (path != previousPath ||
        focusPath != previousFocus ||
        expanded.length != expandedCount) {
      _changed();
    }
  }

  void setView(LensView value) {
    if (view == value) return;
    view = value;
    _changed(viewChanged: true);
  }

  void focus(String path) {
    focusPath = path;
    selectedPath = path;
    if (expanded.add(path)) {
      treeTogglePath = null;
      treeRevision++;
    }
    _changed();
  }

  void toggle(String path) {
    if (!expanded.remove(path)) expanded.add(path);
    treeTogglePath = path;
    treeRevision++;
    _changed();
  }

  void expandAll(bool expand) {
    expanded = expand
        ? document!.nodes.values
              .where((n) => n.isContainer)
              .map((n) => n.path)
              .toSet()
        : <String>{};
    treeTogglePath = null;
    treeRevision++;
    _changed();
  }

  void rename(HistoryEntry entry, String title) {
    entry.title = title;
    persist();
    notifyListeners();
  }

  void delete(HistoryEntry entry) {
    history.remove(entry);
    if (currentId == entry.id) currentId = null;
    persist();
    notifyListeners();
  }

  void clearHistory() {
    history.clear();
    currentId = null;
    _storageReadable = true;
    persist();
    notifyListeners();
  }

  void newDocument() {
    _capture();
    persist();
    document = null;
    draft = '';
    currentId = null;
    parseError = null;
    selectedPath = r'$';
    focusPath = r'$';
    expanded = {r'$'};
    view = LensView.source;
    notifyListeners();
  }

  void persist() {
    _saveTimer?.cancel();
    if (!_storageReadable) return;
    _writeRequested = true;
    if (_writing) return;
    _writing = true;
    _pendingWrite = Future<void>.microtask(_drainWrites);
  }

  Future<void> _drainWrites() async {
    // 写入期间的多次变动合并到下一次快照，避免排队序列化整份历史。
    while (_writeRequested) {
      _writeRequested = false;
      _capture();
      final payload = jsonEncode(history.map((e) => e.toMap()).toList());
      final previousError = storageError;
      try {
        await storage.write(payload);
        storageError = null;
      } catch (error) {
        storageError = '历史保存失败，请检查本地存储空间：$error';
      }
      if (!_disposed && previousError != storageError) notifyListeners();
    }
    _writing = false;
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _capture();
    persist();
    await _pendingWrite;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _disposed = true;
    _browseChanges.dispose();
    super.dispose();
  }
}
