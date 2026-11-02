import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/core/document.dart';
import 'package:jlens/ui/search_results.dart';

class CountingDocument extends DataDocument {
  CountingDocument(DataDocument document)
    : super(document.raw, document.root, document.format);
  int searches = 0;
  @override
  List<DataNode> search(String query, String mode) {
    searches++;
    return super.search(query, mode);
  }
}

void main() {
  testWidgets('合并连续输入，重建复用结果，模式或文档变化刷新缓存', (tester) async {
    final doc = CountingDocument(
      DataDocument.parse('{"name":"Apple", "tag":"a.b"}'),
    );
    Future<void> show(
      String query, {
      String mode = '全部',
      DataDocument? document,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResults(
            document: document ?? doc,
            query: query,
            mode: mode,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await show('a');
    await tester.pump(const Duration(milliseconds: 80));
    await show('ap');
    await tester.pump(const Duration(milliseconds: 80));
    expect(doc.searches, 0);
    await show('apple');
    await tester.pump(const Duration(milliseconds: 150));
    expect(doc.searches, 1);
    expect(find.text('找到 1 个节点 · 点击定位'), findsOneWidget);
    await show('apple');
    await tester.pump(const Duration(milliseconds: 200));
    expect(doc.searches, 1);
    await show('apple', mode: '字段');
    expect(doc.searches, 2);
    expect(find.text('没有找到匹配的节点'), findsOneWidget);
    final next = CountingDocument(DataDocument.parse('{"apple":true}'));
    await show('apple', mode: '字段', document: next);
    expect(next.searches, 1);
    expect(find.text('找到 1 个节点 · 点击定位'), findsOneWidget);
    await show('a.b');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(doc.searches, 3); // 换回文档立即检索，销毁后没有延迟检索。
  });

  testWidgets('搜索按字面高亮并选择对应节点，支持大小写差异', (tester) async {
    final doc = DataDocument.parse('{"name":"a.b APPLE"}');
    DataNode? selected;
    Future<void> show(String query) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResults(
              document: doc,
              query: query,
              mode: '全部',
              onSelect: (node) => selected = node,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }

    for (final query in ['a.b', 'apple']) {
      await show(query);
      final text = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.textSpan?.toPlainText() == '"a.b APPLE"',
        ),
      );
      final span = text.textSpan! as TextSpan;
      expect(
        span.children!
            .whereType<TextSpan>()
            .where((part) => part.style?.backgroundColor != null)
            .single
            .text!
            .toLowerCase(),
        query,
      );
    }
    await tester.tap(find.byKey(const ValueKey(r'result:$.name')));
    expect(selected, same(doc.nodes[r'$.name']));
    await tester.pumpAndSettle();
  });
}
