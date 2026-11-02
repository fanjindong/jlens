import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/main.dart';

import 'workbench_test.dart' show MemoryStorage;

void main() {
  testWidgets('连续选中节点只更新浏览区域，保存成功不触发整页重建', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JLensApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();

    var screenBuilds = 0;
    final previousCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousCallback?.call(element, builtOnce);
      if (element.widget is WorkbenchScreen) screenBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
    for (var index = 0; index < 10; index++) {
      final path = index.isEven ? r'$.request_id' : r'$.success';
      await tester.tap(find.byKey(ValueKey('node:$path')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = previousCallback;
    debugPrint('10 次节点选择及保存完成：工作台整体重建 $screenBuilds 次');
    expect(find.text(r'$.success'), findsWidgets);
    expect(screenBuilds, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
