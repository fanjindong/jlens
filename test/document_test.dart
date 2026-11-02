import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/core/document.dart';

void main() {
  test('有界预览保持完整 JSON 的前缀，复制仍输出完整数据', () {
    final document = DataDocument.parse(
      jsonEncode({
        'items': List.generate(
          2000,
          (index) => {'id': index, 'name': '苹果\n"😀"'},
        ),
        'empty': <String, Object?>{},
        'long': '😀\n' * 3000,
      }),
    );
    for (final node in [
      document.root,
      document.nodes[r'$.long']!,
      document.nodes[r'$.empty']!,
    ]) {
      final full = node.toJson();
      for (final limit in [0, 1, 2, 3, 8, 1800, full.length]) {
        final expected = full.length > limit
            ? '${full.substring(0, limit)}\n…（预览已截断，复制可得完整内容）'
            : full;
        expect(node.jsonPreview(maxLength: limit), expected);
      }
    }
    expect(
      (jsonDecode(document.root.toJson()) as Map<String, Object?>)['items'],
      hasLength(2000),
    );
  });

  test('标准 JSON 保留超大整数、小数与指数原文', () {
    const raw =
        '{"id":900719925474099312345,"price":0.1234567890123456789,"scale":1e999}';
    final doc = DataDocument.parse(raw);
    expect(doc.format, 'JSON');
    expect(doc.root.toJson(pretty: false), raw);
    expect(doc.nodes[r'$.id']!.value, '900719925474099312345');
  });
  test('Python 字符串转义、布尔、空值、嵌套和尾逗号转换正确', () {
    final doc = DataDocument.parse(
      r'''{'title': "it's good", 'quote': 'it\'s fine', 'items': [True, False, None,], 'unicode': '\u4e2d\U0001f600', 'hex': '\x41',}''',
    );
    expect(doc.format, 'Python Dict');
    expect(doc.nodes[r'$.title']!.value, "it's good");
    expect(doc.nodes[r'$.quote']!.value, "it's fine");
    expect(doc.nodes[r'$.unicode']!.value, '中😀');
    expect(doc.nodes[r'$.hex']!.value, 'A');
    expect(doc.nodes[r'$.items[0]']!.value, 'true');
    expect(DataDocument.parse(doc.root.toJson()).format, 'JSON');
  });
  test('Python 数字转为合法 JSON 且不经浮点舍入', () {
    final doc = DataDocument.parse(
      '[+.5, -2., 000.5, +999999999999999999999, 1E+99]',
    );
    expect(
      doc.root.toJson(pretty: false),
      '[0.5,-2.0,0.5,999999999999999999999,1e+99]',
    );
    expect(
      () => DataDocument.parse('[012]'),
      throwsA(isA<DataParseException>()),
    );
  });
  test('路径不会混淆特殊键与嵌套节点，源码范围精确', () {
    const raw = '{"a.b":{"x[0]":"中文"},"a":{"b":1},"":null}';
    final doc = DataDocument.parse(raw);
    final node = doc.nodes[r'$["a.b"]["x[0]"]']!;
    expect(raw.substring(node.start, node.end), '"中文"');
    expect(doc.nodes[r'$.a.b']!.value, '1');
    expect(doc.nodes[r'$[""]']!.kind, NodeKind.nil);
  });
  test('明确拒绝重复键、执行表达式、非字符串键与畸形数据', () {
    for (final raw in [
      '{"a":1,"a":2}',
      "__import__('os').system('whoami')",
      "{'a': f()}",
      '{1:2}',
      '{"a":}',
      '[1 2]',
      'true trailing',
      '[NaN]',
      r'"\q"',
      '[1,',
      '{"a":true,\'b\':True}',
    ]) {
      expect(
        () => DataDocument.parse(raw),
        throwsA(isA<DataParseException>()),
        reason: raw,
      );
    }
  });
  test('错误含行列，限制深层输入', () {
    try {
      DataDocument.parse('{\n "a": @\n}');
      fail('应该报错');
    } on DataParseException catch (error) {
      expect(error.line, 2);
      expect(error.column, 7);
    }
    expect(
      () => DataDocument.parse('${'[' * 130}0${']' * 130}'),
      throwsA(isA<DataParseException>()),
    );
  });
  test('支持根标量、空容器与准确搜索', () {
    expect(DataDocument.parse('null').root.kind, NodeKind.nil);
    expect(DataDocument.parse('[]').root.children, isEmpty);
    final doc = DataDocument.parse(
      '{"name":"苹果","nested":{"name":null},"empty":""}',
    );
    expect(doc.search('name', '字段'), hasLength(2));
    expect(doc.search('苹果', '值').single.path, r'$.name');
    expect(doc.search('null', '类型').single.path, r'$.nested.name');
    expect(doc.search('nested', '路径'), hasLength(2));
  });
  test('数值排序对超大数字、小数和巨大指数仍精确', () {
    expect(
      compareNumbers('9007199254740993', '9007199254740992'),
      greaterThan(0),
    );
    expect(
      compareNumbers('-9007199254740993', '-9007199254740992'),
      lessThan(0),
    );
    expect(compareNumbers('0.0002', '0.001'), lessThan(0));
    expect(compareNumbers('1.00', '1'), 0);
    expect(compareNumbers('-0', '0.000'), 0);
    expect(
      compareNumbers('1e99999999999999999999', '1e99999999999999999998'),
      greaterThan(0),
    );
    expect(compareNumbers('9', '10'), lessThan(0));
  });
}
