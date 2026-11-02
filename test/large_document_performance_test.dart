import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/core/workbench.dart';
import 'package:jlens/ui/source_editor.dart';
import 'package:jlens/ui/tree_view.dart';

import 'workbench_test.dart' show MemoryStorage;

void main() {
  testWidgets('大文档展开与重复高亮计时', (tester) async {
    final raw = jsonEncode({
      'items': List.generate(
        5000,
        (i) => {
          'id': i,
          'name': '商品$i',
          'tags': ['当季', '直采'],
          'active': true,
        },
      ),
    });
    final model = Workbench(MemoryStorage());
    await model.initialize();
    model.edit(raw);
    expect(model.parse(), isTrue);
    model.expandAll(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: model.browseChanges,
            builder: (context, child) =>
                TreeView(model: model, onCopy: (value, label) async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 只记录本地测试耗时，不以易受机器负载影响的毫秒数作为断言。
    final timings = <int>[];
    for (var i = 0; i < 35; i++) {
      final watch = Stopwatch()..start();
      model.toggle(r'$.items[0].tags');
      await tester.pump();
      watch.stop();
      if (i >= 5) timings.add(watch.elapsedMicroseconds);
    }
    timings.sort();
    final controller = CodeController(text: raw);
    final context = tester.element(find.byType(TreeView));
    final highlights = <int>[];
    for (var i = 0; i < 35; i++) {
      controller.selection = TextSelection.collapsed(offset: i);
      final watch = Stopwatch()..start();
      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 12),
        withComposing: false,
      );
      watch.stop();
      expect(span.toPlainText(), raw);
      if (i >= 5) highlights.add(watch.elapsedMicroseconds);
    }
    highlights.sort();
    debugPrint(
      'BENCH nodes=${model.document!.nodes.length} bytes=${utf8.encode(raw).length} tree_p50_us=${timings[15]} tree_p95_us=${timings[28]} highlight_p50_us=${highlights[15]} highlight_p95_us=${highlights[28]}',
    );
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    model.dispose();
  });
}
