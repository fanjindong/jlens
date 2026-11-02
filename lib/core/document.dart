import 'dart:convert';

enum NodeKind { object, array, string, number, boolean, nil }

class DataNode {
  const DataNode({
    required this.kind,
    required this.path,
    required this.label,
    required this.start,
    required this.end,
    this.value = '',
    this.children = const [],
  });
  final NodeKind kind;
  final String path;
  final String label;
  final int start;
  final int end;
  final String value;
  final List<DataNode> children;
  bool get isContainer => kind == NodeKind.object || kind == NodeKind.array;
  String get type => kind == NodeKind.nil ? 'null' : kind.name;
  String get preview => switch (kind) {
    NodeKind.object => '{ ${children.length} 个字段 }',
    NodeKind.array => '[ ${children.length} 项 ]',
    NodeKind.string => jsonEncode(value),
    _ => value,
  };

  String toJson({bool pretty = true, int depth = 0}) {
    if (!isContainer) {
      return kind == NodeKind.string ? jsonEncode(value) : value;
    }
    final object = kind == NodeKind.object;
    final open = object ? '{' : '[';
    final close = object ? '}' : ']';
    if (children.isEmpty) return '$open$close';
    final gap = pretty ? '\n' : '';
    final indent = pretty ? '  ' * (depth + 1) : '';
    final entries = children.map(
      (child) =>
          '$indent${object ? '${jsonEncode(child.label)}:${pretty ? ' ' : ''}' : ''}${child.toJson(pretty: pretty, depth: depth + 1)}',
    );
    return '$open$gap${entries.join(',$gap')}$gap${pretty ? '  ' * depth : ''}$close';
  }

  String jsonPreview({int maxLength = 1800}) {
    assert(maxLength >= 0);
    final output = StringBuffer();
    final budget = maxLength + 1;
    void append(String text) {
      final remaining = budget - output.length;
      if (remaining > 0) {
        output.write(
          text.length > remaining ? text.substring(0, remaining) : text,
        );
      }
    }

    String quoted(String text) =>
        jsonEncode(text.length > budget ? text.substring(0, budget) : text);
    void visit(DataNode node, int depth) {
      if (output.length >= budget) return;
      if (!node.isContainer) {
        append(node.kind == NodeKind.string ? quoted(node.value) : node.value);
        return;
      }
      final object = node.kind == NodeKind.object;
      append(object ? '{' : '[');
      for (var index = 0; index < node.children.length; index++) {
        if (output.length >= budget) return;
        final child = node.children[index];
        append('${index == 0 ? '' : ','}\n${'  ' * (depth + 1)}');
        if (object) append('${quoted(child.label)}: ');
        visit(child, depth + 1);
      }
      if (node.children.isNotEmpty) append('\n${'  ' * depth}');
      append(object ? '}' : ']');
    }

    // 详情只显示少量字符，到预算即停，避免点击大容器时完整序列化。
    visit(this, 0);
    final text = output.toString();
    return text.length > maxLength
        ? '${text.substring(0, maxLength)}\n…（预览已截断，复制可得完整内容）'
        : text;
  }
}

class DataDocument {
  DataDocument(this.raw, this.root, this.format) {
    void visit(DataNode node) {
      nodes[node.path] = node;
      for (final child in node.children) {
        parents[child.path] = node.path;
        visit(child);
      }
    }

    visit(root);
  }
  final String raw;
  late final int byteLength = utf8.encode(raw).length;
  final DataNode root;
  final String format;
  final Map<String, DataNode> nodes = {};
  final Map<String, String> parents = {};
  late final List<DataNode> arrays = List.unmodifiable(
    nodes.values.where((n) => n.kind == NodeKind.array),
  );

  static DataDocument parse(String raw) {
    // 输入来自剪贴板与编辑器；限制递归深度和大小，避免坏输入阻塞浏览界面。
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const DataParseException('输入超过 2 MiB，请先截取所需数据', 0, 1, 1);
    }
    try {
      return DataDocument(raw, _Parser(raw, python: false).parse(), 'JSON');
    } on DataParseException catch (jsonError) {
      try {
        return DataDocument(
          raw,
          _Parser(raw, python: true).parse(),
          'Python Dict',
        );
      } on DataParseException catch (pythonError) {
        throw pythonError.offset >= jsonError.offset ? pythonError : jsonError;
      }
    }
  }

  List<DataNode> search(String query, String mode) {
    final needle = query.toLowerCase();
    return nodes.values
        .where(
          (n) => switch (mode) {
            '字段' => n.label.toLowerCase().contains(needle),
            '值' => !n.isContainer && n.value.toLowerCase().contains(needle),
            '类型' => n.type == needle,
            '路径' => n.path.toLowerCase().contains(needle),
            _ =>
              n.label.toLowerCase().contains(needle) ||
                  n.path.toLowerCase().contains(needle) ||
                  (!n.isContainer && n.value.toLowerCase().contains(needle)),
          },
        )
        .toList();
  }
}

