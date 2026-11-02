import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/document.dart';
import '../core/workbench.dart';
import 'theme.dart';

enum _NodeAction { focus, copyPath, copyValue, copyJson }

class TreeView extends StatefulWidget {
  const TreeView({super.key, required this.model, required this.onCopy});
  final Workbench model;
  final Future<void> Function(String value, String label) onCopy;
  @override
  State<TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<TreeView> {
  final _scroll = ScrollController();
  final _keyboardFocus = FocusNode(debugLabel: '树形导航');
  String? _lastSelected;
  DataDocument? _document;
  String? _focusPath;
  int? _revision;
  final _rows = <({DataNode node, int depth})>[];
  final _depthCounts = <int>[];
  @override
  void dispose() {
    _scroll.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _selectNode(DataNode node) {
    _keyboardFocus.requestFocus();
    widget.model.select(node.path);
  }

  void _toggleNode(DataNode node) {
    _keyboardFocus.requestFocus();
    widget.model.toggle(node.path);
  }

  KeyEventResult _navigate(FocusNode focus, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (![
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(key)) {
      return KeyEventResult.ignored;
    }
    final model = widget.model;
    var path = model.selectedPath;
    var index = _rows.indexWhere((row) => row.node.path == path);
    // 鼠标折叠祖先后，原选中节点可能已隐藏；从可见祖先继续导航。
    while (index < 0 && path != model.focusPath) {
      path = model.document!.parents[path]!;
      index = _rows.indexWhere((row) => row.node.path == path);
    }
    final node = _rows[index].node;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final next = (index + (key == LogicalKeyboardKey.arrowUp ? -1 : 1)).clamp(
        0,
        _rows.length - 1,
      );
      _selectNode(_rows[next].node);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (node.isContainer && !model.expanded.contains(node.path)) {
        _selectNode(node);
        _toggleNode(node);
      } else if (node.children.isNotEmpty) {
        _selectNode(node.children.first);
      }
    } else if (node.isContainer && model.expanded.contains(node.path)) {
      _selectNode(node);
      _toggleNode(node);
    } else if (node.path != model.focusPath) {
      _selectNode(model.document!.nodes[model.document!.parents[node.path]]!);
    }
    return KeyEventResult.handled;
  }

  Future<void> _showNodeMenu(DataNode node, Offset globalPosition) async {
    _keyboardFocus.requestFocus();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final action = await showMenu<_NodeAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        if (node.isContainer)
          const PopupMenuItem(value: _NodeAction.focus, child: Text('聚焦此节点')),
        const PopupMenuItem(value: _NodeAction.copyPath, child: Text('复制路径')),
        const PopupMenuItem(value: _NodeAction.copyValue, child: Text('复制值')),
        const PopupMenuItem(
          value: _NodeAction.copyJson,
          child: Text('复制 JSON'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _NodeAction.focus:
        widget.model.focus(node.path);
      case _NodeAction.copyPath:
        await widget.onCopy(node.path, '路径');
      case _NodeAction.copyValue:
        await widget.onCopy(
          node.isContainer ? node.toJson(pretty: false) : node.value,
          '值',
        );
      case _NodeAction.copyJson:
        await widget.onCopy(node.toJson(), 'JSON');
    }
  }

  void _appendRows(
    DataNode node,
    int depth,
    List<({DataNode node, int depth})> rows,
  ) {
    rows.add((node: node, depth: depth));
    if (depth == _depthCounts.length) _depthCounts.add(0);
    _depthCounts[depth]++;
    if (widget.model.expanded.contains(node.path)) {
      for (final child in node.children) {
        _appendRows(child, depth + 1, rows);
      }
    }
  }

  void _updateBranch(String path) {
    final index = _rows.indexWhere((row) => row.node.path == path);
    if (index < 0) return; // 隐藏分支的切换不影响当前可见行。
    final row = _rows[index];
    var end = index + 1;
    while (end < _rows.length && _rows[end].depth > row.depth) {
      _depthCounts[_rows[end].depth]--;
      end++;
    }
    _rows.removeRange(index + 1, end);
    while (_depthCounts.last == 0) {
      _depthCounts.removeLast();
    }
    if (widget.model.expanded.contains(path)) {
      final added = <({DataNode node, int depth})>[];
      for (final child in row.node.children) {
        _appendRows(child, row.depth + 1, added);
      }
      _rows.insertAll(index + 1, added);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!identical(_document, model.document) ||
        _focusPath != model.focusPath ||
        _revision != model.treeRevision) {
      if (identical(_document, model.document) &&
          _focusPath == model.focusPath &&
          _revision != null &&
          model.treeRevision == _revision! + 1 &&
          model.treeTogglePath != null) {
        _updateBranch(model.treeTogglePath!);
      } else {
        // 换文档、改变聚焦范围或同一帧发生多次展开变更时重建。
        _rows.clear();
        _depthCounts.clear();
        _appendRows(model.focused!, 0, _rows);
      }
      _document = model.document;
      _focusPath = model.focusPath;
      _revision = model.treeRevision;
    }
    final rows = _rows;
    if (_lastSelected != model.selectedPath) {
      _lastSelected = model.selectedPath;
      final index = _rows.indexWhere(
        (row) => row.node.path == model.selectedPath,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && index >= 0) {
          final target = 10 + index * 42.0;
          if (target < _scroll.offset ||
              target >
                  _scroll.offset + _scroll.position.viewportDimension - 42) {
            _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
          }
        }
      });
    }
    final maxDepth = _depthCounts.length - 1;
    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _navigate,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${rows.length} 个可见节点',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => model.expandAll(true),
                  child: const Text('全部展开'),
                ),
                TextButton(
                  onPressed: () => model.expandAll(false),
                  child: const Text('全部折叠'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(constraints.maxWidth, 460 + maxDepth * 20.0),
                  child: ListView.builder(
                    controller: _scroll,
                    itemExtent: 42,
                    itemCount: rows.length,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemBuilder: (context, index) {
                      final row = rows[index], node = rows[index].node;
                      final selected = model.selectedPath == node.path;
                      return Material(
                        color: selected
                            ? mint.withValues(alpha: .08)
                            : Colors.transparent,
                        child: GestureDetector(
                          onLongPressStart: (details) =>
                              _showNodeMenu(node, details.globalPosition),
                          child: InkWell(
                            key: ValueKey('node:${node.path}'),
                            onTap: () => _selectNode(node),
                            onSecondaryTapUp: (details) =>
                                _showNodeMenu(node, details.globalPosition),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: selected ? mint : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              padding: EdgeInsets.only(
                                left: 10 + row.depth * 20.0,
                                right: 18,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: node.isContainer
                                        ? IconButton(
                                            padding: EdgeInsets.zero,
                                            iconSize: 18,
                                            tooltip:
                                                model.expanded.contains(
                                                  node.path,
                                                )
                                                ? '折叠'
                                                : '展开',
                                            onPressed: () => _toggleNode(node),
                                            icon: Icon(
                                              model.expanded.contains(node.path)
                                                  ? Icons.keyboard_arrow_down
                                                  : Icons.chevron_right,
                                              color: muted,
                                            ),
                                          )
                                        : const Center(
                                            child: Text(
                                              '·',
                                              style: TextStyle(color: muted),
                                            ),
                                          ),
                                  ),
                                  Expanded(
                                    // 连续点击逐次响应，避免为了识别双击而延迟单击。
                                    // 箭头独立处理点击，不参与行内容的双击计数。
                                    child: RawGestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      excludeFromSemantics: true,
                                      gestures: {
                                        SerialTapGestureRecognizer:
                                            GestureRecognizerFactoryWithHandlers<
                                              SerialTapGestureRecognizer
                                            >(
                                              () => SerialTapGestureRecognizer(
                                                allowedButtonsFilter:
                                                    (buttons) =>
                                                        buttons ==
                                                        kPrimaryButton,
                                              ),
                                              (recognizer) {
                                                recognizer
                                                    .onSerialTapUp = (details) {
                                                  _selectNode(node);
                                                  if (node.isContainer &&
                                                      details.count.isEven) {
                                                    _toggleNode(node);
                                                  }
                                                };
                                              },
                                            ),
                                      },
                                      child: Row(
                                        children: [
                                          Flexible(
                                            flex: 3,
                                            child: Text(
                                              node.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: codeStyle.copyWith(
                                                color: selected ? mint : ink,
                                              ),
                                            ),
                                          ),
                                          const Text(
                                            '  :  ',
                                            style: TextStyle(color: muted),
                                          ),
                                          Expanded(
                                            flex: 5,
                                            child: Text(
                                              node.preview,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: codeStyle.copyWith(
                                                color: node.isContainer
                                                    ? muted
                                                    : typeColor(node.type),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          TypeBadge(node.type),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
