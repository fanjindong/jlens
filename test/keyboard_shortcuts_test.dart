import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/main.dart';
import 'package:jlens/ui/tree_view.dart';

import 'workbench_test.dart' show MemoryStorage;

Future<void> mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(JLensApp(storage: MemoryStorage()));
  await tester.pumpAndSettle();
}

Future<void> findShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('Cmd/Ctrl+F 聚焦搜索，方向键不劫持搜索输入', (tester) async {
    await mount(tester);
    final model = tester.widget<TreeView>(find.byType(TreeView)).model;
    final search = find.byKey(const Key('search-input'));
    for (final modifier in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
    ]) {
      await findShortcut(tester, modifier);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(model.selectedPath, r'$');
    }
    await tester.enterText(search, '苹果');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(
      find.byKey(const ValueKey(r'result:$.data.products[1].name')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(model.selectedPath, r'$.data.products[1].price');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('从源码搜索再清空时保留搜索焦点和未解析草稿', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const Key('view-source')));
    await tester.pumpAndSettle();
    final source = find.byKey(const Key('source-input'));
    await tester.enterText(source, '{"draft":');
    await findShortcut(tester, LogicalKeyboardKey.metaLeft);
    final search = find.byKey(const Key('search-input'));
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.enterText(search, '苹果');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(source).controller!.text, '{"draft":');
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
