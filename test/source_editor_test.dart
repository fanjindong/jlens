import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/ui/source_editor.dart';

void main() {
  testWidgets('光标变化复用高亮，修改文本或样式后显示最新内容', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    final controller = CodeController(
      text: '{"id":9007199254740993,"name":"苹果"}',
    );
    addTearDown(controller.dispose);
    final first = controller.buildTextSpan(
      context: context,
      style: const TextStyle(fontSize: 12),
      withComposing: false,
    );
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    final selected = controller.buildTextSpan(
      context: context,
      style: const TextStyle(fontSize: 16),
      withComposing: false,
    );
    expect(selected.children, same(first.children));
    expect(selected.style!.fontSize, 16);
    expect(selected.toPlainText(), controller.text);
    controller.text = "{'name':'梨','active':True}";
    final changed = controller.buildTextSpan(
      context: context,
      style: null,
      withComposing: false,
    );
    expect(changed.toPlainText(), controller.text);
    expect(changed.children, isNot(same(first.children)));
    expect(
      changed.children!
          .whereType<TextSpan>()
          .where((span) => span.text == "'梨'")
          .single
          .style!
          .color,
      isNotNull,
    );
  });
}
