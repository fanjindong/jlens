import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/main.dart';

import 'workbench_test.dart' show MemoryStorage;

void main() {
  testWidgets('表格缓存随排序、筛选和数组切换更新，节点选择保留结果顺序', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JLensApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-document')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-input')),
      '{"items":[{"id":3,"name":"C"},{"id":1,"name":"A"},{"id":2,"name":"B"}],"other":[4,2]}',
    );
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-table')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('id'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('"A"')).dy,
      lessThan(tester.getTopLeft(find.text('"C"')).dy),
    );
    await tester.tap(find.text('"B"'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('"A"')).dy,
      lessThan(tester.getTopLeft(find.text('"C"')).dy),
    );
    final filter = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == '筛选记录…',
    );
    await tester.enterText(filter, 'C');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 条'), findsOneWidget);
    await tester.enterText(filter, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('id'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('"C"')).dy,
      lessThan(tester.getTopLeft(find.text('"A"')).dy),
    );
    await tester.tap(find.text(r'$.items').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'$.other').last);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 条'), findsOneWidget);
    expect(find.text('值'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('桌面解析 Python、搜索定位、切换源码与表格、恢复历史', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JLensApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();
    expect(find.text('JLens'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-document')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-input')),
      "{'items': [{'name': '苹果', 'price': None}, {'name': '梨'}], 'ok': True}",
    );
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-tree')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-input')), '苹果');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(r'result:$.items[0].name')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(r'node:$.items[0].name')), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-table')));
    await tester.pumpAndSettle();
    expect(find.text('— 缺失'), findsOneWidget);
    expect(find.text('null'), findsWidgets);
    await tester.tap(find.byKey(const Key('view-source')));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(
      find.byKey(const Key('source-input')),
    );
    expect(
      editor.controller!.selection.textInside(editor.controller!.text),
      "'苹果'",
    );
    await tester.tap(find.byKey(const Key('new-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('items · ok'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('窄屏无布局溢出，错误输入可定位', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JLensApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-source')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-input')), '{"x": @}');
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 行'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