class DataParseException implements Exception {
  const DataParseException(this.message, this.offset, this.line, this.column);
  final String message;
  final int offset;
  final int line;
  final int column;
  @override
  String toString() => '$message（第 $line 行，第 $column 列）';
}

class _Parser {
  _Parser(this.source, {required this.python});
  final String source;
  final bool python;
  int pos = 0;
  int count = 0;
  static final _jsonNumber = RegExp(
    r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?',
  );
  static final _pythonNumber = RegExp(
    r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?',
  );
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$');

  Never fail(String message, [int? at]) {
    final offset = at ?? pos;
    final prefix = source.substring(0, offset);
    throw DataParseException(
      message,
      offset,
      '\n'.allMatches(prefix).length + 1,
      offset - prefix.lastIndexOf('\n'),
    );
  }

  void space() {
    while (pos < source.length && ' \r\n\t'.contains(source[pos])) {
      pos++;
    }
  }

  bool take(String token) {
    if (source.startsWith(token, pos)) {
      pos += token.length;
      return true;
    }
    return false;
  }

  DataNode parse() {
    space();
    final result = node(r'$', r'$', 0);
    space();
    if (pos != source.length) fail('数据结束后存在多余内容');
    return result;
  }

  DataNode node(String path, String label, int depth) {
    if (depth > 128) fail('嵌套层级超过 128 层');
    if (++count > 50000) fail('节点超过 50,000 个，请缩小数据范围');
    space();
    final start = pos;
    if (pos >= source.length) fail('此处需要一个值');
    final char = source[pos];
    NodeKind kind;
    var value = '';
    final children = <DataNode>[];
    if (char == '{' || char == '[') {
      final object = char == '{';
      kind = object ? NodeKind.object : NodeKind.array;
      final close = object ? '}' : ']';
      pos++;
      space();
      final keys = <String>{};
      if (!take(close)) {
        while (true) {
          space();
          String childLabel;
          String childPath;
          if (object) {
            if (pos >= source.length ||
                (source[pos] != '"' && !(python && source[pos] == "'"))) {
              fail('对象键须为带引号的字符串');
            }
            childLabel = string();
            if (!keys.add(childLabel)) {
              fail('重复字段 ${jsonEncode(childLabel)}，请明确保留哪一个值');
            }
            childPath = _identifier.hasMatch(childLabel)
                ? '$path.$childLabel'
                : '$path[${jsonEncode(childLabel)}]';
            space();
            if (!take(':')) fail('字段名后缺少冒号');
          } else {
            childLabel = '${children.length}';
            childPath = '$path[$childLabel]';
          }
          children.add(node(childPath, childLabel, depth + 1));
          space();
          if (take(close)) break;
          if (!take(',')) fail('此处需要逗号或 $close');
          space();
          if (python && take(close)) break;
        }
      }
    } else if (char == '"' || (python && char == "'")) {
      kind = NodeKind.string;
      value = string();
    } else {
      final literals = python
          ? {'True': 'true', 'False': 'false', 'None': 'null'}
          : {'true': 'true', 'false': 'false', 'null': 'null'};
      var literalFound = false;
      kind = NodeKind.number;
      for (final entry in literals.entries) {
        if (take(entry.key)) {
          value = entry.value;
          kind = value == 'null' ? NodeKind.nil : NodeKind.boolean;
          literalFound = true;
          break;
        }
      }
      if (!literalFound) {
        final match = (python ? _pythonNumber : _jsonNumber).matchAsPrefix(
          source,
          pos,
        );
        if (match == null) fail('无法识别的值；仅支持 JSON 或 Python 数据字面量');
        value = match.group(0)!;
        pos = match.end;
        // 数字不经 double 转换，跨 Web / 原生平台都保留完整精度。
        if (python) value = normalizeNumber(value);
      }
    }
    return DataNode(
      kind: kind,
      path: path,
      label: label,
      start: start,
      end: pos,
      value: value,
      children: children,
    );
  }

