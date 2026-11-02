import 'package:flutter/material.dart';

import '../core/document.dart';
import 'theme.dart';

class CodeController extends TextEditingController {
  CodeController({super.text});
  static final tokens = RegExp(
    r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:true|false|null|True|False|None)\b|[+-]?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?''',
  );
  String? _highlightedText;
  List<TextSpan> _highlightedSpans = [];
  static final _numberStart = RegExp(r'^[+\-\d]');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_highlightedText == text) {
      return TextSpan(style: style, children: _highlightedSpans);
    }
    final spans = <TextSpan>[];
    var end = 0;
    for (final match in tokens.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, match.start)));
      final token = match.group(0)!;
      final color = token.startsWith('"') || token.startsWith("'")
          ? mint
          : _numberStart.hasMatch(token)
          ? const Color(0xffffce84)
          : const Color(0xffc6a3ff);
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(color: color),
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: text.substring(end)));
    // 光标和选区变化也会请求高亮；原文未变时复用分词结果。
    _highlightedText = text;
    _highlightedSpans = spans;
    return TextSpan(style: style, children: spans);
  }
}

class SourceEditor extends StatefulWidget {
  const SourceEditor({
    super.key,
    required this.raw,
    required this.onChanged,
    required this.selection,
    required this.error,
    required this.onParse,
    required this.focusOnLocate,
  });
  final String raw;
  final ValueChanged<String> onChanged;
  final DataNode? selection;
  final DataParseException? error;
  final VoidCallback onParse;
  final bool focusOnLocate;
  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  late final CodeController _controller = CodeController(text: widget.raw);
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void didUpdateWidget(SourceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.raw != _controller.text) _controller.text = widget.raw;
    if (oldWidget.selection != widget.selection ||
        oldWidget.error != widget.error) {
      _locate();
    }
  }

  void _locate() {
    if (widget.error != null) {
      final offset = widget.error!.offset.clamp(0, _controller.text.length);
      _controller.selection = TextSelection.collapsed(offset: offset);
    } else if (widget.selection case final node?) {
      if (node.path != r'$' && node.end <= _controller.text.length) {
        _controller.selection = TextSelection(
          baseOffset: node.start,
          extentOffset: node.end,
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 从搜索恢复源码时保留搜索框焦点，避免继续输入写入草稿。
      if (mounted &&
          widget.focusOnLocate &&
          (widget.error != null || widget.selection?.path != r'$')) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.code, size: 16, color: muted),
            const SizedBox(width: 8),
            const Text('原始输入', style: TextStyle(color: muted)),
            const Spacer(),
            Text(
              '${'\n'.allMatches(widget.raw).length + 1} 行',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: TextField(
          key: const Key('source-input'),
          controller: _controller,
          focusNode: _focus,
          onChanged: widget.onChanged,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: codeStyle,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: '在此粘贴 JSON 或 Python dict…\n\n解析后，即可切换视角浏览。',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.all(22),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '支持单引号、True / False / None 与末尾逗号',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
            TextButton(onPressed: widget.onParse, child: const Text('解析输入')),
          ],
        ),
      ),
    ],
  );
}
