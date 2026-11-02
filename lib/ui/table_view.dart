import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/document.dart';
import '../core/workbench.dart';
import 'theme.dart';

class TableView extends StatefulWidget {
  const TableView({super.key, required this.model});
  final Workbench model;
  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  String? _arrayPath;
  String? _lastSelected;
  String _filter = '';
  final _filterController = TextEditingController();
  final _scroll = ScrollController();
  final _horizontal = ScrollController();
  bool _revealColumn = true;
  final Set<String?> _hidden = {};
  String? _sortKey;
  bool _sorting = false;
  bool _ascending = true;
  DataNode? _cachedArray;
  List<String?> _allColumns = [];
  (DataNode, String, bool, String?, bool)? _rowInputs;
  List<DataNode> _rows = [];
  final _rowPositions = <String, int>{};

  DataNode? cell(DataNode row, String? column) => column == null
      ? (row.kind == NodeKind.object ? null : row)
      : row.children
            .where(
              (child) => row.kind == NodeKind.object && child.label == column,
            )
            .firstOrNull;
  @override
  void dispose() {
    _filterController.dispose();
    _scroll.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final arrays = model.document!.arrays;
    if (arrays.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined, size: 42, color: muted),
            SizedBox(height: 18),
            Text('这份数据中没有数组'),
            SizedBox(height: 8),
            Text('对象数组适合用表格比较，也支持普通数组。', style: TextStyle(color: muted)),
          ],
        ),
      );
    }
    final selectionChanged = _lastSelected != model.selectedPath;
    if (selectionChanged) {
      _lastSelected = model.selectedPath;
      _revealColumn = true;
      var path = model.selectedPath;
      while (true) {
        if (model.document!.nodes[path]?.kind == NodeKind.array) {
          _arrayPath = path;
          break;
        }
        final parent = model.document!.parents[path];
        if (parent == null) break;
        path = parent;
      }
    }
    final array =
        arrays.where((node) => node.path == _arrayPath).firstOrNull ??
        arrays.first;
    _arrayPath = array.path;
    if (!identical(_cachedArray, array)) {
      _cachedArray = array;
      final columns = <String?>{};
      for (final row in array.children) {
        if (row.kind == NodeKind.object) {
          columns.addAll(row.children.map((child) => child.label));
        } else {
          columns.add(null);
        }
      }
      _allColumns = columns.toList();
    }
    final allColumns = _allColumns;
    String? rowPath = model.selectedPath;
    while (rowPath != null && model.document!.parents[rowPath] != array.path) {
      rowPath = model.document!.parents[rowPath];
    }
    final selectedRow = model.document!.nodes[rowPath];
    String? selectedColumn;
    if (selectedRow != null) {
      if (selectedRow.kind == NodeKind.object) {
        selectedColumn = selectedRow.children
            .where(
              (node) =>
                  model.selectedPath == node.path ||
                  model.selectedPath.startsWith('${node.path}.') ||
                  model.selectedPath.startsWith('${node.path}['),
            )
            .firstOrNull
            ?.label;
      }
      if (_revealColumn) {
        _hidden.remove(selectedColumn);
        if (_filter.isNotEmpty &&
            !selectedRow
                .toJson(pretty: false)
                .toLowerCase()
                .contains(_filter.toLowerCase())) {
          _filter = '';
          _filterController.clear();
        }
      }
    }
    final columns = allColumns.where((key) => !_hidden.contains(key)).toList();
    final inputs = (array, _filter, _sorting, _sortKey, _ascending);
    final rowsChanged = inputs != _rowInputs;
    if (rowsChanged) {
      _rowInputs = inputs;
      final needle = _filter.toLowerCase();
      _rows = array.children
          .where(
            (row) =>
                needle.isEmpty ||
                row.toJson(pretty: false).toLowerCase().contains(needle),
          )
          .toList();
      if (_sorting) {
        _rows.sort((a, b) {
          final x = cell(a, _sortKey), y = cell(b, _sortKey);
          final int result;
          if (x == null || y == null) {
            result = x == null ? (y == null ? 0 : 1) : -1;
          } else if (x.kind == NodeKind.number && y.kind == NodeKind.number) {
            result = compareNumbers(x.value, y.value);
          } else {
            result = x.preview.compareTo(y.preview);
          }
          return result == 0
              ? int.parse(a.label).compareTo(int.parse(b.label))
              : (_ascending ? result : -result);
        });
      }
      _rowPositions.clear();
      for (var index = 0; index < _rows.length; index++) {
        _rowPositions[_rows[index].path] = index;
      }
    }
    final rows = _rows;
    final selectedIndex = _rowPositions[selectedRow?.path] ?? -1;
    if (selectedIndex >= 0 && (selectionChanged || rowsChanged)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = selectedIndex * 48.0;
        if (target < _scroll.offset ||
            target > _scroll.offset + _scroll.position.viewportDimension - 48) {
          _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(array.path),
                  initialValue: array.path,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '浏览数组'),
                  items: arrays
                      .map(
                        (node) => DropdownMenuItem(
                          value: node.path,
                          child: Text(
                            node.path,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (path) {
                    if (path != null) {
                      _hidden.clear();
                      _sorting = false;
                      model.select(path);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _filterController,
                  decoration: const InputDecoration(
                    hintText: '筛选记录…',
                    prefixIcon: Icon(Icons.filter_list, size: 18),
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              PopupMenuButton<String?>(
                tooltip: '选择显示列',
                icon: const Icon(Icons.view_column_outlined, size: 20),
                itemBuilder: (context) => allColumns
                    .map(
                      (column) => CheckedPopupMenuItem<String?>(
                        value: column,
                        checked: !_hidden.contains(column),
                        onTap: () => setState(() {
                          if (!_hidden.remove(column)) _hidden.add(column);
                        }),
                        child: Text(column ?? '值'),
                      ),
                    )
                    .toList(),
              ),
              Text(
                '${rows.length} / ${array.children.length} 条',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('没有匹配的记录', style: TextStyle(color: muted)),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.max(
                      constraints.maxWidth,
                      64 + columns.length * 180.0,
                    );
                    final cellWidth = columns.isEmpty
                        ? 0.0
                        : (width - 64) / columns.length;
                    if (_revealColumn && selectedRow != null) {
                      _revealColumn = false;
                      final columnIndex = columns.indexOf(selectedColumn);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted ||
                            !_horizontal.hasClients ||
                            columnIndex < 0) {
                          return;
                        }
                        final target = 64 + columnIndex * cellWidth;
                        if (target < _horizontal.offset ||
                            target + cellWidth >
                                _horizontal.offset +
                                    _horizontal.position.viewportDimension) {
                          _horizontal.jumpTo(
                            target.clamp(
                              0,
                              _horizontal.position.maxScrollExtent,
                            ),
                          );
                        }
                      });
                    }
                    return SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          children: [
                            Container(
                              height: 44,
                              color: panel,
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 64,
                                    child: Center(
                                      child: Text(
                                        '#',
                                        style: TextStyle(color: muted),
                                      ),
                                    ),
                                  ),
                                  for (final column in columns)
                                    SizedBox(
                                      width: cellWidth,
                                      child: InkWell(
                                        onTap: () => setState(() {
                                          _ascending =
                                              _sorting && _sortKey == column
                                              ? !_ascending
                                              : true;
                                          _sortKey = column;
                                          _sorting = true;
                                        }),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  column ?? '值',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                _sorting && _sortKey == column
                                                    ? (_ascending
                                                          ? Icons.arrow_upward
                                                          : Icons
                                                                .arrow_downward)
                                                    : Icons.unfold_more,
                                                size: 14,
                                                color: muted,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: _scroll,
                                itemExtent: 48,
                                itemCount: rows.length,
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: index == selectedIndex
                                          ? mint.withValues(alpha: .06)
                                          : null,
                                      border: const Border(
                                        bottom: BorderSide(
                                          color: line,
                                          width: .5,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 64,
                                          child: TextButton(
                                            onPressed: () =>
                                                model.select(row.path),
                                            child: Text(
                                              row.label,
                                              style: const TextStyle(
                                                color: muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        for (final column in columns)
                                          Builder(
                                            builder: (context) {
                                              final value = cell(row, column);
                                              final selected =
                                                  value?.path ==
                                                  model.selectedPath;
                                              return SizedBox(
                                                width: cellWidth,
                                                child: Material(
                                                  color: selected
                                                      ? mint.withValues(
                                                          alpha: .12,
                                                        )
                                                      : Colors.transparent,
                                                  child: InkWell(
                                                    onTap: value == null
                                                        ? null
                                                        : () => model.select(
                                                            value.path,
                                                          ),
                                                    child: Container(
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                          ),
                                                      child: Text(
                                                        value?.preview ??
                                                            '— 缺失',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 1,
                                                        style: codeStyle
                                                            .copyWith(
                                                              fontSize: 12,
                                                              color:
                                                                  value == null
                                                                  ? muted
                                                                  : typeColor(
                                                                      value
                                                                          .type,
                                                                    ),
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
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
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'null 空值    ·    — 缺失字段    ·    "" 空字符串    /    点击单元格查看详情',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