  String normalizeNumber(String token) {
    var text = token.startsWith('+') ? token.substring(1) : token;
    final parts = text.split(RegExp('[eE]'));
    var mantissa = parts.first;
    final negative = mantissa.startsWith('-');
    if (negative) mantissa = mantissa.substring(1);
    final decimal = mantissa.contains('.');
    final integer = mantissa.split('.').first;
    if (!decimal &&
        parts.length == 1 &&
        integer.length > 1 &&
        integer.startsWith('0') &&
        RegExp('[1-9]').hasMatch(integer)) {
      fail('Python 十进制整数不能含前导零');
    }
    mantissa = mantissa.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (mantissa.startsWith('.')) mantissa = '0$mantissa';
    if (mantissa.endsWith('.')) mantissa = '${mantissa}0';
    return '${negative ? '-' : ''}$mantissa${parts.length > 1 ? 'e${parts[1]}' : ''}';
  }

  String string() {
    final quote = source[pos++];
    final out = StringBuffer();
    while (pos < source.length) {
      final char = source[pos++];
      if (char == quote) return out.toString();
      if (char.codeUnitAt(0) < 32) fail('字符串中存在未转义的控制字符', pos - 1);
      if (char != r'\') {
        out.write(char);
        continue;
      }
      if (pos >= source.length) fail('转义序列尚未结束');
      final escape = source[pos++];
      const escapes = {
        '"': '"',
        r'\': r'\',
        '/': '/',
        'b': '\b',
        'f': '\f',
        'n': '\n',
        'r': '\r',
        't': '\t',
      };
      if (escapes.containsKey(escape)) {
        out.write(escapes[escape]);
      } else if (python && escape == "'") {
        out.write("'");
      } else if (python && escape == 'a') {
        out.writeCharCode(7);
      } else if (python && escape == 'v') {
        out.writeCharCode(11);
      } else if (escape == 'u' ||
          (python && (escape == 'x' || escape == 'U'))) {
        final length = escape == 'x'
            ? 2
            : escape == 'U'
            ? 8
            : 4;
        if (pos + length > source.length) fail('Unicode 转义不完整');
        final hex = source.substring(pos, pos + length);
        if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) fail('Unicode 转义须为十六进制');
        final code = int.parse(hex, radix: 16);
        if (code > 0x10ffff) fail('Unicode 码点超出范围');
        out.writeCharCode(code);
        pos += length;
      } else if (python && RegExp('[0-7]').hasMatch(escape)) {
        var octal = escape;
        while (octal.length < 3 &&
            pos < source.length &&
            RegExp('[0-7]').hasMatch(source[pos])) {
          octal += source[pos++];
        }
        out.writeCharCode(int.parse(octal, radix: 8));
      } else {
        fail('不支持的转义序列 \\$escape', pos - 2);
      }
    }
    fail('字符串缺少结束引号');
  }
}

// 通过十进制位与指数比较，排序时也不把大整数转成浮点数。
int compareNumbers(String a, String b) {
  ({bool negative, String digits, BigInt order}) parts(String value) {
    final negative = value.startsWith('-');
    final pieces = value
        .replaceFirst(RegExp(r'^-'), '')
        .toLowerCase()
        .split('e');
    final fraction = pieces[0].split('.');
    final digits = fraction.join().replaceFirst(RegExp(r'^0+'), '');
    final exponent = pieces.length == 2 ? BigInt.parse(pieces[1]) : BigInt.zero;
    return (
      negative: negative && digits.isNotEmpty,
      digits: digits,
      order:
          BigInt.from(
            digits.length - (fraction.length == 2 ? fraction[1].length : 0),
          ) +
          exponent,
    );
  }

  final x = parts(a), y = parts(b);
  if (x.negative != y.negative) return x.negative ? -1 : 1;
  int result;
  if (x.digits.isEmpty || y.digits.isEmpty) {
    result = x.digits.isEmpty ? (y.digits.isEmpty ? 0 : -1) : 1;
  } else if (x.order != y.order) {
    result = x.order.compareTo(y.order);
  } else {
    final length = x.digits.length > y.digits.length
        ? x.digits.length
        : y.digits.length;
    result = x.digits
        .padRight(length, '0')
        .compareTo(y.digits.padRight(length, '0'));
  }
  return x.negative ? -result : result;
}
