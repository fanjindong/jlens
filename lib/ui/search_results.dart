import 'dart:async';

import 'package:flutter/material.dart';

import '../core/document.dart';
import 'theme.dart';

class SearchResults extends StatefulWidget {
  const SearchResults({
    super.key,
    required this.document,
    required this.query,
    required this.mode,
    required this.onSelect,
  });
  final DataDocument document;
  final String query;
  final String mode;
  final ValueChanged<DataNode> onSelect;

  @override
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  Timer? _timer;
  bool _pending = true;
  List<DataNode> _results = [];
  late RegExp _matches;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged =
        !identical(widget.document, oldWidget.document) ||
        widget.mode != oldWidget.mode;
    if (contextChanged || widget.query != oldWidget.query) {
      _schedule(immediately: contextChanged);
    }
  }

  void _schedule({bool immediately = false}) {
    _timer?.cancel();
    _pending = true;
    if (immediately) {
      _search();
    } else {
      // 连续输入只检索最后的查询，浏览状态重建则复用现有结果。
      _timer = Timer(
        const Duration(milliseconds: 150),
        () => setState(_search),
      );
    }
  }

  void _search() {
    _results = widget.document.search(widget.query, widget.mode);
    _matches = RegExp(RegExp.escape(widget.query), caseSensitive: false);
    _pending = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _highlight(String text, TextStyle style) {
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in _matches.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            color: mint,
            backgroundColor: mint.withValues(alpha: .16),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pending) {
      return const Center(
        child: Text('正在搜索…', style: TextStyle(color: muted)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '找到 ${_results.length} 个节点 · 点击定位',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? const Center(
                  child: Text('没有找到匹配的节点', style: TextStyle(color: muted)),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final node = _results[index];
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        key: ValueKey('result:${node.path}'),
                        dense: true,
                        title: _highlight(
                          node.path,
                          codeStyle.copyWith(fontSize: 12),
                        ),
                        subtitle: _highlight(
                          node.preview,
                          TextStyle(color: typeColor(node.type), fontSize: 12),
                        ),
                        trailing: TypeBadge(node.type),
                        onTap: () => widget.onSelect(node),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
