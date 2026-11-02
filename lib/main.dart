import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/document.dart';
import 'core/workbench.dart';
import 'ui/source_editor.dart';
import 'ui/search_results.dart';
import 'ui/table_view.dart';
import 'ui/theme.dart';
import 'ui/tree_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(JLensApp(storage: LocalHistoryStorage()));
}

class JLensApp extends StatelessWidget {
  const JLensApp({super.key, required this.storage});
  final HistoryStorage storage;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JLens · JSON 透镜',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: WorkbenchScreen(storage: storage),
  );
}

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key, required this.storage});
  final HistoryStorage storage;
  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen>
    with WidgetsBindingObserver {
  late final Workbench model = Workbench(widget.storage);
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: '搜索');
  String _searchMode = '全部';
  String _searchText = '';
  DataNode? _previewNode;
  String _previewText = '';
  String _historyQuery = '';
  bool _details = true;
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.addListener(_refresh);
    _search.addListener(_refreshSearch);
    unawaited(model.initialize());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _refreshSearch() {
    if (_searchText == _search.text) return;
    setState(() => _searchText = _search.text);
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
  }

  Widget _browseRegion(Widget Function() builder) => ListenableBuilder(
    listenable: model.browseChanges,
    builder: (context, child) => RepaintBoundary(child: builder()),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(model.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_refresh);
    unawaited(model.flush());
    model.dispose();
    _search.removeListener(_refreshSearch);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _copy(String value, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _toast('已复制$label');
    } catch (error) {
      _toast('复制失败：$error');
    }
  }

  void _parse() {
    _search.clear();
    if (!model.parse()) model.setView(LensView.source);
  }

  Future<bool> _leaveDraft() async {
    if (!model.dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('替换尚未解析的输入？'),
            content: const Text('当前输入尚未保存到历史。替换后，这部分修改将丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留输入'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('替换'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _newDocument() async {
    if (!await _leaveDraft() || !mounted) return;
    _search.clear();
    model.newDocument();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || data?.text == null || data!.text!.isEmpty) {
        _toast('剪贴板中没有文本');
        return;
      }
      if (!await _leaveDraft() || !mounted) return;
      _search.clear();
      model.newDocument();
      model.edit(data.text!);
      _parse();
    } catch (error) {
      _toast('无法读取剪贴板，请在源码区直接粘贴：$error');
    }
  }

  Future<void> _restore(HistoryEntry entry) async {
    if (!await _leaveDraft() || !mounted) return;
    _search.clear();
    model.restore(entry);
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
  }

  Future<void> _rename(HistoryEntry entry) async {
    final input = TextEditingController(text: entry.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('命名历史记录'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 等弹窗退出动画结束后再释放仍被 TextField 引用的控制器。
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (mounted && title != null && title.trim().isNotEmpty) {
      model.rename(entry, title.trim());
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空本地历史？'),
        content: const Text('所有历史记录将被删除，当前打开的数据仍可继续浏览。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空历史'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) model.clearHistory();
  }

  void _format(bool pretty) {
    try {
      final parsed = DataDocument.parse(model.draft);
      model.edit(parsed.root.toJson(pretty: pretty));
      _parse();
      model.setView(LensView.source);
    } on DataParseException {
      _parse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final inspector = MediaQuery.sizeOf(context).width >= 1320 && _details;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _parse,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _parse,
      },
      child: Scaffold(
        key: _scaffold,
        drawer: wide ? null : Drawer(backgroundColor: panel, child: _sidebar()),
        body: SafeArea(
          child: !model.ready
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    if (wide)
                      SizedBox(
                        width: 236,
                        child: RepaintBoundary(child: _sidebar()),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          _header(wide),
                          if (model.storageError != null)
                            _notice(
                              model.storageError!,
                              Icons.warning_amber,
                              const Color(0xffffce84),
                            ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                wide ? 26 : 12,
                                0,
                                wide ? 26 : 12,
                                16,
                              ),
                              child: Column(
                                children: [
                                  _toolbar(),
                                  const SizedBox(height: 18),
                                  if (model.parseError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _notice(
                                        model.parseError.toString(),
                                        Icons.error_outline,
                                        const Color(0xfff49cae),
                                      ),
                                    ),
                                  if (model.dirty &&
                                      model.document != null &&
                                      (model.view != LensView.source ||
                                          _search.text.isNotEmpty))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _notice(
                                        '输入已修改。下方仍为上次解析结果，请点击「解析数据」更新。',
                                        Icons.edit_note,
                                        const Color(0xffffce84),
                                      ),
                                    ),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: canvas,
                                              border: Border.all(color: line),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: Column(
                                              children: [
                                                _tabs(inspector),
                                                const Divider(height: 1),
                                                if (model.document != null &&
                                                    model.view !=
                                                        LensView.source)
                                                  _browseRegion(_breadcrumb),
                                                Expanded(
                                                  child: _browseRegion(
                                                    _content,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (inspector &&
                                            model.selected != null) ...[
                                          const SizedBox(width: 16),
                                          SizedBox(
                                            width: 272,
                                            child: _browseRegion(_inspector),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _browseRegion(_statusBar),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 28 : 8, 22, 24, 20),
    child: Row(
      children: [
        if (!wide)
          IconButton(
            onPressed: () => _scaffold.currentState!.openDrawer(),
            icon: const Icon(Icons.menu),
            tooltip: '打开历史',
          ),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '数据工作台',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .5,
                ),
              ),
              SizedBox(height: 6),
              Text('透过结构，看清数据。', style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        if (wide)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 13, color: mint),
                SizedBox(width: 6),
                Text('本地处理', style: TextStyle(color: muted, fontSize: 11)),
              ],
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _help,
          icon: const Icon(Icons.help_outline, size: 20, color: muted),
          tooltip: '使用说明',
        ),
      ],
    ),
  );

  Widget _toolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextField(
        key: const Key('search-input'),
        controller: _search,
        focusNode: _searchFocus,
        decoration: InputDecoration(
          hintText: '查找字段、值或路径…',
          prefixIcon: const Icon(Icons.search, size: 20, color: muted),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  onPressed: _search.clear,
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: '清除搜索',
                ),
        ),
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: _paste,
            icon: const Icon(Icons.content_paste, size: 16),
            label: const Text('粘贴'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            key: const Key('parse-button'),
            onPressed: _parse,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('解析数据'),
          ),
        ],
      );
      final mode = DropdownButton<String>(
        value: _searchMode,
        underline: const SizedBox(),
        style: const TextStyle(color: muted, fontSize: 12),
        items: ['全部', '字段', '值', '路径', '类型']
            .map((mode) => DropdownMenuItem(value: mode, child: Text(mode)))
            .toList(),
        onChanged: (value) => setState(() => _searchMode = value!),
      );
      if (constraints.maxWidth < 650) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                mode,
              ],
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 12),
          mode,
          const SizedBox(width: 18),
          actions,
        ],
      );
    },
  );

  Widget _tabs(bool inspector) => Container(
    color: panel,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Row(
      children: [
        for (final item in [
          (LensView.tree, Icons.account_tree_outlined, '树形'),
          (LensView.table, Icons.table_chart_outlined, '表格'),
          (LensView.source, Icons.code, '源码'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              key: Key('view-${item.$1.name}'),
              onPressed: () {
                _search.clear();
                model.setView(item.$1);
              },
              style: TextButton.styleFrom(
                foregroundColor: model.view == item.$1 && _search.text.isEmpty
                    ? mint
                    : muted,
                backgroundColor: model.view == item.$1 && _search.text.isEmpty
                    ? mint.withValues(alpha: .09)
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              icon: Icon(item.$2, size: 16),
              label: Text(item.$3, style: const TextStyle(fontSize: 12)),
            ),
          ),
        const Spacer(),
        if (model.view == LensView.source)
          PopupMenuButton<String>(
            tooltip: '源码工具',
            icon: const Icon(Icons.more_horiz, size: 20),
            onSelected: (value) => _format(value == '格式化'),
            itemBuilder: (_) => ['格式化', '压缩']
                .map((value) => PopupMenuItem(value: value, child: Text(value)))
                .toList(),
          ),
        if (model.selected != null)
          IconButton(
            tooltip: '节点详情',
            icon: Icon(
              Icons.vertical_split_outlined,
              size: 18,
              color: inspector ? mint : muted,
            ),
            onPressed: () {
              if (MediaQuery.sizeOf(context).width >= 1320) {
                setState(() => _details = !_details);
              } else {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * .7,
                    child: _browseRegion(_inspector),
                  ),
                );
              }
            },
          ),
      ],
    ),
  );

  Widget _breadcrumb() {
    final focus = model.focusPath;
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          IconButton(
            onPressed: focus == r'$'
                ? null
                : () => model.focus(model.document!.parents[focus]!),
            tooltip: '返回上级',
            icon: const Icon(Icons.arrow_upward, size: 16),
          ),
          TextButton(
            onPressed: () => model.focus(r'$'),
            child: const Text('根节点', style: TextStyle(fontSize: 11)),
          ),
          const Icon(Icons.chevron_right, color: muted, size: 14),
          Expanded(
            child: Text(
              focus,
              overflow: TextOverflow.ellipsis,
              style: codeStyle.copyWith(fontSize: 11, color: muted),
            ),
          ),
          Text(
            model.document!.format,
            style: const TextStyle(fontSize: 10, color: mint),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_search.text.isNotEmpty && model.document != null) {
      return SearchResults(
        document: model.document!,
        query: _search.text,
        mode: _searchMode,
        onSelect: (node) {
          _search.clear();
          _searchFocus.unfocus();
          model.select(node.path);
        },
      );
    }
    if (model.view == LensView.source || model.document == null) {
      return SourceEditor(
        raw: model.draft,
        onChanged: model.edit,
        selection: model.dirty ? null : model.selected,
        error: model.parseError,
        onParse: _parse,
        focusOnLocate: !_searchFocus.hasFocus,
      );
    }
    return switch (model.view) {
      LensView.tree => TreeView(model: model, onCopy: _copy),
      LensView.table => TableView(key: ValueKey(model.document), model: model),
      LensView.source => const SizedBox(),
    };
  }

  Widget _inspector() {
    final node = model.selected!;
    return Container(
      decoration: BoxDecoration(
        color: panel,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, size: 17, color: muted),
                SizedBox(width: 9),
                Text('节点详情', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 26),
            const Text('当前路径', style: TextStyle(color: muted, fontSize: 11)),
            const SizedBox(height: 10),
            SelectableText(node.path, style: codeStyle.copyWith(fontSize: 12)),
            const SizedBox(height: 16),
            Row(
              children: [
                TypeBadge(node.type),
                const Spacer(),
                Text(
                  '第 ${'\n'.allMatches(model.document!.raw.substring(0, node.start)).length + 1} 行',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 14),
            Text(
              node.isContainer ? '节点预览 · ${node.children.length} 项' : '值',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(7),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _preview(node),
                  style: codeStyle.copyWith(
                    fontSize: 12,
                    color: typeColor(node.type),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _copy(node.path, '路径'),
                icon: const Icon(Icons.link, size: 15),
                label: const Text('复制路径'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _copy(node.toJson(), '标准 JSON'),
                icon: const Icon(Icons.copy_outlined, size: 15),
                label: const Text('复制为 JSON'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _copy(
                  model.document!.raw.substring(node.start, node.end),
                  '原文',
                ),
                icon: const Icon(Icons.code, size: 15),
                label: const Text('复制原文'),
              ),
            ),
            if (node.isContainer) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    _search.clear();
                    model.focus(node.path);
                    model.setView(
                      node.kind == NodeKind.array
                          ? LensView.table
                          : LensView.tree,
                    );
                  },
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('聚焦此节点'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _preview(DataNode node) {
    if (!identical(_previewNode, node)) {
      _previewNode = node;
      _previewText = node.jsonPreview();
    }
    return _previewText;
  }

  Widget _sidebar() {
    final entries = model.history
        .where(
          (e) =>
              e.title.toLowerCase().contains(_historyQuery.toLowerCase()) ||
              e.raw.toLowerCase().contains(_historyQuery.toLowerCase()),
        )
        .toList();
    return Container(
      decoration: const BoxDecoration(
        color: panel,
        border: Border(right: BorderSide(color: line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 28, 20, 30),
            child: Row(
              children: [
                _Logo(),
                SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'JLens',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                    Text(
                      'JSON 透镜',
                      style: TextStyle(
                        fontSize: 10,
                        color: muted,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('new-document'),
                onPressed: _newDocument,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建数据'),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                const Icon(Icons.history, color: muted, size: 15),
                const SizedBox(width: 8),
                const Text(
                  '最近浏览',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${model.history.length}',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                PopupMenuButton<String>(
                  tooltip: '历史管理',
                  icon: const Icon(Icons.more_horiz, size: 16, color: muted),
                  onSelected: (_) => _clearHistory(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'clear', child: Text('清空历史')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              onChanged: (value) => setState(() => _historyQuery = value),
              decoration: const InputDecoration(
                hintText: '搜索历史…',
                prefixIcon: Icon(Icons.search, size: 16),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _historyQuery.isEmpty ? '解析一份数据，\n便会在此留下足迹。' : '没有匹配的历史',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.8,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index],
                          active = entry.id == model.currentId;
                      final stamp = entry.visited.toLocal();
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        child: Material(
                          color: active
                              ? mint.withValues(alpha: .08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(
                              left: 12,
                              right: 2,
                            ),
                            onTap: () => _restore(entry),
                            title: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: active ? mint : ink,
                              ),
                            ),
                            subtitle: Text(
                              '${stamp.month}/${stamp.day} ${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}  ·  ${(entry.byteLength / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: '记录操作',
                              icon: const Icon(
                                Icons.more_horiz,
                                size: 16,
                                color: muted,
                              ),
                              onSelected: (value) {
                                if (value == 'rename') {
                                  _rename(entry);
                                } else {
                                  model.delete(entry);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除记录'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    if (!await _leaveDraft() || !mounted) return;
                    _search.clear();
                    model.newDocument();
                    model.edit(sampleData);
                    model.setView(LensView.tree);
                    _parse();
                  },
                  icon: const Icon(Icons.data_object, size: 15),
                  label: const Text('打开示例数据', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 10),
                const Text(
                  '数据留在此设备。\n最近 50 条历史 · 总原文最多 5 MiB',
                  style: TextStyle(color: muted, fontSize: 10, height: 1.7),
                ),
                const SizedBox(height: 12),
                const Text(
                  'JLENS  /  0.1.0',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      color: panel,
      border: Border(top: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          size: 6,
          color: model.parseError != null ? const Color(0xfff49cae) : mint,
        ),
        const SizedBox(width: 8),
        Text(
          model.parseError != null
              ? '解析失败'
              : model.dirty
              ? '待解析'
              : '就绪',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            model.selectedPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: codeStyle.copyWith(fontSize: 10, color: muted),
          ),
        ),
        if (model.document != null)
          Text(
            '${model.document!.nodes.length} 个节点  ·  ${(model.document!.byteLength / 1024).toStringAsFixed(1)} KB',
            style: const TextStyle(color: muted, fontSize: 10),
          ),
      ],
    ),
  );
  Widget _notice(String message, IconData icon, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    color: color.withValues(alpha: .08),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    ),
  );
  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('看清数据的每一层'),
      content: const SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Text(
            '1. 粘贴 JSON 或 Python dict，点击「解析数据」。也可在源码区编辑，按 ⌘ / Ctrl + Enter 解析。\n\n'
            '2. 点击箭头或双击节点行内容可展开、折叠；上下键选节点，左右键展开折叠或进入子节点、返回父节点。右键或长按节点可复制路径、值或 JSON，容器还可聚焦。表格用于比较数组记录，可排序、筛选和选列；源码保留原文并高亮选中值。\n\n'
            '3. 按 ⌘ / Ctrl + F 搜索字段、值、路径或类型，命中内容高亮，点击结果即可定位。节点详情可复制路径、原文或标准 JSON，容器节点还可单独聚焦。\n\n'
            '4. 成功解析后保存历史。点击历史可恢复原文、视图、展开节点与选中路径。历史仅存本机，浏览器清除站点数据也会清除历史。\n\n'
            '输入上限为 2 MiB、50,000 个节点、128 层嵌套。Python 支持字符串键 dict、list、字符串、十进制数字、True / False / None；不执行表达式。',
            style: TextStyle(fontSize: 13, height: 1.7),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('开始探索'),
        ),
      ],
    ),
  );
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: mint.withValues(alpha: .09),
      border: Border.all(color: mint.withValues(alpha: .35)),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: mint, width: 1.4),
          ),
        ),
        const Text(
          '{ }',
          style: TextStyle(
            color: mint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
