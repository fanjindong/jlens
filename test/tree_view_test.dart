import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/core/workbench.dart';
import 'package:jlens/ui/tree_view.dart';

import 'workbench_test.dart' show MemoryStorage;

const _path = r'$.data.products[0]';
Finder get _row => find.byKey(const ValueKey('node:$_path'));
Finder get _arrow =>
    find.descendant(of: _row, matching: find.byType(IconButton));
Finder get _label => find.descendant(of: _row, matching: find.text('0'));

Future<Workbench> _mount(
  WidgetTester tester, {
  Future<void> Function(String, String)? onCopy,
}) async {
  final model = Workbench(MemoryStorage());
  await model.initialize();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([model, model.browseChanges]),
          builder: (context, child) =>
              TreeView(model: model, onCopy: onCopy ?? (value, label) async {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    model.dispose();
  });
  return model;
}

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.down(tester.getCenter(target));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind 点击箭头立即展开折叠，单击行立即选中', (tester) async {
      final model = await _mount(tester);
      final gesture = await tester.createGesture(kind: kind);
      for (final expanded in [true, false]) {
        await gesture.down(tester.getCenter(_arrow));
        await gesture.up();
        // 不推进测试时钟，确保没有等待双击判定或长按超时。
        await tester.pump();
        expect(model.expanded.contains(_path), expanded);
        expect(model.selectedPath, r'$');
      }
      await gesture.down(tester.getCenter(_label));
      await gesture.up();
      await tester.pump();
      expect(model.selectedPath, _path);
      expect(model.focusPath, r'$');
      await tester.pumpAndSettle();
    });
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind 双击立即切换展开状态，连续两组双击可展开再折叠', (tester) async {
      final model = await _mount(tester);
      for (var tap = 1; tap <= 4; tap++) {
        final gesture = await tester.createGesture(kind: kind);
        await gesture.down(tester.getCenter(_label));
        await gesture.up();
        await tester.pump();
        expect(model.selectedPath, _path);
        expect(model.expanded.contains(_path), tap == 2 || tap == 3);
        expect(model.focusPath, r'$');
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
  }

  testWidgets('间隔超过双击时限的单击不展开，普通值双击只选中', (tester) async {
    final model = await _mount(tester);
    await tester.tap(_label);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(_label);
    await tester.pump();
    expect(model.expanded.contains(_path), isFalse);
    final value = find.text('request_id');
    await tester.tap(value);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(value);
    await tester.pump();
    expect(model.selectedPath, r'$.request_id');
    expect(model.expanded.contains(r'$.request_id'), isFalse);
    expect(model.focusPath, r'$');
    await tester.pumpAndSettle();
  });

  testWidgets('节点行内容上下留白处也可双击展开', (tester) async {
    final model = await _mount(tester);
    final position = tester.getTopLeft(_row) + const Offset(200, 2);
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(position);
    await tester.pump();
    expect(model.expanded.contains(_path), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('拖动节点内容不触发选中或展开', (tester) async {
    final model = await _mount(tester);
    await tester.drag(_label, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(model.selectedPath, r'$');
    expect(model.expanded.contains(_path), isFalse);
  });

  testWidgets('右键菜单取消不聚焦，选择后聚焦对应容器', (tester) async {
    final model = await _mount(tester);
    await _rightClick(tester, _label);
    expect(find.text('聚焦此节点'), findsOneWidget);
    expect(model.focusPath, r'$');
    expect(model.selectedPath, r'$');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('聚焦此节点'), findsNothing);
    expect(model.focusPath, r'$');
    await _rightClick(tester, _label);
    await tester.tap(find.text('聚焦此节点'));
    await tester.pumpAndSettle();
    expect(model.focusPath, _path);
    expect(model.selectedPath, _path);
    expect(
      find.byKey(const ValueKey(r'node:$.data.products[0].id')),
      findsOneWidget,
    );
  });

  testWidgets('长按容器可从菜单聚焦，普通值不提供聚焦菜单', (tester) async {
    final model = await _mount(tester);
    await _rightClick(tester, find.text('request_id'));
    expect(find.text('聚焦此节点'), findsNothing);
    expect(find.text('复制值'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.longPress(_label);
    await tester.pumpAndSettle();
    expect(find.text('聚焦此节点'), findsOneWidget);
    expect(model.focusPath, r'$');
    await tester.tap(find.text('聚焦此节点'));
    await tester.pumpAndSettle();
    expect(model.focusPath, _path);
  });
  testWidgets('方向键按可见顺序导航，折叠展开并限制在聚焦范围内', (tester) async {
    final model = await _mount(tester);
    for (final path in [r'$.request_id', r'$.success', r'$.data']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(model.selectedPath, path);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(model.expanded.contains(r'$.data'), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(model.expanded.contains(r'$.data'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(model.selectedPath, r'$.data.station');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(model.selectedPath, r'$.data');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(model.selectedPath, r'$.success');
    model.focus(_path);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(model.focusPath, _path);
    expect(model.selectedPath, _path);
  });

  testWidgets('折叠祖先后键盘从可见祖先继续导航', (tester) async {
    final model = await _mount(tester);
    model.select(_path);
    model.toggle(r'$.data');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(model.selectedPath, r'$.data');
    expect(model.expanded.contains(r'$.data'), isTrue);
  });

  testWidgets('右键复制字符串值、精确数字、容器与路径', (tester) async {
    final copied = <(String, String)>[];
    final model = await _mount(
      tester,
      onCopy: (value, label) async {
        copied.add((value, label));
      },
    );
    model.edit(
      r'{"name":"甲\n乙", "id":9007199254740993, "empty":null, "items":[true,1.2300]}',
    );
    expect(model.parse(), isTrue);
    await tester.pumpAndSettle();
    for (final item in [
      ('name', '复制值', '甲\n乙', '值'),
      ('name', '复制 JSON', r'"甲\n乙"', 'JSON'),
      ('id', '复制值', '9007199254740993', '值'),
      ('empty', '复制值', 'null', '值'),
      ('items', '复制路径', r'$.items', '路径'),
      ('items', '复制值', '[true,1.2300]', '值'),
    ]) {
      await _rightClick(tester, find.text(item.$1));
      await tester.tap(find.text(item.$2));
      await tester.pumpAndSettle();
      expect(copied.last, (item.$3, item.$4));
      expect(model.selectedPath, r'$');
    }
  });

  testWidgets('局部分支更新保留兄弟顺序，并处理隐藏切换、多次变更和换文档', (tester) async {
    final model = await _mount(tester);
    model.edit('{"a":{"x":{"z":1},"y":2},"b":[3,4],"c":5}');
    model.parse();
    model.expandAll(true);
    await tester.pumpAndSettle();
    Future<void> checkRows() async {
      await tester.pump();
      final paths = <String>[];
      void visit(String path) {
        paths.add(path);
        if (model.expanded.contains(path)) {
          for (final node in model.document!.nodes[path]!.children) {
            visit(node.path);
          }
        }
      }

      visit(model.focusPath);
      expect(find.text('${paths.length} 个可见节点'), findsOneWidget);
      final actual = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .map((widget) => widget.key)
          .whereType<ValueKey<String>>()
          .where((key) => key.value.startsWith('node:'))
          .map((key) => key.value.substring(5))
          .toList();
      expect(actual, paths);
    }

    await checkRows();
    model.toggle(r'$.a');
    await checkRows();
    model.toggle(r'$.a.x');
    await checkRows();
    model.toggle(r'$.a');
    await checkRows();
    model.toggle(r'$.a.x');
    model.toggle(r'$.b');
    await checkRows();
    model.focus(r'$.a');
    await checkRows();
    model.edit('{"next": [1,2]}');
    model.parse();
    await checkRows();
    await tester.pumpAndSettle();
  });
  testWidgets('键盘连续导航会滚动到屏幕外的选中节点', (tester) async {
    final model = await _mount(tester);
    model.edit('{"items": [${List.generate(80, (i) => i).join(',')}]}');
    model.parse();
    model.expandAll(true);
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(model.selectedPath, r'$.items[28]');
    expect(
      find.byKey(const ValueKey(r'node:$.items[28]')).hitTestable(),
      findsOneWidget,
    );
  });
}
